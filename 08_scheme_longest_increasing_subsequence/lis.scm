;;; Поиск наибольшей (строго) возрастающей подпоследовательности (LIS).
;;; Динамическое программирование:
;;;   len[i]  — длина самой длинной возрастающей подпоследовательности, оканчивающейся на a[i];
;;;   len[i]  = 1 + max(len[j]) по всем j < i, где a[j] < a[i];
;;;   prev[i] — индекс j, на котором достигнут максимум (чтобы восстановить ответ);
;;;   cnt[i]  — сколько различных LIS длины len[i] оканчивается на a[i].

(use-modules (ice-9 rdelim))

(define (read-numbers-from-file path)
  (call-with-input-file path
    (lambda (port)
      (let loop ((acc '()))
        (let ((x (read port)))
          (cond ((eof-object? x) (reverse acc))
                ((number? x) (loop (cons x acc)))
                (else (loop acc))))))))

(define (lis lst)
  (let* ((a (list->vector lst))
         (n (vector-length a))
         (len  (make-vector n 1))
         (prev (make-vector n -1))
         (cnt  (make-vector n 1)))
    ;; заполнение таблиц
    (do ((i 1 (+ i 1))) ((>= i n))
      (do ((j 0 (+ j 1))) ((>= j i))
        (when (< (vector-ref a j) (vector-ref a i))
          (let ((cand (+ 1 (vector-ref len j))))
            (cond ((> cand (vector-ref len i))
                   (vector-set! len i cand)
                   (vector-set! prev i j)
                   (vector-set! cnt i (vector-ref cnt j)))
                  ((= cand (vector-ref len i))
                   (vector-set! cnt i (+ (vector-ref cnt i) (vector-ref cnt j)))))))))
    ;; индекс конца самой длинной подпоследовательности
    (let* ((best (let loop ((i 1) (best 0))
                   (cond ((>= i n) best)
                         ((> (vector-ref len i) (vector-ref len best)) (loop (+ i 1) i))
                         (else (loop (+ i 1) best)))))
           (best-len (vector-ref len best))
           (total (let loop ((i 0) (s 0))
                    (cond ((>= i n) s)
                          ((= (vector-ref len i) best-len) (loop (+ i 1) (+ s (vector-ref cnt i))))
                          (else (loop (+ i 1) s)))))
           ;; восстановление: идём по prev от конца к началу
           (indices (let loop ((i best) (acc '()))
                      (if (= i -1) acc (loop (vector-ref prev i) (cons i acc))))))
      (values (map (lambda (i) (vector-ref a i)) indices) indices total len))))

(define (show-row title vec-or-list)
  (display title)
  (for-each (lambda (x) (display (string-pad (number->string x) 5)))
            (if (vector? vec-or-list) (vector->list vec-or-list) vec-or-list))
  (newline))

(define (main args)
  (let ((nums (cond ((null? args) '(10 9 2 5 3 7 101 18 4 8 6 12))
                    ((and (= (length args) 1) (file-exists? (car args)))
                     (read-numbers-from-file (car args)))
                    (else (map string->number args)))))
    (cond
      ((null? nums) (display "Последовательность пуста\n"))
      ((memv #f nums) (display "Ошибка: все аргументы должны быть числами\n"))
      (else
       (call-with-values (lambda () (lis nums))
         (lambda (seq indices total len)
           (show-row "Индекс:      " (iota (length nums)))
           (show-row "Значение:    " nums)
           (show-row "len[i]:      " len)
           (newline)
           (display "Длина наибольшей возрастающей подпоследовательности: ")
           (display (length seq)) (newline)
           (display "Одна из них: ") (display seq) (newline)
           (display "Позиции в исходной последовательности: ") (display indices) (newline)
           (display "Всего различных подпоследовательностей такой длины: ")
           (display total) (newline)))))))

(main (cdr (command-line)))
