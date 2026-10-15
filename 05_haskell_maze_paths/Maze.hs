-- Рекурсивный поиск количества путей в лабиринте.
-- Путь — последовательность соседних (вверх/вниз/влево/вправо) свободных клеток
-- от S до E, в которой ни одна клетка не повторяется (простой путь).

import qualified Data.Set as Set
import Data.Array
import Data.List (minimumBy, maximumBy)
import Data.Ord (comparing)
import System.Environment (getArgs)
import System.IO

type Pos  = (Int, Int)
type Grid = Array Pos Char

parseMaze :: String -> Grid
parseMaze txt = listArray ((0, 0), (h - 1, w - 1)) (concatMap padRow ls)
  where
    ls = filter (not . null) (lines txt)
    h = length ls
    w = maximum (map length ls)
    padRow r = take w (r ++ repeat '#')

findCell :: Char -> Grid -> Pos
findCell ch g = case [p | (p, c) <- assocs g, c == ch] of
  (p : _) -> p
  []      -> error ("В лабиринте нет клетки " ++ [ch])

neighbours :: Grid -> Pos -> [Pos]
neighbours g (r, c) =
  [ p | p <- [(r - 1, c), (r + 1, c), (r, c - 1), (r, c + 1)]
      , inRange (bounds g) p
      , g ! p /= '#' ]

-- Число путей: из клетки p до цели = сумма путей из каждого непосещённого соседа.
countPaths :: Grid -> Pos -> Set.Set Pos -> Pos -> Integer
countPaths g goal visited p
  | p == goal = 1
  | otherwise = sum [ countPaths g goal (Set.insert n visited) n
                    | n <- neighbours g p, not (Set.member n visited) ]

-- Сами пути (ленивый список) — нужен, чтобы показать кратчайший и самый длинный.
allPaths :: Grid -> Pos -> Set.Set Pos -> Pos -> [[Pos]]
allPaths g goal visited p
  | p == goal = [[p]]
  | otherwise = [ p : rest
                | n <- neighbours g p, not (Set.member n visited)
                , rest <- allPaths g goal (Set.insert n visited) n ]

render :: Grid -> [Pos] -> String
render g path = unlines [ [ mark (r, c) | c <- [c0 .. c1] ] | r <- [r0 .. r1] ]
  where
    ((r0, c0), (r1, c1)) = bounds g
    onPath = Set.fromList path
    mark p
      | g ! p `elem` "SE"      = g ! p
      | p `Set.member` onPath  = '*'
      | otherwise              = g ! p

main :: IO ()
main = do
  hSetEncoding stdout utf8
  args <- getArgs
  let file = case args of
        (f : _) -> f
        []      -> "maze.txt"
  txt <- readFile file
  let g     = parseMaze txt
      start = findCell 'S' g
      goal  = findCell 'E' g
      n     = countPaths g goal (Set.singleton start) start
  putStrLn ("Лабиринт из файла " ++ file ++ ":")
  putStr (render g [])
  putStrLn ("\nКоличество различных путей от S до E: " ++ show n)
  if n == 0
    then putStrLn "Выхода нет."
    else do
      let ps       = allPaths g goal (Set.singleton start) start
          shortest = minimumBy (comparing length) ps
          longest  = maximumBy (comparing length) ps
      putStrLn ("\nКратчайший путь (" ++ show (length shortest - 1) ++ " шагов):")
      putStr (render g shortest)
      putStrLn ("\nСамый длинный путь (" ++ show (length longest - 1) ++ " шагов):")
      putStr (render g longest)
