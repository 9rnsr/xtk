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


template Seq(T...)
{
	alias T Seq;
}


struct Pack(T...)
{
	alias T field;
//	alias Identity!(T.length) length;
	enum size_t length = field.length;
	
	struct Tag;
}

template isPack(T...)
{
	static if (is(T[0] _ == Pack!V, V...))
		enum isPack = true;
	else
		enum isPack = false;
}
version(unittest)
{
	static assert( isPack!(Pack!(1,2, int)));
	static assert(!isPack!(1,2, int));
	static assert(!isPack!(1));
	static assert(!isPack!(int));
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

template staticMap(alias F, T...)
{
    static if (T.length == 0)
    {
        alias Seq!() staticMap;
    }
    else static if (T.length == 1)
    {
        alias Seq!(F!(T[0])) staticMap;
    }
    else
    {
        alias Seq!(
        	staticMap!(F, T[0   .. $/2]),
            staticMap!(F, T[$/2 .. $  ])) staticMap;
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
			alias Seq!() staticIota;
		else
			alias Seq!(+beg) staticIota;
	}
	else
	{
		alias Seq!(
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
		alias Seq!() staticZip;
	else
		alias Seq!(
				Pack!(P.field[0], Q.field[0]),
				staticZip!(Pack!(P.field[1..$]), Pack!(Q.field[1..$]))
			  ) staticZip;
}
template staticZip(alias P, alias Q, alias R)
{
	static assert(P.length == Q.length && Q.length == R.length);
	static if (P.length == 0)
		alias Seq!() staticZip;
	else
		alias Seq!(
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
version(unittest)
{
	static assert(staticReduce!(q{A==""?B:A~", "~B}, "", Seq!("AAA", "BBB", "CCC")) == "AAA, BBB, CCC");
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


template Typeof(alias A)
{
	alias typeof(A) Typeof;
}

template isType(T...) if (T.length == 1)
{
	enum isType = is(T[0]);
}

template isStruct(T...) if (T.length == 1)
{
	enum isStruct = is(T[0] == struct);
}

template RemoveIf(alias F, T...)
{
	static if (T.length == 0)
	{
		alias Seq!() RemoveIf;
	}
	else static if (T.length == 1)
	{
		static if (F!(T[0]))
			alias Seq!() RemoveIf;
		else
			alias Seq!(T[0]) RemoveIf;
	}
	else
	{
		alias Seq!(
				RemoveIf!(F, T[0 .. $/2]),
				RemoveIf!(F, T[$/2 .. $])) RemoveIf;
	}
}

template Filter(alias F, T...)
{
	static if (T.length == 0)
	{
		alias Seq!() Filter;
	}
	else static if (T.length == 1)
	{
		static if (F!(T[0]))
			alias Seq!(T[0]) Filter;
		else
			alias Seq!() Filter;
	}
	else
	{
		alias Seq!(
				Filter!(F, T[0 .. $/2]),
				Filter!(F, T[$/2 .. $])) Filter;
	}
}

/+template allTypes(T)
{
	Filter!(isType, __traits(allMembers, T)
}
+/

template Equal(A, B)
{
	enum Equal = is(A == B);
}
template Equal(A, alias B)
{
	enum Equal = false;
}
template Equal(alias A, B)
{
	enum Equal = false;
}
template Equal(alias A, alias B)
{
	enum Equal = is(Pack!A.Tag == Pack!B.Tag);
}

template Equal(A)
{
	alias Equal_!(A) Equal;
}
template Equal(alias A)
{
	alias Equal_!(A).Equal Equal;
}

template Equal_(A)
{
	template Equal(B)      { enum Equal = .Equal!(A, B); }
	template Equal(alias B){ enum Equal = .Equal!(A, B); }
}
template Equal_(alias A)
{
	template Equal(B)      { enum Equal = .Equal!(A, B); }
	template Equal(alias B){ enum Equal = .Equal!(A, B); }
}


/+
template Test(T...)
{
}
static assert(isTemplate!Test);

static if (is(Test _ == T!U, alias T, U...))
{
	static assert(0);
}
+/

template Not(alias F)// if (isTemplate!F)
{
	template Not(A...)
	{
		enum Not = !(F!A);
	}
}
version(unittest)
{
	alias Seq!(1,2,3) a;
	alias Filter!(Not!(Equal!(1)), Seq!(1,2,3)) b;
	
	static assert(Equal!(Pack!b, Pack!(2,3)));
}
