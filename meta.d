module xtk.meta;

public import std.traits, std.typecons, std.typetuple;

template Identity(alias A)
{
	alias A Identity;
}
template Identity(T)
{
	alias T Identity;
}

struct Pack(T...)
{
	alias T field;
//	alias Identity!(T.length) length;
	enum size_t length = field.length;
}

// workaround @@@BUG4333@@@
template staticLength(tuple...)
{
	enum size_t staticLength = tuple.length;
}

template Join(string sep, Args...)
{
	enum Join = staticReduce!("A==\"\" ? B : A~`"~sep~"`~B", "", Args);
}

template mixinAll(mixins...)
{
	static if (mixins.length == 1)
	{
		static if (is(typeof(mixins[0]) == string))
		{
			mixin(mixins[0]);
		}
		else
		{
			alias mixins[0] it;
			mixin it;
		}
	}
	else static if (mixins.length >= 2)
	{
		mixin mixinAll!(mixins[ 0 .. $/2]);
		mixin mixinAll!(mixins[$/2 .. $ ]);
	}
}

/**
 */
template staticIota(int beg, int end, int step = 1)
	if (step != 0)
{
	static if (beg + 1 >= end)
	{
		static if (beg >= end)
			alias TypeTuple!() staticIota;
		else
			alias TypeTuple!(+beg) staticIota;
	}
	else
	{
		alias TypeTuple!(
			staticIota!(beg, beg+(end-beg)/2),
		    staticIota!(     beg+(end-beg)/2, end))
			staticIota;
	}
}
/// ditto
template staticIota(int end)
{
	alias staticIota!(0, end) staticIota;
}


template staticZip(alias P, alias Q)
{
	static assert(P.length == Q.length);
	static if (P.length == 0)
		alias TypeTuple!() staticZip;
	else
		alias TypeTuple!(
				Pack!(P.field[0], Q.field[0]),
				staticZip!(Pack!(P.field[1..$]), Pack!(Q.field[1..$]))
			  ) staticZip;
}
template staticZip(alias P, alias Q, alias R)
{
	static assert(P.length == Q.length && Q.length == R.length);
	static if (P.length == 0)
		alias TypeTuple!() staticZip;
	else
		alias TypeTuple!(
				Pack!(P.field[0], Q.field[0], R.field[0]),
				staticZip!(Pack!(P.field[1..$]), Pack!(Q.field[1..$]), Pack!(R.field[1..$]))
			  ) staticZip;
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
	scope(failure) std.stdio.writefln("unittest@%s:%s failed", __FILE__, __LINE__);
	
	static assert(staticReduce!(q{A==""?B:A~", "~B}, "", TypeTuple!("AAA", "BBB", "CCC")) == "AAA, BBB, CCC");
}

template allSatisfy(alias F, T...)
{
    static if (T.length == 0)
    {
        enum bool allSatisfy = true;
    }
    else static if (T.length == 1)
    {
		static if (is(T[0] U == Pack!V, V...))
			alias F!(T[0].field) allSatisfy;
		else
        	alias F!(T[0]) allSatisfy;
    }
    else
    {
		static if (is(T[0] U == Pack!V, V...))
        	enum bool allSatisfy = F!(T[0].field) && allSatisfy!(F, T[1 .. $]);
        else
        	enum bool allSatisfy = F!(T[0]) && allSatisfy!(F, T[1 .. $]);
    }
}

template isCovariantParameterWith(alias F, alias G)
{
	enum isCovariantParameterWith = 
		allSatisfy!(isImplicitlyConvertible, staticZip!(F, G));
}

template isImplicitlyConvertible(From, To)
{
	enum bool isImplicitlyConvertible =
		std.traits.isImplicitlyConvertible!(From, To);
}
template isImplicitlyConvertible(alias P) if (is(P Q == Pack!(T), T...))
{
	enum bool isImplicitlyConvertible = 
		isImplicitlyConvertible!(P.field);
}


/**
Return $(D true) if $(D_PARAM T) is template.
*/
template isTemplate(alias T)
{
	enum isTemplate = is(typeof(T)) && !__traits(compiles, { auto v = T; });
}


