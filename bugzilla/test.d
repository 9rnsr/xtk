import std.stdio;

// workaround to avoid contant folding
size_t len(T)(T arr){ return arr.length; }

void shorten(ref const(char)[] s)
{
	s = s[0 .. $-1];
}

void main()
{

	covariant_array_test();
	test_ref_arr_null();

	char[]				mame = "mame_s".dup;
	const(char)[]		mace = "mace_s";
	const(char[])		cace = "cace_s";
	immutable(char)[]	maie = "maie_s";
	immutable(char[])	iaie = "iaie_s";
	
	void print()
	{
		writef("%s\t", mame);
		writef("%s\t", mace);
		writef("%s\t", cace);
		writef("%s\t", maie);
		writef("%s\t", iaie);
		writef("\t");
		writef("%s ", len(mame));
		writef("%s ", len(mace));
		writef("%s ", len(cace));
		writef("%s ", len(maie));
		writef("%s ", len(iaie));
		writefln("");
	}
	
	print();
	
	mame = mame[0 .. $-1];
	mace = mace[0 .. $-1];
//	cace = cace[0 .. $-1];	// ok
	maie = maie[0 .. $-1];
//	iaie = iaie[0 .. $-1];	// ok
	
	print();
	
	assert(len(mame) == 6-1, "fail 1-1");
	assert(len(mace) == 6-1, "fail 1-2");
	assert(len(cace) == 6-0, "fail 1-3");
	assert(len(maie) == 6-1, "fail 1-4");
	assert(len(iaie) == 6-0, "fail 1-5");
	
	shorten(mame);
	shorten(mace);
	shorten(cace);		// bad, shouldn't convert const(T[])     to ref const(T)[]
//	shorten(maie);		// bad, should    convert immutable(T)[] to ref const(T)[]
	shorten(iaie);		// bad, shouldn't convert immutable(T[]) to ref const(T)[]
	
	print();
	
	assert(len(mame) == 6-2, "fail 2-1");
	assert(len(mace) == 6-2, "fail 2-2");
	assert(len(cace) == 6-0, "fail 2-3");	// fail
	assert(len(maie) == 6-2, "fail 2-4");	// fail
	assert(len(iaie) == 6-0, "fail 2-5");	// fail
}



class X{}
class Y:X{ void hello(){} }
class Z:X{}

void covariant_array_test()
{
	Y[] ya = [new Y()];

  version(none)
  {
	X[] xa = ya[];
  }
  else
  {
	// covariant slicing should not share memory
	X[] xa;
	xa.length = ya.length;
	foreach (i, ref x; xa) x = ya[i];	// copy elements
  }
	xa[0] = new Z();
	ya[0].hello();
}



void test_ref_arr_null()
{
	void f(ref int[] arr)
	{
		if (arr) assert(0);
	}
	
	int[] arr = null;
	f(arr);
//	f(cast(int[])null);	// null isn't an lvalue

	void g(ref int[] arr=null)
	{
		if (arr) assert(0);
	}
	g();
	g(arr);
}
