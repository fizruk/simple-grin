module GRIN.Pretty where

import           Syntax.GRIN.Abs
import qualified Syntax.GRIN.Print as GRIN

ppGRIN :: Program -> String
ppGRIN = clean . GRIN.printTree
  where
    clean
      = map (\c -> if c == '$' then ';' else c)
      . filter (`notElem` "{};")
