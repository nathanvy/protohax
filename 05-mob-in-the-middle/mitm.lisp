(ql:quickload :usocket)
(ql:quickload :str)

(defparameter *tonys-address* "7YWHMfk9JZe0LM0g1ZauHuiSxhI")

(defun valid-address-p (s)
  "Ignoring position, is the string a valid buttcoin address?"
  (and (str:starts-with-p "7" s)
       (>= (length s) 26)
       (<= (length s) 35)))

(defun rewrite-addresses (msg)
  (let ((substrs (str:split " " (str:trim msg) :omit-nulls t)))
    (str:concat (str:trim
		 (format nil "~{~a ~}" (loop for s in substrs
					     if (valid-address-p s)
					       do (setf s *tonys-address*)
					     collect s)))
		(format nil "~%"))))

(defun write-to-stream (stream msg)
  (write-sequence (string-to-octets msg) stream)
  (force-output stream))

(defun proxy-thread (src-sock dst-sock stdout)
  "relays messages from src to dst."
  (unwind-protect
       (let ((src (usocket:socket-stream src-sock))
	     (dst (usocket:socket-stream dst-sock))
	     (recv (make-array 1 :fill-pointer 0 :element-type '(unsigned-byte 8))))
	 (loop for b = (read-byte src nil :eof)
	       until (eq b :eof)
	       if (= b #x0a)
		 do (vector-push-extend b recv)
		    (let ((new-msg (rewrite-addresses (octets-to-string recv))))
		      (write-to-stream dst new-msg) 
		      (format stdout "~a -> ~a: ~a" src-sock dst-sock new-msg))
		    (setf recv (make-array 1 :fill-pointer 0 :element-type '(unsigned-byte 8))) 	       else
	       do (vector-push-extend b recv))
	 (force-output dst))
    (format stdout "closing ~a~%" dst-sock)
    (usocket:socket-close dst-sock)))

(defun spawn-handler (handler &rest args)
  (sb-thread:make-thread (lambda () (apply handler args))))

(defun init (&key (address "0.0.0.0") (port 42069))
  (let ((listener (usocket:socket-listen address port
					 :element-type '(unsigned-byte 8)
					 :reuse-address t)))
    (unwind-protect
	 (loop do (let ((new-clients (usocket:wait-for-input listener :ready-only t)))
		    (format t "new-clients: ~a~%" new-clients)
		    (loop for client in new-clients
			  for a = (usocket:socket-accept client)
			  for c = (usocket:socket-connect "chat.protohackers.com" 16963
							  :protocol :stream
							  :element-type '(unsigned-byte 8))
			  do (format t "~a:~a~%" a (usocket:get-peer-port a))
			     (spawn-handler #'proxy-thread a c *standard-output*)
			     (spawn-handler #'proxy-thread c a *standard-output*))))
      (usocket:socket-close listener))))

;;;; CHECK EOF handling
