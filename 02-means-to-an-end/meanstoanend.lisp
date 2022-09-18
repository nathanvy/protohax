;; Byte:  |  0  |  1     2     3     4  |  5     6     7     8  |
;; Type:  |char |         int32         |         int32         |
;; Value: | 'I' |       timestamp       |         price         | ;;insert
;; Value: | 'Q' |        mintime        |        maxtime        | ;;query
(ql:quickload :usocket)
(ql:quickload :cl-intbytes)
(ql:quickload :alexandria)

(defstruct msg
  type
  int-a
  int-b)

(defparameter *halt* nil)

(defun insert (timestamp price db)
  "returns nil if price already exists in db so that we can disco the client in the caller"
  (if (gethash timestamp db) (return-from insert nil) (setf (gethash timestamp db) price)))

(defun query (timestamp1 timestamp2 db)
  (if (> timestamp1 timestamp2) (return-from query 0)) ;;per the spec
  (let ((timestamps (alexandria:hash-table-keys db)))
    (if (zerop (length timestamps))
	(return-from query 0))
    (let ((sorted (sort timestamps #'<)))
      (let ((t1 (find-if (lambda (ts)
			   (<= timestamp1 ts)) sorted))
	    (t2 (find-if (lambda (ts)
			   (>= timestamp2 ts)) (reverse sorted))))
	(when (null t1) ;; when timestamp1 > last item in list
	  (return-from query 0))
	(when (null t2)
	  (return-from query 0))
	(let ((keylist (subseq sorted (position t1 sorted) (1+ (position t2 sorted)))))
	  (loop for key in keylist
		collect (let ((v (gethash key db)))
			  (if v v 0)) into vals
		finally (progn
			  (if (zerop (length vals)) (return-from query 0))
			  (let ((sum (reduce #'+ vals :initial-value 0))
				(divisor (coerce (length vals) 'double-float)))
			    (return-from query (floor (/ sum divisor)))))))))))

(defun octets-to-int (vec)
  (cl-intbytes:octets->int32 (reverse vec)))

(defun tni-ot-stetco (int)
  (reverse (cl-intbytes:int32->octets int)))

(defun handle-client (socket)
  (let ((s (usocket:socket-stream socket))
	(db (make-hash-table))
	(recv (make-array 1 :fill-pointer 0 :element-type '(unsigned-byte 8))))
    (loop for b = (read-byte s nil :eof)
	  until (eq b :eof)
	  do (vector-push-extend b recv)
	  do (when (= (length recv) 9)
	       (let ((msg (make-msg :type (elt recv 0)
				    :int-a (octets-to-int (subseq recv 1 5))
				    :int-b (octets-to-int (subseq recv 5 9)))))
		 (setf recv (make-array 1 :fill-pointer 0 :element-type '(unsigned-byte 8)))
		 (cond
		   ((= (msg-type msg) #x49)
		    (if (not (insert (msg-int-a msg) (msg-int-b msg) db)) (return)))
		   ;; the above line returns if insert returns nil because the client hit UB
		   ((= (msg-type msg) #x51)
		    (progn
		      (let ((mean (query (msg-int-a msg) (msg-int-b msg) db)))
			(write-sequence (tni-ot-stetco mean) s)
			(force-output s))))
		   (t (return))) ;;disconnect if they trigger UB
		 )))
    (usocket:socket-close socket)))

(defun listen-for-connections (host port)
  (let ((listener (usocket:socket-listen host
					 port
					 :reuse-address t
					 :element-type '(unsigned-byte 8))))
    (loop until *halt*
	  do (let ((new-clients (usocket:wait-for-input listener :ready-only t)))
	       (loop for client in new-clients
		     for accepted = (usocket:socket-accept client)
		     do (sb-thread:make-thread
			 (lambda ()
			   (handle-client accepted))))))
    (usocket:socket-close listener)))

(defun init ()
  (sb-thread:make-thread
   (lambda ()
     (listen-for-connections "0.0.0.0" 42069)) :name "TCP listener"))

(defun die ()
  (setf *halt* t))
