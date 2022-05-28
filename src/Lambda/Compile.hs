{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE LambdaCase                 #-}
module Lambda.Compile where

import           Control.Monad.Reader
import           Control.Monad.State
import           Data.Coerce          (coerce)
import           Data.Function        ((&))
import qualified Syntax.GRIN.Abs      as GRIN
import           Syntax.Lambda.Abs

import qualified Syntax.GRIN.Print    as GRIN
import qualified Syntax.Lambda.Par    as Lambda

newtype CodeGen a = CodeGen { runCodeGen :: ReaderT [Var] (State [GRIN.Var]) a }
  deriving (Functor, Applicative, Monad)

knownFunctions :: CodeGen [Var]
knownFunctions = CodeGen ask

freshVar :: CodeGen GRIN.Var
freshVar = CodeGen $ do
  vars <- get
  case vars of
    x:xs -> do
      put xs
      return x
    [] -> error "not enough fresh variables"

freshLPat :: CodeGen GRIN.LPat
freshLPat = GRIN.LPat . GRIN.SimpleVal . GRIN.SimpleVar <$> freshVar

varToLPat :: Var -> GRIN.LPat
varToLPat = GRIN.LPat . GRIN.SimpleVal . GRIN.SimpleVar . coerce

mkFunTag :: Var -> GRIN.Tag
mkFunTag = coerce . ("F" <>) . coerce

mkConTag :: Con -> GRIN.Tag
mkConTag = coerce . ("C" <>) . coerce

atomToSimpleVal :: Atom -> GRIN.SimpleVal
atomToSimpleVal (AtomVar x)     = GRIN.SimpleVar (coerce x)
atomToSimpleVal (AtomLiteral l) = GRIN.SimpleLiteral (compileLiteral l)

compileLiteral :: Literal -> GRIN.Literal
compileLiteral (LitInteger n) = GRIN.LitInteger n

mkGRINSequencing :: GRIN.Exp -> GRIN.LPat -> GRIN.Exp -> GRIN.Exp
mkGRINSequencing e1 x e2 =
  case e1 of
    GRIN.Sequencing e3 y e4 -> mkGRINSequencing e3 y (mkGRINSequencing e4 x e2)
    _                       -> GRIN.Sequencing e1 x e2

compileExpNonStrict :: Exp -> CodeGen GRIN.Exp
compileExpNonStrict = \case
  App f args -> do
    fs <- knownFunctions
    if f `elem` fs
       then return $ GRIN.Store (GRIN.ConstantTag (mkFunTag f) (atomToSimpleVal <$> args))
       else error ("unknown function: " <> show f) -- need to apply HOF techniques
  e -> compileReturn e

compileReturn :: Exp -> CodeGen GRIN.Exp
compileReturn = \case
  Let _x e1 e2 -> do -- FIXME: do not ignore x
    e1' <- compileExpNonStrict e1
    e2' <- compileReturn e2
    p <- freshLPat
    return (mkGRINSequencing e1' p e2')

  LetS x e1 e2 -> do
    e1' <- compileExpStrict e1
    e2' <- compileReturn e2
    return (mkGRINSequencing e1' (varToLPat x) e2')

  Constructor con [] -> return $
    GRIN.Unit (GRIN.SingleTag (mkConTag con))
  Constructor con args -> return $
    GRIN.Unit (GRIN.ConstantTag (mkConTag con) (atomToSimpleVal <$> args))

  Case e cases -> do
    e' <- compileExpStrict e
    v <- freshVar
    let vpat = GRIN.LPat (GRIN.SimpleVal (GRIN.SimpleVar v))
    cases' <- mapM compileCaseExp cases
    return $
      mkGRINSequencing e' vpat $
        GRIN.Case (GRIN.SimpleVal (GRIN.SimpleVar v)) cases'

  e@App{} -> compileExpNonStrict e
  Atom a -> return $ GRIN.Unit (GRIN.SimpleVal (atomToSimpleVal a))

compileCaseExp :: CaseExp -> CodeGen GRIN.CaseExp
compileCaseExp (CaseExp pat e) = do
  pat' <- compilePattern pat
  e' <- compileReturn e
  return $ GRIN.CaseExp pat' e'

compilePattern :: Pat -> CodeGen GRIN.CPat
compilePattern (ConPat con []) = return $ GRIN.ConstTagPattern (mkConTag con)
compilePattern (ConPat con args) = return $ GRIN.ConstNodePattern (mkConTag con) (coerce args)
compilePattern (LitPat lit) = return $ GRIN.ConstLiteral (compileLiteral lit)

compileExpStrict :: Exp -> CodeGen GRIN.Exp
compileExpStrict = \case
  Atom x@AtomVar{} -> return $
    GRIN.App (coerce "eval") [atomToSimpleVal x]
  App f args -> do
    fs <- knownFunctions
    if f `elem` fs
       then return $ GRIN.App (coerce f) (atomToSimpleVal <$> args)
       else error ("unknown function: " <> show f) -- need to apply HOF techniques
  e@Case{} -> compileReturn e
  e@Let{} -> compileReturn e
  e@LetS{} -> compileReturn e
  e@Constructor{} -> compileReturn e
  e@Atom{} -> compileReturn e

compileBinding :: Binding -> CodeGen GRIN.Binding
compileBinding (Binding f args body) =
  GRIN.Binding (coerce f) (coerce <$> args) <$>
    compileReturn body

compileProgram :: Program -> GRIN.Program
compileProgram (Program bindings) = GRIN.Program bindings'
  where
    bindings' = mapM compileBinding bindings
      & runCodeGen
      & flip runReaderT topLevelVars
      & flip evalState defaultFreshVars
    topLevelVars = map (\(Binding f _args _body) -> f) bindings
    defaultFreshVars = coerce [ "t" <> show n | n <- [1..] ]

-- compileProgram :: Program -> GRIN.Program
-- compileProgram (Program bindings) =
--   runCodeGen

example :: Either String Program
example = Lambda.pProgram . Lambda.myLexer . unlines $
  [ "main = let x = upto (S Z) (S (S (S Z))) in sum x ;"
  , ""
  , "upto n m = case (less m n) of { True -> Nil ; False -> Cons m (upto (S m) n) } ;"
  , ""
  , "sum lst = case lst of { Nil -> Z ; Cons x xs -> add x (sum xs) }"
  , ""
  , "add n m = case n of { Z -> m; S z -> S (add z m) }"
  ]

compileExample :: IO ()
compileExample = print $ GRIN.printTree . compileProgram <$> example

compileTest :: String -> IO ()
compileTest input = do
  let tokens = Lambda.myLexer input
  case Lambda.pExp tokens of
    Left err -> print err
    Right e ->
      putStrLn $ filter importantChar $ GRIN.printTree (compileProgram (Program [Binding (coerce "main") [] e]))
  where
    importantChar = (`notElem` ['}', '{', ';'])
