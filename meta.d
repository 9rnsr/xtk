module meta;

public import std.typetuple;
public import std.traits;

import my_demangle : Demangle;


template ToLongString(T)
{
	static if (Demangle!T.length >= 6 && Demangle!T[0..6] == "class ")
	{
		enum ToLongString = Demangle!T[6..$];
	}
	else static if (Demangle!T.length >= 7 && Demangle!T[0..7] == "struct ")
	{
		enum ToLongString = Demangle!T[7..$];
	}
	else static if (Demangle!T.length >= 5 && Demangle!T[0..5] == "enum ")
	{
		enum ToLongString = Demangle!T[5..$];
	}
	else static if (Demangle!T.length >= 8 && Demangle!T[0..8] == "typedef ")
	{
		enum ToLongString = Demangle!T[8..$];
	}
	else
	{
		enum ToLongString = Demangle!T;
	}
}
unittest
{
	static assert(ToLongString!int == "int");
}


template LeastUnsignedType(size_t N)
{
	     static if (N <= ubyte .max) alias ubyte	LeastUnsignedType;
	else static if (N <= ushort.max) alias ushort	LeastUnsignedType;
	else static if (N <= uint  .max) alias uint		LeastUnsignedType;
	else static if (N <= ulong .max) alias ulong	LeastUnsignedType;
	else static assert(0, "tag-size is too big");
	
}



template staticCat(V...)
{
	static if (V.length == 0)
	{
		enum staticCat = "";
	}
	else static if (isSomeString!(typeof(V[0])))
	{
		enum staticCat = V[0] ~ staticCat!(V[1..$]);
	}
	else
	{
		static assert(0);
	}
}
static assert(staticCat!("A", "B", "C") == "ABC");



// 整数範囲を指定し、テンプレート関数からタプルを生成する
template generateTuple(int Begin, int End, alias F) if (Begin <= End)
{
	static if (Begin == End)
	{
		alias TypeTuple!() generateTuple;
	}
	else
	{
		alias TypeTuple!(F!(Begin), generateTuple!(Begin+1, End, F)) generateTuple;
	}
}

template BinaryFun(string Code)
{
	template BinaryFun(alias A, alias B)
	{
		enum BinaryFun = mixin(Code);
	}
}

private template staticReduceEnv(alias Init, alias F, T...)
{
	template Temp(alias T)
	{
		alias T Res;
	}
	template Engine(alias Tmp, T...)
	{
		//pragma(msg, "Engine: (", Tmp.Res, "), ", T);
		static if (T.length == 0)
		{
			alias Tmp.Res Engine;
		}
		else
		{
			alias Engine!(Temp!(F!(Tmp.Res, T[0])), T[1..$]) Engine;
		}
	}
	alias Engine!(Temp!(Init), T) Res;
}
/// reduce
template staticReduce(alias F, alias Init, T...)
{
	static if (isSomeString!(typeof(F)))
	{
		alias staticReduceEnv!(Init, BinaryFun!F, T).Res staticReduce;
	}
	else
	{
		alias staticReduceEnv!(Init, F, T).Res staticReduce;
	}
}


unittest
{
	static assert(staticReduce!(q{A==""?B:A~", "~B}, "", TypeTuple!("AAA", "BBB", "CCC")) == "AAA, BBB, CCC");
}
