{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE LambdaCase                 #-}
module Fun.Compile where

import           Control.Monad.State
import           Data.Coerce         (coerce)
import           Data.Function       ((&))
import           Syntax.Fun.Abs
import qualified Syntax.Fun.Par      as Fun
import qualified Syntax.Lambda.Abs   as Lam

newtype Fresh var a = Fresh { runFresh :: State [var] a }
  deriving (Functor, Applicative, Monad)

type LamGen = Fresh Lam.Var

fresh :: Fresh var var
fresh = Fresh $ do
  get >>= \case
    [] -> error "not enough fresh variables"
    x:xs -> do
      put xs
      return x

compileWithArgs :: [Exp] -> ([Lam.Atom] -> Lam.Exp) -> LamGen Lam.Exp
compileWithArgs args mk = go [] args
  where
    go atoms [] = return (mk atoms)
    go atoms (x:xs) = do
      compileExp x >>= \case
        Lam.Atom a -> go (atoms ++ [a]) xs
        e -> do
          z <- fresh
          Lam.Let z e <$> go (atoms ++ [Lam.AtomVar z]) xs

-- FIXME: works under assumption that original code did not have nested let-expressions with name shadowing
simplifyLet :: Lam.Exp -> Lam.Exp
simplifyLet = \case
  Lam.Let x e1 e2 ->
    case simplifyLet e1 of
      Lam.Let y e3 e4 -> Lam.Let y e3 (simplifyLet (Lam.Let x e4 e2))
      e1'             -> Lam.Let x e1' e2
  Lam.Case e cases -> Lam.Case (simplifyLet e) (map simplifyCaseExp cases)
  Lam.LetS x e1 e2 -> Lam.LetS x (simplifyLet e1) (simplifyLet e2)
  e@Lam.Constructor{} -> e
  e@Lam.App{} -> e
  e@Lam.Atom{} -> e
  where
    simplifyCaseExp (Lam.CaseExp pat e) = Lam.CaseExp pat (simplifyLet e)

compileExp :: Exp -> LamGen Lam.Exp
compileExp = \case
  Let x e1 e2  -> fmap simplifyLet $
    Lam.Let (coerce x) <$> compileExp e1 <*> compileExp e2
  LetS x e1 e2 -> Lam.LetS (coerce x) <$> compileExp e1 <*> compileExp e2
  Case e cases -> Lam.Case <$> compileExp e <*> mapM compileCaseExp cases
  Constructor con args -> compileWithArgs args $ Lam.Constructor (coerce con)
  App f a as -> let args = a:as in
    compileExp f >>= \case
      Lam.Atom (Lam.AtomVar f')  -> compileWithArgs args $ Lam.App f'
      Lam.Atom Lam.AtomLiteral{} -> error "cannot apply literal as a function"
      Lam.Constructor{} -> error "cannot apply partially applied constructors"
      e -> do
        f' <- fresh
        Lam.Let f' e <$> compileWithArgs args (Lam.App f')
  Atom (AtomVar x) -> return $ Lam.Atom (Lam.AtomVar (coerce x))
  Atom (AtomLiteral lit) -> return $ Lam.Atom (Lam.AtomLiteral (compileLiteral lit))

compileCaseExp :: CaseExp -> LamGen Lam.CaseExp
compileCaseExp (CaseExp pat e) = Lam.CaseExp <$> compilePat pat <*> compileExp e

compilePat :: Pat -> LamGen Lam.Pat
compilePat (ConPat con args) = return $ Lam.ConPat (coerce con) (coerce args)
compilePat (LitPat lit)      = return $ Lam.LitPat (compileLiteral lit)

compileLiteral :: Literal -> Lam.Literal
compileLiteral (LitInteger n) = Lam.LitInteger n

compileBinding :: Binding -> LamGen Lam.Binding
compileBinding (Binding f args body)
  = Lam.Binding (coerce f) (coerce args) <$> compileExp body

compileProgram :: Program -> Lam.Program
compileProgram (Program bindings) = Lam.Program bindings'
  where
    bindings' = mapM compileBinding bindings
      & runFresh
      & flip evalState defaultFreshVars
    defaultFreshVars = coerce [ "v" <> show n | n <- [1..] ]

exampleFunProgram :: Program
Right exampleFunProgram = Fun.pProgram . Fun.myLexer . unlines $
  [ "main = sum (upto (S (Z)) (S (S (S (Z)))));"
  , ""
  , "upto n m = case (less m n) of { True -> Nil ; False -> Cons m (upto (S m) n) } ;"
  , ""
  , "sum lst = case lst of { Nil -> Z ; Cons x xs -> add x (sum xs) } ;"
  , ""
  , "add n m = case n of { Z -> m; S z -> S (add z m) } ;"
  , ""
  , "less x y = True"
  ]

