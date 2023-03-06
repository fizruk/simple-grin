main = factorial (S (S (Z))) ;

add n m = case n of { Z -> m; S z -> S (add z m) } ;

mul n m = case n of { Z -> m; S z -> add m (mul z m) } ;

fix f = f (fix f) ;

factorial = fix helper ;

helper f n = case n of { Z -> 1; S z -> mul n (f z) } ;
