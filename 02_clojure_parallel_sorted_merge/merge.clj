;; Параллельное объединение отсортированных файлов.
;; Файлы сливаются попарно, как в турнирной сетке: на каждом раунде все пары
;; сливаются одновременно в отдельных потоках (future), пока не останется один список.

(ns merge-files
  (:require [clojure.java.io :as io]
            [clojure.string :as str]))

(defn thread-name [] (.getName (Thread/currentThread)))

(defn read-numbers [path]
  (with-open [r (io/reader path)]
    (->> (line-seq r)
         (map str/trim)
         (remove str/blank?)
         (mapv #(Long/parseLong %)))))

(defn sorted-vec? [v]
  (every? (fn [[a b]] (<= a b)) (partition 2 1 v)))

;; Классическое слияние двух отсортированных векторов за O(n + m).
(defn merge-two [a b]
  (let [na (count a) nb (count b)]
    (loop [i 0 j 0 acc (transient [])]
      (cond
        (= i na) (persistent! (reduce conj! acc (subvec b j)))
        (= j nb) (persistent! (reduce conj! acc (subvec a i)))
        (<= (a i) (b j)) (recur (inc i) j (conj! acc (a i)))
        :else (recur i (inc j) (conj! acc (b j)))))))

(defn parallel-merge [vectors]
  (loop [level vectors round 1]
    (if (<= (count level) 1)
      (or (first level) [])
      (let [pairs   (partition-all 2 level)
            futures (mapv (fn [[a b]]
                            (future
                              {:thread (thread-name)
                               :sizes  (if b [(count a) (count b)] [(count a)])
                               :data   (if b (merge-two a b) a)}))
                          pairs)
            results (mapv deref futures)]
        (println (format "Раунд %d: %d список(ов) -> %d" round (count level) (count results)))
        (doseq [{:keys [thread sizes data]} results]
          (println (format "  %-28s %s -> %d" thread (str/join " + " sizes) (count data))))
        (recur (mapv :data results) (inc round))))))

(defn generate! [k m]
  (let [rnd (java.util.Random. 2026)]
    (doseq [i (range 1 (inc k))]
      (let [path (format "data/gen_%02d.txt" i)
            nums (sort (repeatedly m #(.nextInt rnd 1000000)))]
        (io/make-parents path)
        (spit path (str (str/join "\n" nums) "\n"))
        (println "Создан" path)))))

(defn run-merge [out inputs]
  (let [t0      (System/nanoTime)
        vectors (vec (pmap read-numbers inputs))]   ; файлы читаются тоже параллельно
    (doseq [[path v] (map vector inputs vectors)]
      (println (format "%-22s %6d чисел%s" path (count v)
                       (if (sorted-vec? v) "" "  (НЕ отсортирован! будет отсортирован)"))))
    (let [vectors (mapv #(if (sorted-vec? %) % (vec (sort %))) vectors)
          result  (parallel-merge vectors)
          ms      (/ (- (System/nanoTime) t0) 1e6)]
      (spit out (str (str/join "\n" result) "\n"))
      (println (format "Итого %d чисел записано в %s за %.1f мс, отсортировано: %s"
                       (count result) out ms (sorted-vec? result))))))

(let [args *command-line-args*]
  (cond
    (= (first args) "--gen")
    (generate! (Long/parseLong (nth args 1 "8")) (Long/parseLong (nth args 2 "100000")))

    (>= (count args) 2)
    (run-merge (first args) (vec (rest args)))

    :else
    (println "Использование: merge.clj <выходной файл> <файл1> <файл2> ...\n"
             "              merge.clj --gen <кол-во файлов> <чисел в файле>"))
  (shutdown-agents))
