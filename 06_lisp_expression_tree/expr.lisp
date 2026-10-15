;;; Рекурсивное вычисление арифметического выражения, заданного деревом.
;;; Узел дерева: число (лист), имя переменной (лист) или список (операция аргумент...).
;;; Вычисление делает собственная функция TREE-EVAL, встроенный EVAL не используется.

(defparameter *operations*
  `((+    . ,(lambda (&rest xs) (apply #'+ xs)))
    (-    . ,(lambda (x &rest xs) (if xs (apply #'- x xs) (- x))))
    (*    . ,(lambda (&rest xs) (apply #'* xs)))
    (/    . ,(lambda (x &rest xs)
               (when (some #'zerop xs) (error "деление на ноль"))
               (apply #'/ x xs)))
    (^    . ,(lambda (x y) (expt x y)))
    (sqrt . ,(lambda (x) (sqrt x)))
    (max  . ,(lambda (&rest xs) (apply #'max xs)))
    (min  . ,(lambda (&rest xs) (apply #'min xs)))))

(defvar *variables* (make-hash-table))

(defun tree-eval (node)
  (cond
    ((numberp node) node)
    ((symbolp node)
     (multiple-value-bind (v found) (gethash node *variables*)
       (if found v (error "неизвестная переменная ~a" node))))
    ((consp node)
     (let ((op (assoc (first node) *operations*)))
       (unless op (error "неизвестная операция ~a" (first node)))
       ;; сначала рекурсивно вычисляем поддеревья, потом применяем операцию
       (apply (cdr op) (mapcar #'tree-eval (rest node)))))
    (t (error "некорректный узел ~a" node))))

;; Инфиксная запись для наглядности: (+ 1 (* 2 x)) -> (1 + (2 * X))
(defun to-infix (node)
  (cond
    ((atom node) (format nil "~a" node))
    ((and (eq (first node) '-) (= (length node) 2))
     (format nil "-~a" (to-infix (second node))))
    ((member (first node) '(sqrt max min))
     (format nil "~(~a~)(~{~a~^, ~})" (first node) (mapcar #'to-infix (rest node))))
    (t (format nil "(~{~a~^ ~})"
               (rest (mapcan (lambda (arg) (list (first node) (to-infix arg)))
                             (rest node)))))))

;; Печать дерева с отступами и значением каждого поддерева.
(defun print-tree (node &optional (depth 0))
  (let ((pad (make-string (* 2 depth) :initial-element #\Space))
        (val (handler-case (format nil "~a" (tree-eval node))
               (error () "ошибка"))))
    (if (consp node)
        (progn
          (format t "~a~a  = ~a~%" pad (first node) val)
          (dolist (child (rest node)) (print-tree child (1+ depth))))
        (format t "~a~a~:[  = ~a~;~]~%" pad node (numberp node) val))))

(defun pretty-number (x)
  (if (and (rationalp x) (not (integerp x)))
      (format nil "~a (≈ ~,4f)" x (float x))
      (format nil "~a" x)))

(defun process-form (form)
  (if (and (consp form) (eq (first form) 'set))
      (let ((value (tree-eval (third form))))
        (setf (gethash (second form) *variables*) value)
        (format t "Переменная ~a = ~a~%~%" (second form) (pretty-number value)))
      (handler-case
          (progn
            (format t "Выражение: ~s~%Инфиксно:  ~a~%Дерево:~%" form (to-infix form))
            (print-tree form 1)
            (format t "Результат: ~a~%~%" (pretty-number (tree-eval form))))
        (error (e) (format t "Ошибка вычисления: ~a~%~%" e)))))

(defun main ()
  (let ((file (or (second sb-ext:*posix-argv*) "expressions.txt"))
        (*read-eval* nil))
    (with-open-file (in file :external-format :utf-8)
      (loop for form = (read in nil :eof)
            until (eq form :eof)
            do (process-form form)))))

(main)
