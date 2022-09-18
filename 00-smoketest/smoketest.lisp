;;This is a very simple multithreaded TCP echo server that conforms to the problem spec
;;It waits until it gets an EOF and then dumps all received data back to the sender verbatim.
;;
;;This file is meant to be invoked via:
;; $ sbcl --load smoketest.lisp
;;
;;Yes I'm aware of quicklisp local projects and ASDF but /shrug
;; https://0x85.org/multithreading.html

(ql:quickload :usocket)

(defparameter *halt* nil)

(defun handle-client (socket)
  (let ((s (usocket:socket-stream socket))
	(recv (make-array 1 :fill-pointer 0 :element-type '(unsigned-byte 8))))
    (loop for b = (read-byte s nil :eof)
	  until (eq b :eof)
	  ;;do (format t "byte is 0x~(~2,'0x~) ~%" b)
	  do (vector-push-extend b recv))
    (unless (zerop (length recv))
      (loop for b across recv
	    do (write-byte b s))
      (force-output s))
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
