(ql:quickload :usocket)
(ql:quickload :alexandria)
(ql:quickload :safe-queue)

(defparameter *halt* nil)
(defparameter *all-clients* (make-hash-table :synchronized t))
(defparameter *joined-clients* (make-hash-table :synchronized t))
(defparameter *log-queue* (safe-queue:make-mailbox))

(defstruct client
  (joined nil)
  (nick "")
  socket
  (msg-queue (safe-queue:make-mailbox)))

(defun valid-nick-p (nick)
  (let ((alphabet "1234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"))
    (if (> 1 (length nick)) (return-from valid-nick-p nil))
    (if (> (length nick) 32) (return-from valid-nick-p nil))
    (loop for c across nick
	  do (if (not (find c alphabet))
		 (return-from valid-nick-p nil)))
    t))

(defun send-client-message (nick msg)
  "Sends a message to a specific nick"
  (let ((c (gethash nick *joined-clients*)))
    (safe-queue:mailbox-send-message (client-msg-queue c) msg)))

(defun send-wide-message (nick msg)
  "Pass this function client's own nick."
  (let ((recipients (alexandria:hash-table-keys *joined-clients*)))
    (unless (null recipients)
      (let ((client-list (loop for r in recipients
			       if (not (string-equal nick r))
				 collect (gethash r *joined-clients*))))
	(loop for c in client-list
	      do (safe-queue:mailbox-send-message (client-msg-queue c) msg))))))

(defun handle-line (line client)
  "where line is a bytevec"
  (let ((str (octets-to-string line)))
    (cond ((and (null (client-joined client)) ;; joined == nil
		(typep (client-nick client) '(string 0)))
	   (if (valid-nick-p str)
	       (progn (setf (client-nick client) str)
		      (setf (client-joined client) t)
		      (setf (gethash (client-nick client) *joined-clients*) client)
		      (let ((joined (alexandria:hash-table-keys *joined-clients*)))
			(let ((others (loop for c in joined
					    if (not (string-equal c (client-nick client)))
					      collect c)))
			  (if others
			      (send-client-message (client-nick client)
						   (format nil "* Users: ~{~a~^, ~}~%" others))
			      (send-client-message (client-nick client)
						   (format nil "* No other users.~%")))))
		      (send-wide-message (client-nick client)
					 (format nil "* ~a has entered the chat.~%" (client-nick client))))
	       (return-from handle-line nil)))
	  (t (send-wide-message (client-nick client)
				(format nil "[~a] ~a~%" (client-nick client) str)))))
  t)

(defun write-to-stream (stream msg)
  (write-sequence (string-to-octets msg) stream)
  (force-output stream))

(defun sender-loop (client)
  (loop until *halt*
	do (let ((msg (safe-queue:mailbox-receive-message (client-msg-queue client))))
	     (write-to-stream (usocket:socket-stream (client-socket client)) msg))))

(defun handle-client (socket)
  (let ((s (usocket:socket-stream socket))
	(recv (make-array 1 :fill-pointer 0 :element-type '(unsigned-byte 8)))
	(this-client (make-client)))
    (setf (client-socket this-client) socket)
    (setf (gethash this-client *all-clients*) t)
    (write-sequence (string-to-octets
		     (format nil "Welcome to leetchat, please respond with your nick.~%") :null-terminate nil) s)
    (force-output s)
    (sb-thread:make-thread
     (lambda ()
       (sender-loop this-client)) :name "Client Sender")
    (loop for b = (read-byte s nil :eof)
	  until (eq b :eof)
	  ;;do (format t "byte is 0x~(~2,'0x~) ~%" b)
	  if (= b #x0a)
	    do (progn
		 (unless (handle-line recv this-client) (return));;if handler returns nil, break
		 (setf recv (make-array 1 :fill-pointer 0 :element-type '(unsigned-byte 8)))) 
	  else
	    do (vector-push-extend b recv))
    (safe-queue:mailbox-receive-pending-messages (client-msg-queue this-client)) ;;empty queue
    (remhash this-client *all-clients*)
    (remhash this-client *joined-clients*)
    (when (client-joined this-client)
      (send-wide-message (client-nick this-client)
			 (format nil "* ~a has left the chat.~%" (client-nick this-client))))
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
			   (handle-client accepted)) :name "Client Handler"))))
    (usocket:socket-close listener)))

(defun init ()
  (sb-thread:make-thread
   (lambda ()
     (listen-for-connections "0.0.0.0" 42069)) :name "TCP listener"))

(defun die ()
  (setf *halt* t)
  (quit))
