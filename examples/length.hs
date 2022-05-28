main = length (Cons (Z) (Cons (Z) (Nil))) ;

length lst =
  case lst of
    {
      Nil       -> Z ;
      Cons x xs -> S (length xs)
    }
