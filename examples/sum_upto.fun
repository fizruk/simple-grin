main = sum (upto (S (Z)) (S (S (S (Z))))) ;

upto n m = case (less m n) of { True -> Nil ; False -> Cons m (upto (S m) n) } ;

sum lst = case lst of { Nil -> Z ; Cons x xs -> add x (sum xs) } ;

add n m = case n of { Z -> m; S z -> S (add z m) } ;

less x y = True
