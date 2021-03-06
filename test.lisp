
(defpackage macroexpand-dammit-test
  (:use :cl :macroexpand-dammit :fiveam))

(in-package :macroexpand-dammit-test)

(def-suite :macroexpand-dammit-test)
(in-suite :macroexpand-dammit-test)
(test nested
  "testing highly nested macrolets"
  (macrolet ((a () :b))

    (macrolet ((c (&body body &environment env)
		 (let ((expansion (macroexpand-dammit body env)))
		   (is (equalp expansion
			       '((PRINT :b) (PRINT :b))))
		   `(progn ,@expansion))))

      (macrolet ((d () `(a)))
	(c (print (d))
	   (print (d)))))))

(test nested2
  "testing highly nested macrolets 2nd. error case in 20100701"
  (macrolet ((a () :b))
    (macrolet
	((c (&body body &environment env)
	   (let ((expansion (macroexpand-dammit body env))) ; <-+
	     (is (equalp expansion			    ;   |
			 '((progn (PRINT :b) (PRINT :b))))) ;   |
	     `(progn ,@expansion))))			    ;   |
      (macrolet ((d () `(a)))	     ;			        |
	(c			     ;			        |
	 (macrolet ((e () `(a)))     ; <------------------------+
	   (print (d))		     ; the older version of macroexpand-dammit
	   (print (e))))))))	     ; stops expanding the form after this point.


;; The test results were
;;  The following check failed: (EQUALP EXPANSION '((PROGN (PRINT :B) (PRINT :B))))
;; '((PROGN (PRINT :B) (PRINT :B)))
;;  evaluated to 
;; ((PROGN (PRINT :B) (PRINT :B)))
;;  which is not 
;; EQUALP
;;  to 
;; ((PROGN (PRINT (D)) (PRINT (A))))

;; The original version of macroexpand-dammit stops expanding the form
;; 
;; (macrolet ((e () `(a)))
;;   (print (d))
;;   (print (e)))
;; 
;; mainly because it uses EVAL in order to expand macrolet forms.
;; 
;; When macroexpand-dammit finds a macrolet form it passes the form to
;; EVAL.  ANSI Common Lisp doesn't have EVAL-IN-LEXENV (which some
;; implementation has) and EVAL doesn't take &environment argument.
;; Obviously EVAL doesn't recognize the lexical environment containing
;; the macro-function of D, therefore D remains without expansion. 

;; Since the macro definition of E exists in the form
;; E is always expanded. However again, the definition of A is ignored
;; and the test fails.
;; 
;; The fixed version expands both D and E.


(test issue2
  "issue 2 -- (lambda ...) expands into (function (lambda ...)),
which was not handled collectly in my version."
  (finishes
    (macroexpand-dammit '(lambda (x) x)))
  (finishes
    (macroexpand-dammit '(sb-int:named-lambda a (x) x)))
  (finishes
    (macroexpand-dammit '(defun a (x) x))))

;; issue 1 -- let*, declaration and style warning.
;; Authors of the previous version might have noticed the same problem,
;; which can be seen in the definition of (defhandler let* ...)
;; However their solution was not
;; effective because handler-let* is actually never called with nil.
;; At least I ensured that the declaration
;; is wrapped in `locally`. However, style warnings are still signalled.
(test issue1-let*-declare
  (finishes
    (handler-bind ((style-warning
                    (lambda (c)
                      (warn "style-warning signalled"))))
      (compile nil
               `(lambda ()
                  ,(macroexpand-dammit '(let* ((a 1)
                                               (b 2))
                                         (declare (ignore a b)))))))))



(eval-when (:compile-toplevel :load-toplevel :execute)
  (setf *print-circle* t))

(test walk-tree
  "testing the helper function (circular-list compatible tree walker)"
  (let ((*print-circle* t)
        (counter 0))
    (finishes
      (macroexpand-dammit::walk-tree
       (lambda (subform cont)
         (is (< counter 10))
         (typecase subform
           (cons
            (funcall cont subform))
           (atom
            (print subform)
            (incf counter))))
       '(1 (2 3) (4 (5 6) 7 #1=(8 9 . #1#)))))
    (is (= 9 counter))))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun wrap (form)
    (let ((flagsym (gensym "FLAG")))
      (setf (symbol-value flagsym) nil)
      `(macrolet ((macro ()
                    (if (symbol-value ',flagsym)
                        (error "(macro) is expanded more than twice!")
                        (setf (symbol-value ',flagsym) t))))
         ,form))))

(test wrap
  "testing the helper function"
  (finishes
    (eval (wrap `(progn (macro) :a))))
  (signals error
    (eval (wrap `(progn #1=(macro) #1# :a))))
  (signals error
    (eval (wrap `(progn (macro) (macro) :a)))))

;; (quote (macro) (macro) (macro) ...)
(test (issue3-circular-forms-1 :depends-on (and wrap walk-tree))
  "Ensures that the expansion of circular forms does finish."
  (let ((circular (cons `(macro) nil))
        (*print-circle* t))
    (setf (cdr circular) circular)
    (dolist (head '(quote))
      (let ((form (wrap `(,head ,circular))))
        (finishes
          (pprint form)
          (macroexpand-dammit form))))))


;; (quote
;;  #2=(progn (macro) <----------+--- same cons
;;         #2=(progn (macro) <---+
;;                #2=(progn (macro) ...))))

(test (issue3-circular-forms-2 :depends-on (and wrap walk-tree))
  (let ((circular '(progn (macro)))
        (*print-circle* t))
    (setf (cddr circular) (cons circular nil))
    (dolist (head '(quote))
      (let ((form (wrap `(,head ,circular))))
        (finishes
          (pprint form)
          (macroexpand-dammit form))))))

