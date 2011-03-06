module xtk.match;

private import xtk.meta;

struct Ignore{};
enum _ = Ignore();

struct Ellipsis{}
enum __dollar = Ellipsis();

//	debug = Print1;	//compiletime print1
//	debug = Print2;	// compiletime print2
//	debug = Print3;	//runtime print
debug(Print3) import std.stdio;

/**
 * Save pattern matching information
 * Supports array elements and std.typecons.Tuple fields
 */
struct Match(bool ellipse, Elem...)
{
public:
	template Repeat(T, size_t n)
	{
		static if (n == 0)
			alias TypeTuple!() Repeat;
		else
			alias TypeTuple!(T, Repeat!(T, n-1)) Repeat;
	}
	template FieldTypeTupleOf(A)
	{
		static if (isArray!A)
			alias Repeat!(typeof(A.init[0]), Elem.length) FieldTypeTupleOf;
		else static if (isTuple!A)
			alias typeof(A.field) FieldTypeTupleOf;
	}

	template isMatchParameter(int i, P, Q)
	{
		static if (is(P == Ignore))
		{
			debug(Print2) pragma(msg, "[", i, "] ignore, P=", P, ", Q=", Q);
			enum isMatchParameter = true;
		}
		else static if (is(P U : U*) && is(Q : U))
		{
			debug(Print2) pragma(msg, "[", i, "] capture, P=", P, ", Q=", Q);
			enum isMatchParameter = true;	// capture
		}
		else static if (is(P V == Match!(f, W), bool f, W...))
		{
			debug(Print2) pragma(msg, "[", i, "] pattern, P=", P, ", Q=", Q);
			//enum isMatchParameter = true;	// pattern
			enum isMatchParameter = V.isMatchParameterWith!Q;	// pattern
		}
		else static if (is(P == void*) && is(Q == class))
		{
			debug(Print2) pragma(msg, "[", i, "] value(void*), P=", P, ", Q=", Q);
			enum isMatchParameter = true;	// value(void*)
		}
		else static if (is(P X) && is(Q : X))
		{
			debug(Print2) pragma(msg, "[", i, "] value, P=", P, ", Q=", Q);
			enum isMatchParameter = true;	// value
		}
		else
		{
			debug(Print2) pragma(msg, "[", i, "] failed : (", P, ", ", Q, ")");
			enum isMatchParameter = false;
		}
	}
	template isMatchParameterWith(Q...)
	{
		static if (Q.length==1 && __traits(compiles, Q[0].opMatch))
		{
			debug(Print2) pragma(msg, typeof(this), ".isMatchParameterWith : cls Q=", Q);
			enum isMatchParameterWith = true;	//todo?
		}
		else static if (Q.length==1 && isArray!(Q[0]))
		{
			debug(Print2) pragma(msg, typeof(this), ".isMatchParameterWith : arr Q=", Q);
			enum isMatchParameterWith =
				isMatchParameterWith!(FieldTypeTupleOf!(Q[0]));
		}
		else static if (Q.length==1 && isTuple!(Q[0]))
		{
			debug(Print2) pragma(msg, typeof(this), ".isMatchParameterWith : tup Q=", Q);
			enum isMatchParameterWith =
				isMatchParameterWith!(FieldTypeTupleOf!(Q[0]));
		}
		else
		{
			debug(Print2) pragma(msg, typeof(this), ".isMatchParameterWith : ... Q =", Q);
			static if (ellipse)
			{
				static if (Elem.length <= Q.length)
					enum isMatchParameterWith =
						allSatisfy!(isMatchParameter,
							staticZip!(Pack!(staticIota!(staticLength!Elem)), Pack!Elem, Pack!(Q[0 .. Elem.length])));
				else
					enum isMatchParameterWith = false;
			}
			else
			{
				static if (Elem.length == Q.length)
					enum isMatchParameterWith =
						allSatisfy!(isMatchParameter,
							staticZip!(Pack!(staticIota!(staticLength!Elem)), Pack!Elem, Pack!Q));
				else
					enum isMatchParameterWith = false;
			}
		}
	}
	
	/// match operator(like an arrow operator)
	bool opOpAssign(string op, Ag)(auto ref Ag ag) if (op=="<<")
	{
		//debug(Print3) writefln("%s <<= %s", typeid(typeof(this)), typeid(typeof(ag)));
		
		static if (__traits(compiles, ag.opMatch))
		{
			debug(Print1) pragma(msg, typeof(this), " <<= class ", Ag);
			return ag.opMatch(this);
		}
		else static if (isArray!Ag)
		{
			debug(Print1) pragma(msg, typeof(this), " <<= ", Ag, "");
			static if (ellipse)
			{
				static if(isMatchParameterWith!Ag)
				{
					return (Elem.length <= ag.length ? check(ag[0 .. Elem.length]) : false);
				}
				else
					return false;
			}
			else
			{
				static if(isMatchParameterWith!Ag)
				{
					return (Elem.length == ag.length ? check(ag) : false);
				}
				else
					return false;
			}
		}
		else static if (isTuple!Ag)
		{
			debug(Print1) pragma(msg, typeof(this), " <<= ", Ag, "");
			static if (ellipse)
			{
//				static if (Elem.length <= ag.length && 
///				           isMatchParameterWith!(typeof(ag.slice!(0, Elem.length)().field)))
//				           isMatchParameterWith!Ag)
				static if (isMatchParameterWith!Ag)
				{
					return check(ag.slice!(0, Elem.length));
				}
				else
				{
					return false;
				}
			}
			else
			{
//				static if (Elem.length == ag.length && isMatchParameterWith!Ag)
				static if (isMatchParameterWith!Ag)
				{
					return check(ag);
				}
				else
				{
					return false;
				}
			}
		}
		else
			return false;
	}

private:
	static if (Elem.length > 0)				// elem is ()
		Elem refs;

	/// 
	this(ref Elem elem)
	{
		foreach (i, e; elem)
		{
			static if (is(typeof(elem[i]) == Ignore))
				{}
			else static if (isPointer!(typeof(elem[i])))
				refs[i] = elem[i];
			else
				refs[i] = elem[i];
		}
	}

	bool check(Ag)(Ag ag)
	in{ assert(Elem.length == ag.length); }
	body{
	//	debug(Print1) pragma(msg, "Match.check : Elem = ", Elem, ", Ag = ", Ag);
	//	debug(Print3) writefln("Match.check : ag = %s", ag);
		
		static if (Elem.length > 0)
		{
			bool result = true;
			foreach (i, e; refs)
			{
				static if (is(Elem[i] == Ignore))
				{
					debug(Print3) writefln("[%s] ignore %s <<= %s:%s", i, typeof(refs[i]).stringof, ag[i], typeof(ag[i]).stringof);
				}
				else static if (is(Elem[i] U : U*) && is(typeof(ag[i]) : U))
				{
					debug(Print3) writefln("[%s] capture %s <<= %s:%s", i, typeof(refs[i]).stringof, ag[i], typeof(ag[i]).stringof);
					*refs[i] = ag[i];
				}
				else static if (is(Elem[i] V == Match!(f, W), bool f, W...))
				{
					debug(Print3) writefln("[%s] pattern %s <<= %s:%s", i, typeof(refs[i]).stringof, ag[i], typeof(ag[i]).stringof);
					result = refs[i] <<= ag[i];
				}
				else static if (is(Elem[i] == void*) && is(typeof(ag[i]) == class))
				{
					debug(Print3) writefln("[%s] value(void*) %s <<= %s", i, refs[i], ag[i]);
					if (refs[i] == null)
						result = ag[i] is null;
					else
						result = refs[i] == &ag[i];
				}
				else static if (is(Elem[i] X) && is(typeof(ag[i]) : X))
				{
					debug(Print3) writefln("[%s] value, %s:%s <<= %s:%s", i, refs[i], typeof(refs[i]).stringof, ag[i], typeof(ag[i]).stringof);
					result = (refs[i] == ag[i]);
				}
				else
				{
					static if (Elem.length == Ag.length)
						debug(Print3) writefln("[%s] fail %s <<= %s", i, typeid(Elem[i]), ag[i]);
					result = false;
				}
				if (!result) break;
			}
			debug(Print3) writefln(" check %s", result);
			return result;
		}
		else
			return true;
	}
}

// Pattern literal
struct p
{
	// array/tuple literal pattern
	static auto opSlice()
	{
		return Match!(false)();
	}
	static auto opIndex(Elem...)(Elem elem)
	{
		static if (is(Elem[$-1] == Ellipsis))
			return Match!(true, Elem[0..$-1])(elem[0..$-1]);
		else
			return Match!(false, Elem)(elem);
	}
	
/+	// tuple literal pattern
	// Sadly p(..., $) is invalid D expression, so we can't use this.
	static auto opCall(Elem...)(Elem elem)
	{
		static if (is(Elem[$-1] == Ellipsis))
			return Match!(true, Elem[0..$-1])(elem[0..$-1]);
		else
			return Match!(false, Elem)(elem);
	}+/
}
debug(match)
unittest
{
	scope(success) std.stdio.writefln("unittest succeeded @ %s:%s", __FILE__, __LINE__);
	
	int x, y;
	double a, b;
	assert(p[] <<= []);
	assert(p[_] <<= [1]);
	assert(p[1] <<= [1]);
	assert(p[1, $] <<= [1]);
	assert(p[1, 2] <<= [1, 2]);
	assert(p[&x, &y, $] <<= [1, 2, 3]);
	assert(x == 1 && y == 2);
	assert(p[_, &x, _, &y, $] <<= [1, 2, 3, 4, 5, 6]);
	assert(x == 2 && y == 4);
	assert(p[_, &a, _, &b, $] <<= [1, 2, 3, 4, 5, 6]);
	assert(a == 2.0 && b == 4.0);
	assert(p[p[1, &x], p[&y, 4]] <<= [[1,2], [3,4]]);
	assert(x == 2 && y == 3);
	

	assert(!(p[] <<= [1]));
	assert(!(p[1, $] <<= [0, 0]));
	assert(!(p[1, 2] <<= [1, 3]));
	assert(!(p[1, &x, &y] <<= [1, 2, 3, 4]));
	assert(!(p[&x, 0, &y, $] <<= [1, 2, 3]));
	assert(!(p[_, _] <<= [1]));
	assert(!(p[_, 0] <<= [1, 2]));

	assert(p[] <<= tuple());
	assert(p[_] <<= tuple(1));
	assert(p[1] <<= tuple(1));
	assert(p[1, $] <<= tuple(1));
	assert(p[1, 2] <<= tuple(1, 2));
	assert(p[&x, &y, $] <<= tuple(1, 2, 3));
	assert(x == 1 && y == 2);
	assert(p[_, &x, _, &y, $] <<= tuple(1, 2, 3, 4, 5, 6));
	assert(x == 2 && y == 4);
	assert(p[_, &a, _, &b, $] <<= tuple(1, 2, 3, 4, 5, 6));
	assert(a == 2.0 && b == 4.0);
	assert(p[p[1, &x], p[&y, 4]] <<= tuple(tuple(1,2), tuple(3,4)));
	assert(x == 2 && y == 3);

	assert(!(p[] <<= tuple(1)));
	assert(!(p[1, $] <<= tuple(0, 0)));
	assert(!(p[1, 2] <<= tuple(1, 3)));
	assert(!(p[1, &x, &y] <<= tuple(1, 2, 3, 4)));
	assert(!(p[&x, 0, &y, $] <<= tuple(1, 2, 3)));
	assert(!(p[_, _] <<= tuple(1)));
	assert(!(p[_, 0] <<= tuple(1, 2)));
	
	class Exp
	{
		int tag;
		this(int n){ tag = n; }
		bool opMatch(Match)(ref Match m)
		{
			if (tag == 1)
				return m <<= tuple(0, "");
			else
				return m <<= tuple("", 0);
		}
	}
	auto exp1 = new Exp(1);
	auto exp2 = new Exp(2);
	assert(p[0, ""] <<= exp1);
	assert(p["", 0] <<= exp2);
	
	assert(!(p[1, ""] <<= exp1));
	assert(!(p["", 1] <<= exp2));
	assert(!(p["", ""] <<= exp1));
	assert(!(p["", ""] <<= exp2));
}

/**
 *
 */
auto match(T, U...)(T x, U matches)
in
{
	static assert(U.length % 2 == 0);
}
body
{
	foreach (I,m; matches)
	{
		static if (I%2 == 0)
		{
			static if (is(typeof(matches[I]) == typeof(_)))
			{
				return matches[I+1]();
			}
			else
			{
				if (matches[I] <<= x)
				{
					return matches[I+1]();
				}
			}
		}
	}
	static if (!is(typeof(return) == void))
	{
		return typeof(return).init;
	}
}
debug(match)
unittest
{
	scope(success) std.stdio.writefln("unittest succeeded @ %s:%s", __FILE__, __LINE__);

	// statement version
	int d;
	match(tuple(1, 3.14),
		p[&d, 3.14],			{ assert(d == 1); },
		_,						{ assert(0); }
	);
	match(tuple(1, "hello"),
		p[&d, "bad"],			{ assert(0); },
		_,						{ /*otherwise*/; }
	);
//	static assert(!__traits(compiles, ()
//	{
//		match(tuple(1, "hello"),
//			p[&d, 3.14],		{ },
//			_,					{ }
//		);
//	}));

	// expression version
	assert(
		match(tuple(1, "hello"),
			p[&d, "hello"],		{ return 1; },
			p[&d, "bad"],		{ return 2; }
		)
		== 1);
	assert(
		match(tuple(1, "hello"),
			p[&d, "bad1"],		{ return 1; },
			p[&d, "bad2"],		{ return 2; },
			_,					{ return 3; }
		)
		== 3);
	assert(
		match(tuple(1, "hello"),
			p[&d, "bad1"],		{ return 1; },
			p[&d, "bad2"],		{ return 2; }
		)
		== int.init);
}


template PointerTypeOf(T)
{
	alias T* PointerTypeOf;
}

struct tie
{
	static auto opIndex(Elem...)(ref Elem captures)
	{
		staticMap!(PointerTypeOf, typeof(captures)) pointers;
		foreach (i, c; captures)
			pointers[i] = &captures[i];
		return p[pointers];
	}
}
debug(match)
unittest
{
	scope(success) std.stdio.writefln("unittest succeeded @ %s:%s", __FILE__, __LINE__);

	int x, y;
	tie[x, y] <<= [10, 20];
}
