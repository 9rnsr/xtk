module meta;

public import std.typetuple;
public import std.traits;



import my_demangle : Demangle;//std.demangle;
template ToLongString(T)
{
//	pragma(msg, T.stringof);
	static if( Demangle!T.length >= 6 && Demangle!T[0..6] == "class " ){
		enum ToLongString = Demangle!T[6..$];
	}else{
		enum ToLongString = Demangle!T;
	}
}
static assert(ToLongString!int == "int");


/+
template ToString(T){
	enum ToString = T.stringof;
}

template isType(A)		{ enum isType = true;  }
template isType(alias A){ enum isType = false; }
template ToString(T)
{
	enum ToString = FullName!T;//T.stringof;
}
template ToString(alias T)
{
	enum ToString = T.stringof;
}
template TupleToString(T...)
{
	static if( T.length == 0 ){
		enum TupleToString = "";
	}else{
		static if( is(typeof(T[0])) ){
			enum TupleToString = ToString!(T[0]) ~ (T.length>1?", ":"") ~ TupleToString!(T[1..$]);
		}else{
			enum TupleToString = ToString!(T[0]) ~ (T.length>1?", ":"") ~ TupleToString!(T[1..$]);
		}
	}
}
static assert(TupleToString!(int) == "int");
static assert(TupleToString!("STR") == `"STR"`);
static assert(TupleToString!(int, "STR") == `int, "STR"`);
static assert(TupleToString!(int, float) == "int, float");
static assert(TupleToString!(2, 3) == "2, 3");
static assert(TupleToString!("STR", "VAL") == `"STR", "VAL"`);
+/


template LeastUnsignedType(size_t N)
{
	     static if( N <= ubyte .max ) alias ubyte	LeastUnsignedType;
	else static if( N <= ushort.max ) alias ushort	LeastUnsignedType;
	else static if( N <= uint  .max ) alias uint	LeastUnsignedType;
	else static if( N <= ulong .max ) alias ulong	LeastUnsignedType;
	else static assert(0, "tag-size is too big");
	
}



template staticCat(V...)
{
	static if( V.length == 0 ){
		enum staticCat = "";
	}else static if( isSomeString!(typeof(V[0])) ){
		enum staticCat = V[0] ~ staticCat!(V[1..$]);
	}else{
		static assert(0);
	}
}
static assert(staticCat!("A", "B", "C") == "ABC");



// 整数範囲を指定し、テンプレート関数からタプルを生成する
template generateTuple(int Begin, int End, alias F) if( Begin <= End )
{
	static if( Begin == End ){
		alias TypeTuple!() generateTuple;
	}else{
		alias TypeTuple!(F!(Begin), generateTuple!(Begin+1, End, F)) generateTuple;
	}
}

template BinaryFun(string Code){
	template BinaryFun(alias A, alias B){
		enum BinaryFun = mixin(Code);
	}
}

// reduce
private template staticReduceEnv(alias Init, alias F, T...)
{
	template Temp(alias T){
		alias T Res;
	}
	template Engine(alias Tmp, T...){
		//pragma(msg, "Engine: (", Tmp.Res, "), ", T);
		static if( T.length == 0 ){
			alias Tmp.Res Engine;
		}else{
			alias Engine!(Temp!(F!(Tmp.Res, T[0])), T[1..$]) Engine;
		}
	}
	alias Engine!(Temp!(Init), T) Res;
}
template staticReduce(alias F, alias Init, T...)
{
	static if( isSomeString!(typeof(F)) ){
		alias staticReduceEnv!(Init, BinaryFun!F, T).Res staticReduce;
	}else{
		alias staticReduceEnv!(Init, F, T).Res staticReduce;
	}
}


unittest{
	static assert(staticReduce!(q{A==""?B:A~", "~B}, "", TypeTuple!("AAA", "BBB", "CCC")) == "AAA, BBB, CCC");
}
