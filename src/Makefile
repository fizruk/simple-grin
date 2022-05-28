all: Syntax/Fun/Test Syntax/Lambda/Test Syntax/GRIN/Test

clean:
	make --makefile=Syntax/Fun/MakefileFun clean
	make --makefile=Syntax/Lambda/MakefileLambda clean
	make --makefile=Syntax/GRIN/MakefileGRIN clean

Syntax/Fun/Test: Syntax/Fun.cf
	bnfc -d Syntax/Fun.cf -p Syntax --makefile=Syntax/MakefileFun
	make --makefile=Syntax/MakefileFun

Syntax/Lambda/Test: Syntax/Lambda.cf
	bnfc -d Syntax/Lambda.cf -p Syntax --makefile=Syntax/MakefileLambda
	make --makefile=Syntax/MakefileLambda

Syntax/GRIN/Test: Syntax/GRIN.cf
	bnfc -d Syntax/GRIN.cf -p Syntax --makefile=Syntax/MakefileGRIN
	make --makefile=Syntax/MakefileGRIN

.PHONY: all clean
