module typecons.meta;

public import std.typetuple;
public import std.traits;

import typecons.my_demangle : Demangle;


/// 
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


/// 
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


/// タプルをラップするための型
struct Seq(T...){ alias T field; }


private template SeqListHead(T...) if (T.length == 0)
{
	alias TypeTuple!() SeqListHead;
}
private template SeqListHead(T...) if (is(T[0] U : Seq!W, W...))
{
	static if (T[0].field.length == 0)
	{
		alias TypeTuple!() SeqListHead;
	}
	else
	{
		alias TypeTuple!(T[0].field[0], SeqListHead!(T[1..$])) SeqListHead;
	}
}
private template SeqListTail(T...) if (T.length == 0)
{
	alias TypeTuple!() SeqListTail;
}
private template SeqListTail(T...) if (is(T[0] U : Seq!W, W...))
{
	static if (T[0].field.length == 0)
	{
		alias TypeTuple!() SeqListTail;
	}
	else
	{
		alias TypeTuple!(Seq!(T[0].field[1..$]), SeqListTail!(T[1..$])) SeqListTail;
	}
}
///
/// 複数タプルをSeqでラップした上でstaticZipに渡す
template staticZip(alias F, T...)
{
	static if (SeqListHead!T.length == 0)
	{
		alias TypeTuple!() staticZip;
	}
	else
	{
		alias TypeTuple!(F!(SeqListHead!T), staticZip!(F, SeqListTail!T)) staticZip;
	}
}
version(unittest)
{
	import std.typecons : Tuple;
	template MakeTuple(T...)
	{
		alias Tuple!T MakeTuple;
	}
	static assert(is(
		staticZip!(MakeTuple, Seq!(int, double), Seq!(string, char))
			== TypeTuple!(Tuple!(int, string), Tuple!(double, char))
	));
}


/// 
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


/// 
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
