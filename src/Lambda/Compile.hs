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

newtype CodeGen a = CodeGen { runCodeGen :: ReaderT [(Var, Int)] (State [GRIN.Var]) a }
  deriving (Functor, Applicative, Monad)

knownFunctions :: CodeGen [(Var, Int)]
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

mkPartialFunTag :: Var -> Int -> GRIN.Tag
mkPartialFunTag f leftover = coerce ("P" <> coerce f <> "_" <> show leftover)

mkConTag :: Con -> GRIN.Tag
mkConTag = coerce . ("C" <>) . coerce

withAtomAsSimpleVal :: Atom -> (GRIN.SimpleVal -> CodeGen GRIN.Exp) -> CodeGen GRIN.Exp
withAtomAsSimpleVal (AtomVar x) mk = do
  fs <- knownFunctions
  case lookup x fs of
    Nothing -> mk (GRIN.SimpleVar (coerce x))
    Just{}  -> do
      v <- freshVar
      let vpat = GRIN.LPat (GRIN.SimpleVal (GRIN.SimpleVar v))
      e1 <- compileExpNonStrict (App x [])
      e2 <- mk (GRIN.SimpleVar v)
      return $ mkGRINSequencing e1 vpat e2
withAtomAsSimpleVal (AtomLiteral l) mk = mk (GRIN.SimpleLiteral (compileLiteral l))

withAtomsAsSimpleVals :: [Atom] -> ([GRIN.SimpleVal] -> CodeGen GRIN.Exp) -> CodeGen GRIN.Exp
withAtomsAsSimpleVals atoms mk = go [] atoms
  where
    go vals [] = mk vals
    go vals (a:as) =
      case a of
        AtomVar x -> do
          fs <- knownFunctions
          case lookup x fs of
            Nothing -> go (vals ++ [atomToSimpleVal a]) as
            Just{}  -> do
              v <- freshVar
              let vpat = GRIN.LPat (GRIN.SimpleVal (GRIN.SimpleVar v))
              e1 <- compileExpNonStrict (App x [])
              e2 <- go (vals ++ [GRIN.SimpleVar v]) as
              return $ mkGRINSequencing e1 vpat e2
        AtomLiteral{} -> go (vals ++ [atomToSimpleVal a]) as

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
  e@(Atom (AtomVar x)) -> do
    fs <- knownFunctions
    case lookup x fs of
      Nothing -> compileReturn e
      Just _  -> compileExpNonStrict (App x [])
  App f args -> do
    fs <- knownFunctions
    case lookup f fs of
      Nothing -> do
        v <- freshVar
        let vpat = GRIN.LPat (GRIN.SimpleVal (GRIN.SimpleVar v))
        withAtomsAsSimpleVals args $ \args' -> return $
          mkGRINSequencing (GRIN.App (coerce "eval") [atomToSimpleVal (AtomVar f)]) vpat $
            GRIN.App (coerce ("apply_" <> show (length args))) (GRIN.SimpleVar v : args')
      Just n
        | n == length args -> withAtomsAsSimpleVals args $ \args' -> return $
            GRIN.Store (GRIN.ConstantTag (mkFunTag f) args')
        | otherwise -> withAtomsAsSimpleVals args $ \args' -> return $
            GRIN.Store (GRIN.ConstantTag (mkPartialFunTag f (n - length args)) args')
  e -> compileReturn e

compileReturn :: Exp -> CodeGen GRIN.Exp
compileReturn = \case
  Let x e1 e2 -> do -- FIXME: do not ignore x
    e1' <- compileExpNonStrict e1
    e2' <- compileReturn e2
    return (mkGRINSequencing e1' (varToLPat x) e2')

  LetS x e1 e2 -> do
    e1' <- compileExpStrict e1
    e2' <- compileReturn e2
    return (mkGRINSequencing e1' (varToLPat x) e2')

  Constructor con [] -> return $
    GRIN.Unit (GRIN.SingleTag (mkConTag con))
  Constructor con args -> withAtomsAsSimpleVals args $ \args' -> return $
    GRIN.Unit (GRIN.ConstantTag (mkConTag con) args')

  Case e cases -> do
    e' <- compileExpStrict e
    v <- freshVar
    let vpat = GRIN.LPat (GRIN.SimpleVal (GRIN.SimpleVar v))
    cases' <- mapM compileCaseExp cases
    return $
      mkGRINSequencing e' vpat $
        GRIN.Case (GRIN.SimpleVal (GRIN.SimpleVar v)) cases'

  e@App{} -> compileExpStrict e

  Atom a -> withAtomAsSimpleVal a $ \a' -> return $
    GRIN.Unit (GRIN.SimpleVal a')

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
  Atom a@(AtomVar x) -> do
    fs <- knownFunctions
    case lookup x fs of
      Nothing -> return $ GRIN.App (coerce "eval") [atomToSimpleVal a]
      Just _  -> compileExpStrict (App x [])
  App f args -> do
    fs <- knownFunctions
    case lookup f fs of
      Nothing -> do
        v <- freshVar
        let vpat = GRIN.LPat (GRIN.SimpleVal (GRIN.SimpleVar v))
        return $ mkGRINSequencing (GRIN.App (coerce "eval") [atomToSimpleVal (AtomVar f)]) vpat $
          GRIN.App (coerce ("apply_" <> show (length args))) (GRIN.SimpleVar v : map atomToSimpleVal args)
      Just n
        | n == length args -> withAtomsAsSimpleVals args $ \args' -> return $
            GRIN.App (coerce f) args'
        | otherwise -> withAtomsAsSimpleVals args $ \args' -> return $
            GRIN.Unit (GRIN.ConstantTag (mkPartialFunTag f (n - length args)) args')

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
    topLevelVars = map (\(Binding f args _body) -> (f, length args)) bindings
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
