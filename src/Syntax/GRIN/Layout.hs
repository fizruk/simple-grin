module Syntax.GRIN.Layout where

import Prelude

import Syntax.GRIN.Lex


import Data.Maybe (isNothing, fromJust)

-- Generated by the BNF Converter

-- local parameters


topLayout :: Bool
topLayout = True

layoutWords, layoutStopWords :: [String]
layoutWords     = ["\8594","="]
layoutStopWords = []

-- layout separators


layoutOpen, layoutClose, layoutSep :: String
layoutOpen  = "{"
layoutClose = "}"
layoutSep   = ";"

-- | Replace layout syntax with explicit layout tokens.
resolveLayout :: Bool    -- ^ Whether to use top-level layout.
              -> [Token] -> [Token]
resolveLayout tp = res Nothing [if tl then Implicit 1 else Explicit]
  where
  -- Do top-level layout if the function parameter and the grammar say so.
  tl = tp && topLayout

  res :: Maybe Token -- ^ The previous token, if any.
      -> [Block] -- ^ A stack of layout blocks.
      -> [Token] -> [Token]

  -- The stack should never be empty.
  res _ [] ts = error $ "Layout error: stack empty. Tokens: " ++ show ts

  res _ st (t0:ts)
    -- We found an open brace in the input,
    -- put an explicit layout block on the stack.
    -- This is done even if there was no layout word,
    -- to keep opening and closing braces.
    | isLayoutOpen t0 = moveAlong (Explicit:st) [t0] ts

  -- We are in an implicit layout block
  res pt (Implicit n:ns) (t0:ts)

      -- End of implicit block by a layout stop word
    | isStop t0 =
           -- Exit the current block and all implicit blocks
           -- more indented than the current token
       let (ebs,ns') = span (`moreIndent` column t0) ns
           moreIndent (Implicit x) y = x > y
           moreIndent Explicit _ = False
           -- the number of blocks exited
           b = 1 + length ebs
           bs = replicate b layoutClose
           -- Insert closing braces after the previous token.
           (ts1,ts2) = splitAt (1+b) $ addTokens (afterPrev pt) bs (t0:ts)
        in moveAlong ns' ts1 ts2

    -- End of an implicit layout block
    | newLine pt t0 && column t0 < n  =
           -- Insert a closing brace after the previous token.
       let b:t0':ts' = addToken (afterPrev pt) layoutClose (t0:ts)
           -- Repeat, with the current block removed from the stack
        in moveAlong ns [b] (t0':ts')

  res pt st (t0:ts)
    -- Start a new layout block if the first token is a layout word
    | isLayout t0 =
        case ts of
            -- Explicit layout, just move on. The case above
            -- will push an explicit layout block.
            t1:_ | isLayoutOpen t1 -> moveAlong st [t0] ts
                 -- The column of the next token determines the starting column
                 -- of the implicit layout block.
                 -- However, the next block needs to be strictly more indented
                 -- than the previous block.
            _ -> let col = max (indentation st + 1) $
                       -- at end of file, the start column doesn't matter
                       if null ts then column t0 else column (head ts)
                     -- insert an open brace after the layout word
                     b:ts' = addToken (nextPos t0) layoutOpen ts
                     -- save the start column
                     st' = Implicit col:st
                 in -- Do we have to insert an extra layoutSep?
                case st of
                  Implicit n:_
                    | newLine pt t0 && column t0 == n
                      && not (isNothing pt ||
                              isTokenIn [layoutSep,layoutOpen] (fromJust pt)) ->
                     let b':t0':b'':_ =
                           addToken (afterPrev pt) layoutSep (t0:b:ts')
                     in moveAlong st' [b',t0',b''] ts'
                  _ -> moveAlong st' [t0,b] ts'

    -- If we encounter a closing brace, exit the first explicit layout block.
    | isLayoutClose t0 =
          let st' = drop 1 (dropWhile isImplicit st)
           in if null st'
                 then error $ "Layout error: Found " ++ layoutClose ++ " at ("
                              ++ show (line t0) ++ "," ++ show (column t0)
                              ++ ") without an explicit layout block."
                 else moveAlong st' [t0] ts

  -- Insert separator if necessary.
  res pt st@(Implicit n : _) (t0:ts)
    -- Encounted a new line in an implicit layout block.
    | newLine pt t0 && column t0 == n =
       -- Insert a semicolon after the previous token.
       -- unless we are the beginning of the file,
       -- or the previous token is a semicolon or open brace.
       if isNothing pt || isTokenIn [layoutSep,layoutOpen] (fromJust pt)
          then moveAlong st [t0] ts
          else let b:t0':ts' = addToken (afterPrev pt) layoutSep (t0:ts)
                in moveAlong st [b,t0'] ts'

  -- Nothing to see here, move along.
  res _ st (t:ts)  = moveAlong st [t] ts

  -- At EOF: skip explicit blocks.
  res (Just t) (Explicit:bs) [] | null bs = []
                                | otherwise = res (Just t) bs []

  -- If we are using top-level layout, insert a semicolon after
  -- the last token, if there isn't one already
  res (Just t) [Implicit _n] []
      | isTokenIn [layoutSep] t = []
      | otherwise = addToken (nextPos t) layoutSep []

  -- At EOF in an implicit, non-top-level block: close the block
  res (Just t) (Implicit _ : bs) [] =
     let c = addToken (nextPos t) layoutClose []
      in moveAlong bs c []

  -- This should only happen if the input is empty.
  res Nothing _st [] = []

  -- | Move on to the next token.
  moveAlong :: [Block] -- ^ The layout stack.
            -> [Token] -- ^ Any tokens just processed.
            -> [Token] -- ^ the rest of the tokens.
            -> [Token]
  moveAlong _  [] _  = error "Layout error: moveAlong got [] as old tokens"
  moveAlong st ot ts = ot ++ res (Just $ last ot) st ts

  newLine :: Maybe Token -> Token -> Bool
  newLine pt t0 = case pt of
    Nothing -> True
    Just t  -> line t /= line t0

data Block
   = Implicit Int -- ^ An implicit layout block with its start column.
   | Explicit
   deriving Show

-- | Get current indentation.  0 if we are in an explicit block.
indentation :: [Block] -> Int
indentation (Implicit n : _) = n
indentation _ = 0

-- | Check if s block is implicit.
isImplicit :: Block -> Bool
isImplicit (Implicit _) = True
isImplicit _ = False

type Position = Posn

-- | Insert a number of tokens at the begninning of a list of tokens.
addTokens :: Position -- ^ Position of the first new token.
          -> [String] -- ^ Token symbols.
          -> [Token]  -- ^ The rest of the tokens. These will have their
                      --   positions updated to make room for the new tokens .
          -> [Token]
addTokens p ss ts = foldr (addToken p) ts ss

-- | Insert a new symbol token at the begninning of a list of tokens.
addToken :: Position -- ^ Position of the new token.
         -> String   -- ^ Symbol in the new token.
         -> [Token]  -- ^ The rest of the tokens. These will have their
                     --   positions updated to make room for the new token.
         -> [Token]
addToken p s ts = sToken p s : map (incrGlobal p (length s)) ts

-- | Get the position immediately to the right of the given token.
--   If no token is given, gets the first position in the file.
afterPrev :: Maybe Token -> Position
afterPrev = maybe (Pn 0 1 1) nextPos

-- | Get the position immediately to the right of the given token.
nextPos :: Token -> Position
nextPos t = Pn (g + s) l (c + s + 1)
  where Pn g l c = position t
        s = tokenLength t

-- | Add to the global and column positions of a token.
--   The column position is only changed if the token is on
--   the same line as the given position.
incrGlobal :: Position -- ^ If the token is on the same line
                       --   as this position, update the column position.
           -> Int      -- ^ Number of characters to add to the position.
           -> Token -> Token
incrGlobal (Pn _ l0 _) i (PT (Pn g l c) t) =
  if l /= l0 then PT (Pn (g + i) l c) t
             else PT (Pn (g + i) l (c + i)) t
incrGlobal _ _ p = error $ "cannot add token at " ++ show p

-- | Create a symbol token.
sToken :: Position -> String -> Token
sToken p s = PT p (TS s i)
  where
    i = case s of
      "$" -> 1
      "(" -> 2
      "()" -> 3
      ")" -> 4
      ";" -> 5
      "=" -> 6
      "False" -> 7
      "True" -> 8
      "case" -> 9
      "fetch" -> 10
      "of" -> 11
      "store" -> 12
      "unit" -> 13
      "update" -> 14
      "{" -> 15
      "}" -> 16
      "\955" -> 17
      "\8594" -> 18
      _ -> error $ "not a reserved word: " ++ show s

-- | Get the position of a token.
position :: Token -> Position
position t = case t of
  PT p _ -> p
  Err p -> p

-- | Get the line number of a token.
line :: Token -> Int
line t = case position t of Pn _ l _ -> l

-- | Get the column number of a token.
column :: Token -> Int
column t = case position t of Pn _ _ c -> c

-- | Check if a token is one of the given symbols.
isTokenIn :: [String] -> Token -> Bool
isTokenIn ts t = case t of
  PT _ (TS r _) | r `elem` ts -> True
  _ -> False

-- | Check if a word is a layout start token.
isLayout :: Token -> Bool
isLayout = isTokenIn layoutWords

-- | Check if a token is a layout stop token.
isStop :: Token -> Bool
isStop = isTokenIn layoutStopWords

-- | Check if a token is the layout open token.
isLayoutOpen :: Token -> Bool
isLayoutOpen = isTokenIn [layoutOpen]

-- | Check if a token is the layout close token.
isLayoutClose :: Token -> Bool
isLayoutClose = isTokenIn [layoutClose]

-- | Get the number of characters in the token.
tokenLength :: Token -> Int
tokenLength t = length $ prToken t

