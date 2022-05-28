module GRIN.Pretty where

import           Data.Char         (isSpace)
import           Syntax.GRIN.Abs
import qualified Syntax.GRIN.Print as GRIN

ppGRIN :: Program -> String
ppGRIN = clean . GRIN.printTree
  where
    clean
      = squashNewlines
      . map (\c -> if c == '$' then ';' else c)
      . filter (`notElem` "{};")

squashNewlines :: String -> String
squashNewlines = unlines . squash . lines
  where
    squash [] = []
    squash (l:ls)
      | isSpaces l =
          case dropWhile isSpaces ls of
            []       -> []
            (l':ls') -> "" : l' : squash ls'
      | otherwise = l : squash ls

    isSpaces = all isSpace
