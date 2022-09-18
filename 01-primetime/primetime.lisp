(ql:quickload :usocket)
(ql:quickload :jonathan)
(ql:quickload :cl-primality)
(ql:quickload :babel)

(defparameter *halt* nil)

(defun validate-fields (ht)
  (and (string= (gethash "method" ht) "isPrime")
       (numberp (gethash "number" ht))))

;; go back to the binary version.  Newline is 0x10.  Try shitting it out to utf-8 with babel or something
(defun validate-json (str)
  "return JSON or nil if malformed"
  (handler-case
      (let ((parsed (jojo:parse str :as :hash-table)))
	(if (validate-fields parsed)
	    (return-from validate-json parsed)
	    (return-from validate-json nil)))
    (error (e)
      (format t "Ruh roh: ~a ~%" e)
      (return-from validate-json nil))))

(defun send-bogus-response (stream)
  (let ((resp (babel:string-to-octets "dank memes~%")))
    (write-sequence resp stream)
    (force-output stream)))

(defun reply-to-client (stream response)
  (let ((bool (if response "true" "false")))
    (let ((resp (babel:string-to-octets
		 (format nil "{\"method\":\"isPrime\",\"prime\":~a}~%" bool))))
      (write-sequence resp stream)
      (force-output stream))))

(defun handle-client (socket)
  (let ((s (usocket:socket-stream socket))
	(recv (make-array 1 :fill-pointer 0 :element-type '(unsigned-byte 8))))
    (loop for b = (read-byte s nil :eof)
	  until (eq b :eof)
	  if (eq b #x0a) ;; if newline
	    do (let ((json (validate-json (babel:octets-to-string recv))))
		 (when json
		   ;;request is well-formed so clear buffer before reply
		   (setf recv (make-array 1 :fill-pointer 0 :element-type '(unsigned-byte 8)))
		   (let ((n (gethash "number" json)))
		     (if (and (> n 0) (integerp n) (cl-primality:primep n))
		      (reply-to-client s t)
		      (reply-to-client s nil))))
		 (when (null json)
		   ;;request is malformed
		   (send-bogus-response s)
		   (return)))
	  else
	    do (vector-push-extend b recv))
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
  (setf *halt* nil)
  (sb-thread:make-thread
   (lambda ()
     (listen-for-connections "0.0.0.0" 42069)) :name "TCP listener"))

(defun die ()
  (setf *halt* t))
