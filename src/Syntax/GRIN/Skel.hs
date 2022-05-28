-- Haskell module generated by the BNF converter

{-# OPTIONS_GHC -fno-warn-unused-matches #-}

module Syntax.GRIN.Skel where

import Prelude (($), Either(..), String, (++), Show, show)
import qualified Syntax.GRIN.Abs

type Err = Either String
type Result = Err String

failure :: Show a => a -> Result
failure x = Left $ "Undefined case: " ++ show x

transTag :: Syntax.GRIN.Abs.Tag -> Result
transTag x = case x of
  Syntax.GRIN.Abs.Tag string -> failure x

transVar :: Syntax.GRIN.Abs.Var -> Result
transVar x = case x of
  Syntax.GRIN.Abs.Var string -> failure x

transProgram :: Syntax.GRIN.Abs.Program -> Result
transProgram x = case x of
  Syntax.GRIN.Abs.Program bindings -> failure x

transBinding :: Syntax.GRIN.Abs.Binding -> Result
transBinding x = case x of
  Syntax.GRIN.Abs.Binding var vars exp -> failure x

transExp :: Syntax.GRIN.Abs.Exp -> Result
transExp x = case x of
  Syntax.GRIN.Abs.Sequencing exp1 lpat exp2 -> failure x
  Syntax.GRIN.Abs.Case val caseexps -> failure x
  Syntax.GRIN.Abs.App var simplevals -> failure x
  Syntax.GRIN.Abs.Unit val -> failure x
  Syntax.GRIN.Abs.Store val -> failure x
  Syntax.GRIN.Abs.Fetch var -> failure x
  Syntax.GRIN.Abs.Update var val -> failure x

transCaseExp :: Syntax.GRIN.Abs.CaseExp -> Result
transCaseExp x = case x of
  Syntax.GRIN.Abs.CaseExp cpat exp -> failure x

transSimpleVal :: Syntax.GRIN.Abs.SimpleVal -> Result
transSimpleVal x = case x of
  Syntax.GRIN.Abs.SimpleLiteral literal -> failure x
  Syntax.GRIN.Abs.SimpleVar var -> failure x

transVal :: Syntax.GRIN.Abs.Val -> Result
transVal x = case x of
  Syntax.GRIN.Abs.ConstantTag tag simplevals -> failure x
  Syntax.GRIN.Abs.VariableTag var simplevals -> failure x
  Syntax.GRIN.Abs.SingleTag tag -> failure x
  Syntax.GRIN.Abs.Empty -> failure x
  Syntax.GRIN.Abs.SimpleVal simpleval -> failure x

transLPat :: Syntax.GRIN.Abs.LPat -> Result
transLPat x = case x of
  Syntax.GRIN.Abs.LPat val -> failure x

transCPat :: Syntax.GRIN.Abs.CPat -> Result
transCPat x = case x of
  Syntax.GRIN.Abs.ConstNodePattern tag vars -> failure x
  Syntax.GRIN.Abs.ConstTagPattern tag -> failure x
  Syntax.GRIN.Abs.ConstLiteral literal -> failure x

transLiteral :: Syntax.GRIN.Abs.Literal -> Result
transLiteral x = case x of
  Syntax.GRIN.Abs.LitInteger integer -> failure x
  Syntax.GRIN.Abs.LitBoolFalse -> failure x
  Syntax.GRIN.Abs.LitBoolTrue -> failure x
