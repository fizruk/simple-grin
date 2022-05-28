{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE LambdaCase                 #-}
{-# LANGUAGE RecordWildCards            #-}
module Lambda.Compile where

import           Control.Monad.RWS
import           Data.Coerce       (coerce)
import           Data.Function     ((&))
import           Data.List         (union)
import qualified Syntax.GRIN.Abs   as GRIN
import           Syntax.Lambda.Abs

import qualified Syntax.GRIN.Print as GRIN
import qualified Syntax.Lambda.Par as Lambda

newtype TopLevelSymbols = TopLevelSymbols
  { getTopLevelSymbols :: [(Var, Int)] }
  deriving (Show)

data FunctionSymbols = FunctionSymbols
  { usedFunctionTags :: [(GRIN.Tag, GRIN.Var, Int)]
  , usedPartialTags  :: [(GRIN.Tag, GRIN.Var, Int, Int)]
  , usedConTags      :: [(GRIN.Tag, Int)]
  , usedMaxApply     :: Int
  } deriving (Show)

instance Semigroup FunctionSymbols where
  FunctionSymbols fs1 ps1 cs1 m1 <> FunctionSymbols fs2 ps2 cs2 m2
    = FunctionSymbols (fs1 `union` fs2) (ps1 `union` ps2) (cs1 `union` cs2) (max m1 m2)

instance Monoid FunctionSymbols where
  mempty = FunctionSymbols mempty mempty mempty 0

newtype CodeGen a = CodeGen
  { runCodeGen :: RWS TopLevelSymbols FunctionSymbols [GRIN.Var] a }
  deriving (Functor, Applicative, Monad)

knownFunctions :: CodeGen [(Var, Int)]
knownFunctions = CodeGen (asks getTopLevelSymbols)

registerApplyFunctionTag :: (GRIN.Tag, GRIN.Var, Int) -> CodeGen ()
registerApplyFunctionTag t@(_, _, n) = CodeGen (tell (FunctionSymbols [t] [] [] n))

registerFunctionTag :: (GRIN.Tag, GRIN.Var, Int) -> CodeGen ()
registerFunctionTag f = CodeGen (tell (FunctionSymbols [f] [] [] 0))

registerPartialTag :: (GRIN.Tag, GRIN.Var, Int, Int) -> CodeGen ()
registerPartialTag f = CodeGen (tell (FunctionSymbols [] [f] [] 0))

registerConTag :: (GRIN.Tag, Int) -> CodeGen ()
registerConTag f = CodeGen (tell (FunctionSymbols [] [] [f] 0))

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

applyVar :: Int -> GRIN.Var
applyVar n = coerce ("apply_" <> show n)

compileApplyFunTag :: Int -> CodeGen GRIN.Tag
compileApplyFunTag n = do
  let f = coerce ("apply_" <> show n)
      tag = mkFunTag f
  registerApplyFunctionTag (tag, coerce f, n)
  forM_ [1..n-1] $ \k -> do
    let g = coerce ("apply_" <> show k)
        tag' = mkFunTag g
    registerApplyFunctionTag (tag', coerce g, k)
  return tag

compileFunTag :: Var -> CodeGen GRIN.Tag
compileFunTag f = do
  let tag = mkFunTag f
  fs <- knownFunctions
  case lookup f fs of
    Just n -> do
      registerFunctionTag (tag, coerce f, n)
      return tag
    Nothing -> return tag

compilePartialTag :: Var -> Int -> Int -> CodeGen GRIN.Tag
compilePartialTag f argsNum leftover = do
  let tag = mkPartialFunTag f leftover
  registerPartialTag (tag, coerce f, argsNum, leftover)
  forM_ [1..leftover - 1] $ \i -> do
    let tag' = mkPartialFunTag f i
    registerPartialTag (tag', coerce f, argsNum + leftover - i, i)
  return tag

compileConTag :: Con -> Int -> CodeGen GRIN.Tag
compileConTag con n = do
  let tag = mkConTag con
  registerConTag (tag, n)
  return tag

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
      Nothing -> withAtomsAsSimpleVals args $ \args' -> do
        let n = 1 + length args
        ap' <- compileApplyFunTag n
        return $ GRIN.Store (GRIN.ConstantTag ap' (GRIN.SimpleVar (coerce f) : args'))
      Just n
        | n == length args -> withAtomsAsSimpleVals args $ \args' -> do
            f' <- compileFunTag f
            return $ GRIN.Store (GRIN.ConstantTag f' args')
        | otherwise -> withAtomsAsSimpleVals args $ \args' -> do
            f' <- compilePartialTag f (length args) (n - length args)
            return $ GRIN.Store (GRIN.ConstantTag f' args')
  e -> compileReturn e

compileReturn :: Exp -> CodeGen GRIN.Exp
compileReturn = \case
  Let x e1 e2 -> do
    e1' <- compileExpNonStrict e1
    e2' <- compileReturn e2
    return (mkGRINSequencing e1' (varToLPat x) e2')

  LetS x e1 e2 -> do
    e1' <- compileExpStrict e1
    e2' <- compileReturn e2
    return (mkGRINSequencing e1' (varToLPat x) e2')

  Constructor con [] -> do
    con' <- compileConTag con 0
    return $ GRIN.Unit (GRIN.SingleTag con')
  Constructor con args -> withAtomsAsSimpleVals args $ \args' -> do
    con' <- compileConTag con (length args)
    return $ GRIN.Unit (GRIN.ConstantTag con' args')

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
compilePattern (ConPat con []) = do
  con' <- compileConTag con 0
  return $ GRIN.ConstTagPattern con'
compilePattern (ConPat con args) = do
  con' <- compileConTag con (length args)
  return $ GRIN.ConstNodePattern con' (coerce args)
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
        | otherwise -> withAtomsAsSimpleVals args $ \args' -> do
            f' <- compilePartialTag f (length args) (n - length args)
            return $ GRIN.Unit (GRIN.ConstantTag f' args')

  e@Case{} -> compileReturn e
  e@Let{} -> compileReturn e
  e@LetS{} -> compileReturn e
  e@Constructor{} -> compileReturn e
  e@Atom{} -> compileReturn e

compileBinding :: Binding -> CodeGen GRIN.Binding
compileBinding (Binding f args body) =
  GRIN.Binding (coerce f) (coerce <$> args) <$>
    compileReturn body

generateApplyN :: FunctionSymbols -> Int -> CodeGen GRIN.Binding
generateApplyN FunctionSymbols{..} n = do
  f <- GRIN.SimpleVal . GRIN.SimpleVar <$> freshVar
  xs <- replicateM n freshVar
  cases <- mapM (generateApplyNCase n xs) usedPartialTags
  return $ GRIN.Binding (applyVar n) xs $
    GRIN.Case f cases

generateApplyNCase
  :: Int
  -> [GRIN.Var]
  -> (GRIN.Tag, GRIN.Var, Int, Int)
  -> CodeGen GRIN.CaseExp
generateApplyNCase n args (tag, f, argsNum, leftover) = do
  xs <- replicateM argsNum freshVar
  v <- GRIN.SimpleVar <$> freshVar
  let vpat = GRIN.LPat (GRIN.SimpleVal v)
  let ap' = applyVar (n - leftover)
  return $ GRIN.CaseExp (GRIN.ConstNodePattern tag xs) $
    case splitAt leftover args of
      _ | n == leftover -> GRIN.App f (map GRIN.SimpleVar (xs <> args))
      _ | n < leftover -> GRIN.Unit (GRIN.ConstantTag (mkPartialFunTag (coerce f) (leftover - n)) (map GRIN.SimpleVar (xs <> args)))
      (before, after) ->
          mkGRINSequencing (GRIN.App f (GRIN.SimpleVar <$> (xs <> before))) vpat $
            GRIN.App ap' (v : map GRIN.SimpleVar after)

generateEvalConCases :: GRIN.Exp -> FunctionSymbols -> CodeGen [GRIN.CaseExp]
generateEvalConCases rhs FunctionSymbols{..}
  = mapM (generateEvalConCase rhs) usedConTags

generateEvalConCase :: GRIN.Exp -> (GRIN.Tag, Int) -> CodeGen GRIN.CaseExp
generateEvalConCase rhs (con, n) = do
  xs <- replicateM n freshVar
  return $ case xs of
    [] -> GRIN.CaseExp (GRIN.ConstTagPattern con) rhs
    _  -> GRIN.CaseExp (GRIN.ConstNodePattern con xs) rhs

generateEvalFunCases :: GRIN.Var -> FunctionSymbols -> CodeGen [GRIN.CaseExp]
generateEvalFunCases p FunctionSymbols{..}
  = mapM (generateEvalFunCase p) usedFunctionTags

generateEvalFunCase :: GRIN.Var -> (GRIN.Tag, GRIN.Var, Int) -> CodeGen GRIN.CaseExp
generateEvalFunCase p (tag, f, n) = do
  xs <- replicateM n freshVar
  w <- freshVar
  let wval = GRIN.SimpleVal (GRIN.SimpleVar w)
  let wpat = GRIN.LPat (GRIN.SimpleVal (GRIN.SimpleVar w))
  return $
    GRIN.CaseExp (GRIN.ConstNodePattern tag xs) $
      mkGRINSequencing (GRIN.App f (GRIN.SimpleVar <$> xs)) wpat $
        mkGRINSequencing (GRIN.Update p wval) (GRIN.LPat GRIN.Empty) $
          GRIN.Unit wval

generateEval :: FunctionSymbols -> CodeGen GRIN.Binding
generateEval fs = do
  p <- freshVar
  v <- GRIN.SimpleVal . GRIN.SimpleVar <$> freshVar
  let vpat = GRIN.LPat v
  conCases <- generateEvalConCases (GRIN.Unit v) fs
  funCases <- generateEvalFunCases p fs
  return $
    GRIN.Binding (coerce "eval") [p] $
      mkGRINSequencing (GRIN.Fetch p) vpat $
        GRIN.Case v (conCases <> funCases)

generateEvalAndApplyBindings :: FunctionSymbols -> CodeGen [GRIN.Binding]
generateEvalAndApplyBindings fs@FunctionSymbols{..} = do
  evalBinding <- generateEval fs
  applyBindings <- mapM (generateApplyN fs) [1..usedMaxApply]
  return (evalBinding : applyBindings)

compileProgram :: Program -> GRIN.Program
compileProgram (Program bindings)
  = GRIN.Program (bindings' ++ helperBindings)
  where
    (helperBindings, _) = generateEvalAndApplyBindings symbols
      & runCodeGen
      & \m -> evalRWS m (TopLevelSymbols topLevelVars) leftoverVars
    (bindings', leftoverVars, symbols) = mapM compileBinding bindings
      & runCodeGen
      & \m -> runRWS m (TopLevelSymbols topLevelVars) defaultFreshVars
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
