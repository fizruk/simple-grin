module Main where

import qualified Fun.Compile         as Fun
import qualified GRIN.Pretty         as GRIN
import qualified Lambda.Compile      as Lam
import qualified Syntax.Fun.Par      as Fun
import qualified Syntax.Lambda.Print as Lam

main :: IO ()
main = do
  input <- getContents
  let tokens = Fun.myLexer input
  case Fun.pProgram tokens of
    Left err -> print err
    Right program -> do
      let programLam = Fun.compileProgram program
      putStrLn "==================================================="
      putStrLn (Lam.printTree programLam)
      putStrLn "==================================================="
      let programGRIN = Lam.compileProgram programLam
      putStrLn (GRIN.ppGRIN programGRIN)
      putStrLn "==================================================="
