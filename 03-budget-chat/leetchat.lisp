(ql:quickload :usocket)
(ql:quickload :safe-queue)
(ql:quickload :alexandria)
(ql:quickload :uuid)

(defun valid-name-p (nick)
  (let ((alphabet "1234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"))
    (if (> 1 (length nick)) (return-from valid-name-p nil))
    (if (> (length nick) 32) (return-from valid-name-p nil))
    (loop for c across nick
	  do (if (not (find c alphabet))
		 (return-from valid-name-p nil)))
    t))

(defun write-to-stream (stream msg)
  (write-sequence (string-to-octets msg) stream)
  (force-output stream))

(defun broadcast (members message &optional skip-id)
  (loop for (name stream) being the hash-values of members using (hash-key id)
        unless (equal id skip-id)
          do (when (open-stream-p stream)
               (write-line message stream)
               (force-output stream))))

(defun chat-room (channel)
  (let ((members (make-hash-table :test 'equal)))
    (loop for (command id payload) = (safe-queue:dequeue channel)
          until (eql command :terminate)
          do (case command
               (:register
                (broadcast members (format nil "* ~A has joined the room" (first payload)))
                (format (second payload) "* The room contains: ")
                (loop for (name _) being the hash-values of members
                      do (format (second payload) "~A " name))
                (terpri (second payload))
                (force-output (second payload))
                (setf (gethash id members) payload))
               (:broadcast
                (broadcast members (format nil "[~A] ~A" (first (gethash id members)) payload) id))
               (:deregister
                (broadcast members (format nil "* ~A has left the room" (first (gethash id members))))
                (remhash id members))))))

(defun chat-thread (c channel)
  (unwind-protect
    (let ((s (usocket:socket-stream c))
          (id (uuid:make-v4-uuid))
          name)
      (write-line "Please select a username:" s)
      (force-output s)
      (setf name (read-line s nil nil))
      (when (valid-name-p name)
        (safe-queue:enqueue (list :register id (list name s)) channel)
        (loop for line = (read-line s nil nil)
              while line
              do (safe-queue:enqueue (list :broadcast id line) channel))
        (safe-queue:enqueue (list :deregister id) channel)))
    (usocket:socket-close c)))

(defun spawn-handler (handle &rest args)
  (bt:make-thread (lambda () (apply handle args))))

(defun init ()
  (let ((listener (usocket:socket-listen "0.0.0.0" 42069 :element-type 'character))
        (channel (safe-queue:make-queue)))
    (unwind-protect
	 (progn (bt:make-thread (lambda () (chat-room channel)))
		(unwind-protect
		     (loop for c = (usocket:socket-accept listener)
			   do (format t "~A on port: ~A~%" c (usocket:get-peer-port c))
			      (spawn-handler #'chat-thread c channel))
		  (safe-queue:enqueue '(:terminate) channel)))
      (usocket:socket-close listener))))

