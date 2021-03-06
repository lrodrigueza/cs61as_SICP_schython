;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; File: PY-META.SCM
;; Author: Hoa Long Tam (hoalong.tam@berkeley.edu)
;; Large parts adapted for use in as a Python-in-Scheme interpreter for use in
;; UC Berkeley's intro to computer science course, CS 61A from a Logo-in-Scheme
;; interpreter written by Brian Harvey (bh@cs.berkeley.edu), available at
;; ~cs61a/lib/logo-meta.scm, and the Metacircular Evaluator, a Scheme-in-Scheme
;; interpreter written by Harold Abelson and Gerald Jay Sussman, published in
;; the Structure and Interpretation of Computer Programs (1996, Cambridge, MA:
;; MIT Press).  Particular thanks go to Michael C Chang for ideas on how to
;; handle nested indented blocks.  Thanks also to Jon Kotker, for suggesting the
;; project and writing the specification, Christopher Cartland, for testing
;; and debugging, and George Wang, for testing and administrative support.
;;
;; REVISION HISTORY
;; 2.  July 30th, 2010.  Code added for 'else'-blocks to ensure equitable
;;                       distribution of work.
;; 1.  July 27th, 2010.  Project released.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Spring 2014 CS61AS revisions
;;
;; edits made by Saam Barati  <saamyjoon@berkeley.edu>
;;           and Marion Halim <marionhalim@berkeley.edu>
;; from tests conducted while solving the project
;;
;; 1. We altered many places where `parser.scm` relied on a `cons` statement evaluating its arguments
;;    from the left to the right, but cons statements in STk evaluate the right argument first.
;;    i.e (cons (display 1) (display 2)) prints `2` then `1`
;;
;; 2. Move function application detection into eval-item instead of handle-infix because, logically speaking,
;;    the application of `foo()` is one item to be evaluated.
;;    (This also fixes the following bug: `>>> 2 * foo()`)
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define **DEBUGGING** #t) ;**** #t - dump errors back into scheme

;; Read-Eval-Print Loop
(define (driver-loop)
  (define (repl)
    (prompt ">>> ")
    (if (eof-object? (peek-char))
	(begin (newline) 'bye)
	(let ((line-obj (make-line-obj (py-read))))
	  (if (ask line-obj 'exit?)
	      'bye
	      (begin (py-print (eval-line line-obj the-global-environment))
		     (repl))))))
  (read-char)
  (if **DEBUGGING**
      (repl)
      (while (catch (repl)) '*IGNORE-ME*))  ;**** what does CATCH do???
  'bye)

;; Only display prompt if reading user input from standard input.
(define tty-port (current-input-port))
(define (prompt str)
  (if (eq? (current-input-port) tty-port)
      (begin (display str) (flush) *NONE*)
      *NONE*))

;; Check that the line has zero indentation then check nothing is left over
;; after sending the line to py-eval.
(define (eval-line line-obj env)
  (if (ask line-obj 'empty?)
     *NONE*
      (if (zero? (ask line-obj 'indentation))
	  (let ((val (py-eval line-obj env)))
	    (if (not (ask line-obj 'empty?))
		(py-error "SyntaxError: multiple statements on one line")
		val))
	  (py-error "IndentationError: unexpected indent"))))

;; Starts the infix/item evaluator loop
(define (py-eval line-obj env)
  (handle-infix (eval-item line-obj env) line-obj env))

;; Calculates the first python object on the line-obj.
(define (eval-item line-obj env)
  (if (ask line-obj 'empty?)
      *NONE*
      (let ((token (ask line-obj 'next)))
	(cond ((string? token) (make-py-string token))
	      ((number? token) (make-py-num token))
	      ((bool? token) (make-py-bool token))
	      ((none? token) *NONE*)
	      ((unary-op? token) (apply-unary token (eval-item line-obj env))) ;**?
	      ((block? token) (eval-block token env))
	      ((if? token)  ;;;;IF
	       (let ((block (make-if-block line-obj env)))
		 (ask line-obj 'push block)
		 (py-eval line-obj env)))
	      ((for? token) ;;;;FOR
	       (let ((block (make-for-block line-obj env)))
		 (ask line-obj 'push block)
		 (py-eval line-obj env)))
	      ((while? token) ;;;;WHILE
	       (let ((block (make-while-block line-obj env)))
                 (ask line-obj 'push block)
                 (py-eval line-obj env)))
	      ((def? token)
	       (let ((block (make-def-block line-obj env)))
                 (ask line-obj 'push block)
                 (py-eval line-obj env)))
	      ((open-paren? token)
	       (let ((sub (collect-sequence line-obj env close-paren-symbol)))
			 (if (null? (cdr sub))
				 (car sub)
				 (py-error "SyntaxError: tuples not implemented"))))
	      ((print? token) (py-print (py-eval line-obj env)))
	      ((return? token)
	       (cons '*RETURN*
		     (py-eval line-obj env)))
	      ((break? token) '*BREAK*)
	      ((continue? token) '*CONTINUE*)
	      ((lambda? token) (eval-lambda line-obj env))
	      ((import? token) (eval-import line-obj))
	      ((raise? token) (eval-raise line-obj env))
	      ((open-bracket? token)                                
	       (if (memq 'for (ask line-obj 'tokens))
		   (eval-list-comp line-obj env)
		   (make-py-list

		    (collect-sequence line-obj env close-bracket-symbol))))   
	      ((open-brace? token)
	       (make-py-dictionary
		(collect-key-value line-obj env close-brace-symbol)))
    ;; handle both value dereferences and value assignments of lists and 
    ;; dictionaries. This breaks the handle-infix model for assignments but 
    ;; is the cleanest way to solve the lookahead problem
		   ;;(dict['hello']) or (list[0]) or (list[x] = y)
		  ((bracket-dereference? token line-obj)
		   (let ((val (lookup-variable-value token env)))
		     (ask line-obj 'next) ;; remove '[' token
		     (define key #f)
		     (cond
		      ((py-list? val)
		       (set! key (get-slice line-obj env))) ;;get the list slice
		      ((py-dict? val)
		       (set! key 
			     (eval-inside-delimiters 
			      line-obj env 
			      open-bracket-symbol 
			      close-bracket-symbol))) ;;get the dictionary key
		      (else (print (ask val 'type))
			    (print val)
			    (print (py-list? val))
			    (print (py-dict? val))
			    (py-error "token not subscriptable")))
		     
		     (if (and (not (ask line-obj 'empty?))
			      (eq? (ask line-obj 'peek) '=))
			 (begin (ask line-obj 'next) ;; remove '=' token
				;;set item in dict or list
				(ask val '__setitem__ key (py-eval line-obj env))) 
			 (ask val '__getitem__ key))))
		  ((assignment? token line-obj)
		   (define-variable! token (py-eval line-obj env) env)
		   *NONE*)
		  ((application? token line-obj) 
;;application? must come before variable? 
;;because both applications and variables start with strings: i.e: foo and foo()
		   ;variable name, i.e, fib in fib()
		   (let ((func (lookup-variable-value token env))) 
		     (eval-func func line-obj env)))
		  ((variable? token)
		   (let ((val (lookup-variable-value token env)))
		      ;variable lookup
		     (if val val (py-error "NameError: Unbound variable: " token))))
		  (else (py-error "SyntaxError: Unrecognized token: " token))))

      )  )   ;; end EVAL-ITEM

;; Prints a python object.
(define (py-print obj)
  (if (not (none? obj))
      (if (ask obj 'string?)
	  (print (ask obj 'val))
	  (begin (display (ask (ask obj '__str__) 'val)) (newline))))
  *NONE*)

;; Selectors for py-eval
(define (bool? token) (memq token '(|True| |False|)))
(define (none? token)
  (or (eq? token *NONE*)
      (eq? token '|None|)))
(define (if? token) (eq? token 'if))
(define (for? token) (eq? token 'for))
(define (while? token) (eq? token 'while))
(define (def? token) (eq? token 'def))
(define (print? token) (eq? token 'print))
(define (assignment? token line-obj)
  (and (variable? token)
       (not (ask line-obj 'empty?))
       (let ((next (ask line-obj 'peek)))
	 (if (eq? next '=)
	     (begin (ask line-obj 'next) #t)
	     #f))))
(define (variable? token) (symbol? token))
(define (application? token line-obj)
  ;;  handle -> fib(10)
  (and (variable? token)
       (not (ask line-obj 'empty?))
       (open-paren? (ask line-obj 'peek))))
(define (bracket-dereference? token line-obj) ;;  dict["hello"] and list[0]
  (and (variable? token)
       (not (ask line-obj 'empty?))
       (open-bracket? (ask line-obj 'peek))))
(define (return? token) (eq? token 'return))
(define (break? token) (eq? token 'break))
(define (continue? token) (eq? token 'continue))
(define (block? token) (and (pair? token) (eq? (car token) '*BLOCK*)))
(define (lambda? token) (eq? token 'lambda))
(define (import? token) (eq? token 'import))
(define (raise? token) (eq? token 'raise))
(define (not? token) (eq? token 'not))
;; Infix Handling
(define infix-alist
  '((+ . __add__) (- . __sub__) (*  . __mul__)
    (/ . __div__) (% . __mod__) (** . __pow__)
    (> . __gt__)  (>= . __ge__) (== . __eq__)
    (< . __lt__)  (<= . __le__) (!= . __ne__)))

;; Infix selectors
(define infix-operators (map car infix-alist))
(define (infix-op? token) (memq token infix-operators))
(define (lookup-op op) (cdr (assq op infix-alist)))

;; Takes the last value returned from py-eval and applies the next infix
;; operator, if there is one.  Also checks for list slices and procedure calls
(define (handle-infix val line-obj env)
  (if (ask line-obj 'empty?)
      val
      (let ((token (ask line-obj 'next)))
	(cond ((infix-op? token) ;; arithmetic infix operators
	       (let ((rhs (eval-item line-obj env)))
		 (handle-infix (py-apply (ask val (lookup-op token))
					 (list rhs))
			       line-obj
			       env)))
   ;;;; B[#5] IN?
   ;; checks if the variable TOKEN (the nest token in line) is "in"
	      ((in? token)
	       (let ((next-list (eval-item line-obj env)))
		 (ask next-list '__contains__ val)))
	      		 
   ;;;; B[#5] NOT?	      
	      ((not? token)
	       (let ((in-token? (ask line-obj 'next)))
		 (if (in? in-token?)
		     (let ((next-list (eval-item line-obj env)))
		       (negate-bool (ask next-list '__contains__ val)))) ))
		       
	      ;; logical infix operators
   ;;;; A[#5] AND
	      ((and? token)
	       (if (ask val 'true?)
		   (py-eval line-obj env)
		   (begin (eat-tokens line-obj)
       		  *PY-FALSE*)))
   ;;;; A[#5] OR
       	      ((or? token)
	       (if (ask val 'true?)
		   (begin (eat-tokens line-obj)
			  val)
		   (py-eval line-obj env)))

	      ;; test for membership
    
 	      ;; dot syntax message: val.msg
        ((dotted? token)
          (let ((func (ask val (remove-dot token))))      ;gets the py-function
            (if (and (not (ask line-obj 'empty?))
		     ;IF IT IS ACTUALLY A FUNCTION CALL, EVALUATE IT
                     (open-paren? (ask line-obj 'peek))) 
 ; make sure to continue handling infix: i.e -> if list.length() > 10: -> evaluate the `> 10` portion
                (handle-infix (eval-func func line-obj env) line-obj env)
		;OTHERWISE RETURN THE FUNCTION ITSELF
                (handle-infix func line-obj env)))) 
	      (else (begin (ask line-obj 'push token)
			   val))))))

;; Infix selectors
(define (and? token) (eq? token 'and))
(define (or? token) (eq? token 'or))
(define (in? token) (eq? token 'in))
(define (is? token) (eq? token 'is))
(define (dotted? token) (equal? (first token) '.))
(define (remove-dot token)
  (let ((tail (butfirst token)))
    (if (string? tail)
	(string->symbol tail)
	tail)))

;; Lists
(define (open-bracket? token) (eq? token open-bracket-symbol))
(define (close-bracket? token) (eq? token close-bracket-symbol))

;; Dictionaries
(define (open-brace? token) (eq? token open-brace-symbol))
(define (close-brace? token) (eq? token close-brace-symbol))

;; Procedures
(define (open-paren? token) (eq? token open-paren-symbol))
(define (close-paren? token) (eq? token close-paren-symbol))
(define (py-primitive? proc) (ask proc 'primitive?))
(define (py-procedure? proc) (ask proc 'procedure?))
(define (py-apply proc args)
  (cond ((py-primitive? proc) (ask proc '__call__ args))
	((py-procedure? proc) (ask proc '__call__ args))
	(else (py-error "TypeError: cannot call objects of type: "
			(ask proc 'type)))))


;; accepts a line-obj with opening delimiter removed
;; returns evaluating inside something, removes the closing delimiter from line-obj
(define (eval-inside-delimiters line-obj env open-delim close-delim)
  ;; hanlde both [ x y x ] and dict[dict1[dict2[x]]]
  ;; count keeps track of balance of braces
  ;;collect the tokens inside two delimiters
  (define (collect line-obj count)
    (if (= count 0)
      '()
      (let ((t (ask line-obj 'next)))
        (cond
          ((eq? t close-delim)
            (cons t (collect line-obj (- count 1))))
          ((eq? t open-delim)
            (cons t (collect line-obj (+ count 1))))
          (else (cons t (collect line-obj count)))))))
  (let* ((inner-tokens (collect line-obj 1))
         (inside-line (make-line-obj (cons '*DUMMY-INDENT* inner-tokens))))
    (py-eval inside-line env)))

(define (collect-sequence line-obj env close-token)
  (let ((token (ask line-obj 'next)))
    (cond
      ((eq? token close-token) '())
      ((comma? token) (collect-sequence line-obj env close-token))
      (else
       (ask line-obj 'push token)                                        
       (let ((obj (py-eval line-obj env)))
			(cons obj
			   (collect-sequence line-obj env close-token)))))))


 
(define (collect-key-value line-obj env close-token)  ;; Common-8
  (let ((token (ask line-obj 'next)))
    (cond ((eq? token close-token) '())
	  ((comma? token) (collect-key-value line-obj env close-token)) 
	  (else                                    ;; must be beginning of a new pair
	   (ask line-obj 'push token)              ;; push key to begining of token list
	   
	   (let ((key (py-eval line-obj env)))     ;; evaluate the key, and actually eats until colon
	     (if (colon? (ask line-obj 'peek))     ;; sanity check for colon after key
		 (begin (ask line-obj 'next)       ;; eat the colon
			(let ((valu (py-eval line-obj env)))        ;; evaluate the key
			  (cons (cons key valu)                          ;; cons key and valu together
				(cond ((comma? (ask line-obj 'peek))     ;; sanity check to see if comma is before next kv-pair
				       (collect-key-value line-obj env close-token)) ;; if it is, then recursive call fxn
				      ((eq? (ask line-obj 'peek) close-token) 
				       (begin (ask line-obj 'next)    ;; need line-obj to be empty in order to return '()
					      '()))                   ;; if it is last kv-pair, then return empty list
				      (else (py-error "SyntaxError: Expected comma to separate key-value pairs")))))) ;; if no comma, then py-error 
		 (py-error "SyntaxError: Expected colon to separate key and value")))))))
		




;; Variables and Assignment: taken mostly from Abelson and Sussman's
;; Metacircular Evaluator (SICP, Chapter 4)
(define (enclosing-environment env) (cdr env))

(define (first-frame env) (car env))

(define (make-frame variables values)
  (cons variables values))

(define (frame-variables frame) (car frame))

(define (frame-values frame) (cdr frame))

(define (add-binding-to-frame! var val frame)
  (set-car! frame (cons var (car frame)))
  (set-cdr! frame (cons val (cdr frame))))

(define (extend-environment vars vals base-env)
  (if (= (length vars) (length vals))
      (cons (make-frame vars vals) base-env)
      (if (< (length vars) (length vals))
          (py-error "Too many arguments supplied " vars " " vals)
          (py-error "Too few arguments supplied " vars " " vals))))

(define the-empty-environment '())

(define (lookup-variable-value var env)
  (define (env-loop env)
    (define (scan vars vals)
      (cond ((null? vars)
             (env-loop (enclosing-environment env)))
            ((eq? var (car vars))
             (car vals))
            (else (scan (cdr vars) (cdr vals)))))
    (if (eq? env the-empty-environment)
	#f
        (let ((frame (first-frame env)))
          (scan (frame-variables frame)
                (frame-values frame)))))
  (env-loop env))

(define (set-variable-value! var val env)
  (define (env-loop env)
    (define (scan vars vals)
      (cond ((null? vars)
             (env-loop (enclosing-environment env)))
            ((eq? var (car vars))
             (set-car! vals val))
            (else (scan (cdr vars) (cdr vals)))))
    (if (eq? env the-empty-environment)
        (py-error "NameError: Unbound variable " var)
        (let ((frame (first-frame env)))
          (scan (frame-variables frame)
                (frame-values frame)))))
  (env-loop env)
  *NONE*)

(define (define-variable! var val env)
  (let ((frame (first-frame env)))
    (define (scan vars vals)
      (cond ((null? vars)
             (add-binding-to-frame! var val frame))
            ((eq? var (car vars))
             (set-car! vals val))
            (else (scan (cdr vars) (cdr vals)))))
    (scan (frame-variables frame)
          (frame-values frame)))
  *NONE*)

(define the-global-environment the-empty-environment)
(define (initialize-python)
  (set! the-global-environment (extend-environment '() '() '()))
  (define-variable! '__name__
    (make-py-string "__main__")
    the-global-environment)
  (define-primitives!)
  (driver-loop))


;; Blocks, Loops, Procedures

(define unindented-line #f)
(define read-block
  ;; Read-block is a procedure of two arguments.  Old-indent is the indentation
  ;; (as a Scheme number) to check against for dedents (mostly for else and elif
  ;; blocks).  Env is the current environment, used for evaluating define
  ;; blocks.  It returns a list of lines (Scheme list of lists, NOT line-objs!).
  (let ((unindented-line #f)) 
    (lambda (old-indent env)
      (let ((new-indent #f))
	(define (read-loop)
	  (prompt "... ")
	  (let ((line (py-read)))
	    (define (helper)
	      (if (not new-indent) (set! new-indent (indentation line)))
	      (cond ((null? (tokens line)) (set! unindented-line #f) '())
		    ((> (indentation line) new-indent)
		     (py-error "SyntaxError: Unexpected indent"))
		    ((< (indentation line) new-indent)
		     (if (and (= (indentation line) old-indent)
			      (not (null? (tokens line)))
			      (memq (car (tokens line)) '(elif else)))
			 (let ((trailing-block (make-block (make-line-obj line)
							   env)))
			   (if (not unindented-line)
			       (list trailing-block)
			       (begin (set! line unindented-line)
				      (set! unindented-line #f)
				      (cons trailing-block (helper)))))
			 (begin (set! unindented-line line)
				'())))
		    ((memq (car (tokens line)) '(def if for while))
		     (let ((nested-block (make-block (make-line-obj line) env)))
		       (if (not unindented-line)
			   (list nested-block)
			   (begin (set! line unindented-line)
				  (set! unindented-line #f)
				  (cons nested-block (helper))))))
		    (else (cons line (read-loop)))))
	    (helper)))
	(read-loop)))))

;;evaluate function calls
(define (eval-func func line-obj env)
  (ask line-obj 'next) ;eats the open paren
  (py-apply func (collect-sequence line-obj env close-paren-symbol)))

;; Evaluates a block, line-by-line
(define (eval-sequence block env)
  (if (null? block)
      *NONE*
      (let ((line-obj (make-line-obj (car block))))
	(let ((val (py-eval line-obj env)))
	  (if (not (ask line-obj 'empty?))
	      (py-error "SyntaxError: Too many tokens on one line")
	      (cond ((and (pair? val) (eq? (car val) '*RETURN*)) val)
		    ((memq val '(*BREAK* *CONTINUE*)) val)
		    (else (eval-sequence (cdr block) env))))))))

;; Block selectors
(define (block-body block) (cdr block))
(define (block-type block) (cadr block))
(define (if-block? block) (eq? (block-type block) '*IF-BLOCK*))
(define (def-block? block) (eq? (block-type block) '*DEF-BLOCK*))
(define (for-block? block) (eq? (block-type block) '*FOR-BLOCK*))
(define (elif-block? block) (eq? (block-type block) '*ELIF-BLOCK*))
(define (else-block? block) (eq? (block-type block) '*ELSE-BLOCK*))
(define (while-block? block) (eq? (block-type block) '*WHILE-BLOCK*))
(define (eval-block block env)
  (cond ((if-block? block) (eval-if-block block env))
	((def-block? block) (eval-def-block block env))
	((for-block? block) (eval-for-block block env))
	((elif-block? block) (eval-elif-block block env))
	((else-block? block) (eval-else-block block env))
	((while-block? block) (eval-while-block block env))
	(else (py-error "SyntaxError: bad block type: " (block-type block)))))
(define (split-block block)
  ;; Split block takes a list of lines and checks if the last line is a else
  ;; or elif block.  If so, it returns a pair whose car is a list of all but
  ;; that last line and whose cdr is the elif or else block.  If there is no
  ;; such trailing elif or else block, it returns (cons block #f).
  (define (iter so-far to-go)
    (let ((current-line (tokens (car to-go)))
	  (rest (cdr to-go)))
      (if (null? rest)
	  (if (and (block? (car current-line))
		   (or (elif-block? (car current-line))
		       (else-block? (car current-line))))
	      (cons (reverse so-far) (car to-go))
	      (cons (reverse (cons (car to-go) so-far)) #f))
	  (iter (cons (car to-go) so-far) rest))))
  (iter '() block))

;; Block constructor
(define (make-block line-obj env)
  (let ((type (ask line-obj 'next)))
    (cond ((eq? type 'if) (list '*DUMMY-INDENT* (make-if-block line-obj env)))
	  ((eq? type 'for) (list '*DUMMY-INDENT* (make-for-block line-obj env)))
	  ((eq? type 'def) (list '*DUMMY-INDENT* (make-def-block line-obj env)))
	  ((eq? type 'elif) (list '*DUMMY-INDENT* (make-elif-block line-obj env)))
	  ((eq? type 'else) (list '*DUMMY-INDENT* (make-else-block line-obj env)))
	  ((eq? type 'while) (list '*DUMMY-INDENT* (make-while-block line-obj env)))
	  (else (py-error "SyntaxError: unknown keyword: " type)))))

;; Conditionals


(define (make-if-block line-obj env)
(define (helper-if line-obj lst)
  (if (colon? (ask line-obj 'peek))
       (begin (ask line-obj 'next)
       lst)
	 (helper-if line-obj (append lst (list (ask line-obj 'next))))))

(let ((helper-pred-if (cons (ask line-obj 'indentation) (helper-if line-obj '())))
      (if-body (read-block (ask line-obj 'indentation) env)))
(list '*BLOCK* '*IF-BLOCK* helper-pred-if (split-block if-body))))
(define (if-block-pred block)
 (caddr block))
(define (if-block-body block)
  (car (cadddr block)))
(define (if-block-else block)
  (cdr (cadddr block)))

(define (eval-if-block block env)
(let (( py-obj-if (py-eval (make-line-obj (if-block-pred block)) env)))

  (if (ask py-obj-if 'true?)
      (eval-sequence (if-block-body block) env)
      (if (equal? (if-block-else block) #f)
	  *NONE*

	  (eval-item (make-line-obj (if-block-else block)) env)))))
  

;; Elif/Else blocks
(define (make-else-block line-obj env)
  (if (not (and (not (ask line-obj 'empty?))
		(eq? (ask line-obj 'next) ':)
		(ask line-obj 'empty?)))
      (py-error "SyntaxError: invalid syntax")
      (let ((body (read-block (ask line-obj 'indentation) env)))
	(list '*BLOCK* '*ELSE-BLOCK* (split-block body)))))
(define (else-block-body block) (caaddr block))
(define (else-block-else block) (py-error "SyntaxError: too many else clauses"))

(define (eval-else-block block env)
  (eval-sequence (else-block-body block) env))

(define (make-elif-block line-obj env)
  
  (define (helper-elif line-obj lst)
  (if (colon? (ask line-obj 'peek))
       (begin (ask line-obj 'next)
       lst)
	 (helper-elif line-obj (append lst (list (ask line-obj 'next))))))

(let ((helper-pred-elif (cons (ask line-obj 'indentation) (helper-elif line-obj '())))
      (elif-body (read-block (ask line-obj 'indentation) env)))
 (list '*BLOCK* '*ELIF-BLOCK* helper-pred-elif (split-block elif-body))))
(define (elif-block-pred block)
   (caddr block))
(define (elif-block-body block)
  (car (cadddr block)))
(define (elif-block-else block)
 (car (cdr (cdr (cadddr block)))))
(define (eval-elif-block block env)
    (set-car! (cdr block) '*IF-BLOCK*)
  (eval-if-block block env))
















#|
   ;;;; B[#7] CONDITIONAL: IF part 1
(define (make-if-block line-obj env)
  (py-error "TodoError: Person B, Question 7"))
(define (if-block-pred block)
  (py-error "TodoError: Person B, Question 7"))
(define (if-block-body block)
  (py-error "TodoError: Person B, Question 7"))
(define (if-block-else block)
  (py-error "TodoError: Person B, Question 7"))

(define (eval-if-block block env)
  (py-error "TodoError: Person B, Question 7"))

;; Elif/Else blocks
(define (make-else-block line-obj env)
  (if (not (and (not (ask line-obj 'empty?))
		(eq? (ask line-obj 'next) ':)
		(ask line-obj 'empty?)))
      (py-error "SyntaxError: invalid syntax")
      (let ((body (read-block (ask line-obj 'indentation) env)))
	(list '*BLOCK* '*ELSE-BLOCK* (split-block body)))))
(define (else-block-body block) (caaddr block))
(define (else-block-else block) (py-error "SyntaxError: too many else clauses"))

(define (eval-else-block block env)
  (eval-sequence (else-block-body block) env))

   ;;;; B[#7] CONDITIONAL: ELIF part2
(define (make-elif-block line-obj env)
  (py-error "TodoError: Person B, Question 7"))
(define (elif-block-pred block) (py-error "TodoError: Person B, Question 7"))
(define (elif-block-body block) (py-error "TodoError: Person B, Question 7"))
(define (elif-block-else block) (py-error "TodoError: Person B, Question 7"))

(define (eval-elif-block block env)
  (py-error "TodoError: Person B, Question 7"))




|#




;; Procedure definitions
(define (make-def-block line-obj env)
  (let ((name (ask line-obj 'next))
	(params (begin (ask line-obj 'next) (collect-params line-obj env))))
    (if (or (ask line-obj 'empty?)
	    (not (eq? (ask line-obj 'next) ':)))
	(py-error "SyntaxError: Expected \":\"")
	(let ((body (read-block (ask line-obj 'indentation) env)))
	  (list '*BLOCK* '*DEF-BLOCK* (cons name params) body)))))
(define (def-block-name block) (caaddr block))
(define (def-block-params block) (cdaddr block))
(define (def-block-body block) (cadddr block))

(define (collect-params line-obj env)
  (if (ask line-obj 'empty?)
      (py-error "SyntaxError: Expected \")\"")
      (let ((token (ask line-obj 'next)))
	(cond ((eq? token close-paren-symbol) '())
	      ((comma? token) (collect-params line-obj env))
	      ((eq? (ask line-obj 'peek) '=)
	       (py-error "ExpertError: Default Parameters"))
	      (else (cons token (collect-params line-obj env)))))))

(define (eval-def-block block env)
  (let ((proc (make-py-proc (def-block-name block)
			    (def-block-params block)
			    (def-block-body block)
			    env)))
    (define-variable! (def-block-name block) proc env)))

;; While loops
    ;;;; Comm[#6]   WHILE

;;;;;;;;;;;;  PERSON A
(define (make-while-block line-obj env)
  (let ((pred (collect-pred line-obj env))
	(body (read-block (ask line-obj 'indentation) env)))
    (list '*BLOCK* '*WHILE-BLOCK* pred body)))

(define (collect-pred line-obj env)
  (define (helper line-obj env)            ;; this grabs everything before colon
    (let ((token (ask line-obj 'next)))    ;; grabs first thing suppposedly after while
      (if (colon? token)                   ;; checks if its a colon
	  '()                              ;; return empty list, because don't want colon
	  (cons token (helper line-obj env))))) ;; makes a list of tokens, starts with token
  (let ((indent (ask line-obj 'indentation))) ;; this is to grab the indentation, 
                                              ;;; i think after the while? this is wrong..?
    (cons indent (helper line-obj env)))) ;; return a list of the indent plus list of tokens

(define (while-block-pred block)
  (caddr block))                       ;; grabs the third item of the list 
(define (while-block-body block)       ;; assume selecting from (*BLOCK* *WHILE-BLOCK* ..)
  (car (split-block (cadddr block))))  ;; grab block, split-it, then take the car which is body
(define (while-block-else block)       ;; grab block, split-it, take cdr [SINCE SPLIT BLOCK 
                                       ;; RETURNS A PAIR], which is the else
  (cdr (split-block (cadddr block))))  ;; this will be #f if there is no else 


;;;;;;;;;;;;  Comm[#6] implemented for persons A and B

(define (eval-while-block block env)
  (let ((pred (while-block-pred block))
	(body (while-block-body block))
	(else-clause (while-block-else block)))
    (let ((should-eval-if else-clause))
      (define (loop)
	(let ((bool-value (py-eval (make-line-obj pred) env)))
	  (if (ask bool-value 'true?)
	      (let ((result (eval-sequence body env)))
		(cond ((eq? result '*BREAK*) (set! should-eval-if #f) *NONE*)
		      ((and (pair? result) (eq? (car result) '*RETURN*)) result)
		      (else (loop))))
	      (if should-eval-if
		  (eval-item (make-line-obj else-clause) env)
		  *NONE*))))
      (loop))))


;; For loops
;;;; For loop constructors

;; try to with one less parameter in for-block list 
(define (make-for-block line-obj env)             ;; creates a FOR-BLOCK
  (let ((var (ask line-obj 'next))                ;; for is eaten, so next token is variable
	(collection (begin (ask line-obj 'next)   ;; eat the variable
			   (collect-collection line-obj env)))  ;; finally at the collection
	(body (read-block (ask line-obj 'indentation) env)))
    (list '*BLOCK* '*FOR-BLOCK* (cons var collection) body))) ;; final FOR-BLOCK 


;; helper to collect collection
(define (collect-collection line-obj env)         ;; grabs collection before the colon
  (let ((token (ask line-obj 'next)))             ;; grabs first token of collection (after in)
    (if (colon? token)                            ;; checks if at the end of collection
	'()
	(cons token (collect-collection line-obj env))))) ;; starts making a token list of coll

;;;; For loop selectors 
;;;; assume working with (*BLOCK* *FOR-LOOP* ... ) 
(define (for-block-var block)                     ;; return the 3rd item of list
  (caaddr block))                          
(define (for-block-collection block)              ;; return the 4th item of list   
  (cdaddr block))                      
(define (for-block-body block)                    ;; return the car (body) of 5th item of list
  (car (split-block (cadddr block))))
(define (for-block-else block)                    ;; return the cdr (else) of 5th item of list 
  (cdr (split-block (cadddr block))))



;;;; For loop evaluator
(define (eval-for-block block env)
  (let ((collection-obj (py-eval (instantiate line-obj '*DUMMY-INDENT*      ;; make line-obj
					      (for-block-collection block)) ;; py-eval it 
				 env))
	(var (for-block-var block))                              ;; select variable
	(body (for-block-body block))                            ;; select body
	(else-clause (for-block-else block)))                    ;; select else-clause
    (let ((result (ask collection-obj '__iter__ var body env))   ;; iterate and get result
	  (should-eval-if else-clause))                          ;; grab else clause
      (cond ((eq? result '*BREAK)                                ;; did it break?
	     (set! should-eval-if #f)                            ;; set should-eval-if #f 
	     *NONE*)                                             ;; return *NONE* object
	    ((not (eq? should-eval-if #f))                       ;; is there an else?
	     (eval-item (make-line-obj else-clause) env))        ;; eval it!
	    (else *NONE*)))))                     ;; no else? return *NONE* object
	                                       
     
		



;; List Access
(define (get-slice line-obj env)
  ;; only handles [i], [i:j], and slices, not [:j], [i:], or [::k]
  (let ((val (py-eval line-obj env)))
    (cond ((eq? (ask line-obj 'peek) close-bracket-symbol)
	   (ask line-obj 'next) ;; get rid of ] token
	   (list val))
	  ((eq? (ask line-obj 'peek) ':)
	   (ask line-obj 'next) ;; get rid of : token
	   (cons val (get-slice line-obj env)))
	  (else (py-error "SyntaxError: Expected \"]\", encountered "
			  (ask line-obj 'next))))))

;; Unary operators
(define unary-operators '(- not))
(define (unary-op? token) (memq token unary-operators))
(define (apply-unary op val)
  (cond ((eq? op '-) (make-py-num (- (ask val 'val))))
	((eq? op 'not) (make-py-bool (not (ask val 'val)))) ;; handles "not x"
	(else (py-error "SyntaxError: Unrecognized operator: " op))))

;; Logical operators
(define (eat-tokens line-obj) ;; eats until a comma, newline or close-paren
  (define stop-tokens '(: |,| |]| |)|))
  (if (ask line-obj 'empty?)
      *NONE*
      (let ((token (ask line-obj 'peek)))
	(if (memq token stop-tokens)
	    *NONE*
	    (begin (ask line-obj 'next) (eat-tokens line-obj))))))

;; Lambda
(define (eval-lambda line-obj env)
  (define (collect-lambda-params)
    (if (ask line-obj 'empty?)
	(py-error "SyntaxError: Expected \":\", encountered newline")
	(let ((token (ask line-obj 'next)))
	  (cond ((eq? token ':) '())
		((comma? token) (collect-lambda-params))
		(else (cons token (collect-lambda-params)))))))
  (define (get-lambda-body braces)
    (define stop-tokens '(: |,| |]| |)| |}|))
    (define brace-alist '((|{| . |}|) (|[| . |]|) (|(| . |)|)))
    (define open-braces (map car brace-alist))
    (define close-braces (map cdr brace-alist))
    (define (reverse-brace token)
      (cdr (assq token brace-alist)))
    (if (ask line-obj 'empty?)
	'()
	(let ((token (ask line-obj 'next)))
	  (cond ((and (null? braces) (memq token stop-tokens))
		 (ask line-obj 'push token) ;; so the caller can see the brace
		 '())
		((memq token open-braces)
		 (cons token
		       (get-lambda-body (cons (reverse-brace token) braces))))
		((memq token close-braces)
		 (if (and (not (null? braces)) ;; null case handled above
			  (eq? token (car braces)))
		     (cons token (get-lambda-body (cdr braces)))
		     (py-error "SyntaxError: unexpected token " token)))
		(else (cons token (get-lambda-body braces)))))))
  (let ((name (string->symbol "<lambda>"))
	(params (collect-lambda-params))
	(body (list (cons '*DUMMY-INDENT*
			  (cons 'return (get-lambda-body '()))))))
    (make-py-proc name params body env)))

;; File Importation
(define (eval-import line-obj)
  (define (gather-tokens)
    (cond ((ask line-obj 'empty?) '())
      ((comma? (ask line-obj 'peek)) (ask line-obj 'next) (gather-tokens))
      (else
        (let ((n (ask line-obj 'next)))
          (cons n (gather-tokens))))))
  (let ((fnames (gather-tokens)))
    (for-each meta-load fnames))
  *NONE*)

(define (meta-load fname)
  (define (loader)
    (let ((exp (py-read)))
      (if (and (null? (cdr exp))
	       (eof-object? (peek-char)))
	  *NONE*
	  (begin (py-eval (make-line-obj exp)
			  the-global-environment)
		 (loader)))))
  (let ((file (symbol->string (word fname ".py"))))
    (set-variable-value! '__name__ (make-py-string file) the-global-environment)
    (with-input-from-file file loader)
    (set-variable-value! '__name__
			 (make-py-string "__main__")
			 the-global-environment)
    *NONE*))

;; Errors: bump to Scheme
(define (eval-raise line-obj env)
  (let ((err (py-eval line-obj env)))
    (py-error "Error: " (ask err 'val))))
(define (py-error . args)
  (for-each display args)
  (newline)
  (error "PythonError"))

;; List Comprehensions
(define (list-comp? seq) (memq 'for seq))

;; List comprehensions should work as follows:
;;   >>> myList = [1,2,3]
;;   >>> [3*x for x in myList]
;;   [3,6,9]
;;   >>> [i + j for i in "abc" for j in "def"]
;;   ["ad", "ae", "af", "bd", "be", "bf", "cd", "ce", "cf"]
;;   >>> [i*j for j in range(10) if j % 2 == 0 for i in "SICP"]
;;   ["SS", "II", "CC", "PP", "SSSS", "IIII", "CCCC", "PPPP"]
(define (eval-list-comp line-obj env)
  (py-error "ExpertError: List Comprehensions"))
