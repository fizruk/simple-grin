# simple-grin

Compiler from a simple functional language to GRIN.

The implementation is based on the thesis of [Urban Boquist, Code Optimisation Techniques for Lazy Functional Languages](https://github.com/grin-compiler/grin/blob/master/papers/boquist.pdf).

This project presents 3 languages:
1. Fun is a simple functional language (should be typed, but for now is not).
2. Lambda is a simple untyped language, similar in some sense to STG language for Haskell: it has fully saturated constructor applications, lifted functions, and atomic arguments.
3. GRIN (Graph Reduction Intermediate Notation) is a lower-level intermediate language (used in the aforementioned thesis for whole program analysis and optimizations).

In this project, we provide simple translations from Fun to Lambda, and then from Lambda to GRIN.

## Examples

See examples in [`examples/`](examples/) directory.
You can compile each example into GRIN simply by running `stack run`, for example:

```sh
stack run < examples/quad.fun
```

### Higher-order functions

Consider the following program in Fun language, making heavy use of higher-order functions.

```haskell
main = (quad quad) inc (Z) ;
quad f = twice twice f ;
twice f x = f (f x) ;
inc n = S n
```

The corresponding GRIN program looks like this:

```haskell
main =
  store (Pquad_1) ; λ t1 →
  store (Fquad t1) ; λ v1 →
  unit CZ ; λ v2 →
  eval v1 ; λ t2 →
  apply_2 t2 inc v2

quad f =
  store (Ptwice_2) ; λ t3 →
  twice t3 f

twice f x =
  store (Fapply_2 f x) ; λ v3 →
  eval f ; λ t4 →
  apply_1 t4 v3

inc n =
  unit (CS n)
```

Here, `eval`, `apply_1`, and `apply_2` functions are automatically generated.
`eval` computes delayed closures:

```haskell
eval t5 =
  fetch t5 ; λ t6 →
  case t6 of
    ...

    (CS t7) →
      unit t6

    (Fquad t8) →
      quad t8 ; λ t9 →
      update t5 t9 ; λ () →
      unit t9

    ...
```

While `apply_1` and `apply_2` work with partially applied functions:

```haskell
apply_1 t16 =
  case t15 of
    (Pquad_1) →
      quad t16

    (Ptwice_2) →
      unit (Ptwice_1 t16)

    (Ptwice_1 t19) →
      twice t19 t16
```

## How to build

This project is built using Stack and tested with GHC 9.0.2.

Parsers, abstract syntax trees, and pretty-printers for the three languages are generated using the BNF converter tool. To install BNF converter tool, follow instructions on their [official website](http://bnfc.digitalgrammars.com). For example, you can use the Stack tool:

```sh
stack install BNFC
```

To use BNF converter, you will also need to install Alex and Happy (lexer and parser generator tools for Haskell, analogous to YACC and Bison). Using Stack you can install them as follows:

```sh
stack install alex happy
```

After making changes to the Labelled BNF for any of the languages in a corresponding `src/Syntax/*.cf` file, make sure to regenerate the code by running `make`:

```sh
cd src/
make
```
