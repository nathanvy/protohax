(ql:quickload :usocket)
(ql:quickload :safe-queue)
(ql:quickload :str)

(defparameter *version* "v4.20.69")
(defparameter *db* (make-hash-table :synchronized t :test #'equal))
(defparameter *queue* (safe-queue:make-mailbox))

(defun insert (k v)
  (setf (gethash k *db*) v))

(defun retrieve (k)
  (when (string= k "version")
    (return-from retrieve (format nil "version=~a" *version*)))
  (let ((v (gethash k *db*)))
    (if v
	(format nil "~a=~a" k v)
	(format nil "~a=" k))))

(defun send-response (msg sock remote-host remote-port)
  (let ((bytes (string-to-octets msg :null-terminate nil)))
    (usocket:socket-send sock bytes (length bytes) :host remote-host :port remote-port)))

(defun handle-input (payload sock)
  (let ((buf (first payload))
	(len (second payload))
       	(remote-host (third payload))
	(remote-port (fourth payload)))
    (let ((msg (octets-to-string buf :start 0 :end len)))
      (if (str:containsp "=" msg)
	  (let ((kv (str:split "=" msg :limit 2)))
	    (insert (first kv) (second kv)))
	  (let ((r (retrieve msg)))
	    (send-response r sock remote-host remote-port))))))

(defun ingress-loop (sock)
  (loop do (multiple-value-bind (recv len remote-host remote-port)
	       (usocket:socket-receive sock nil 1000)
	     (safe-queue:mailbox-send-message *queue* (list recv len remote-host remote-port)))))

(defun egress-loop (sock)
  (loop for msg = (safe-queue:mailbox-receive-message *queue*)
	do (handle-input msg sock)))

(defun init ()
  (let ((listener (usocket:socket-connect nil nil
					  :protocol :datagram
					  :element-type '(unsigned-byte 8)
					  :local-host "0.0.0.0"
					  :local-port 42069)))
    (sb-thread:make-thread (lambda ()
			     (ingress-loop listener))
			   :name "Ingress")
    (sb-thread:make-thread (lambda ()
			     (egress-loop listener))
			   :name "Egress")))
