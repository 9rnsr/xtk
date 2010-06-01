module typecons.tuple_tie;

public import std.typecons : Tuple;
public import std.typecons : tuple;

import std.typetuple;
import std.traits;

import typecons.tuple_match : _;

version(unittest)
{
	import std.stdio : pp=writefln;
}


private:
/// 
struct Tie(T...)
{
private:
	template satisfy(int I, U...)
	{
		static assert(T.length == I + U.length);
		static if (U.length == 0)
		{
			enum result = true;
		}
		else
		{
			alias T[I] Lhs;
			alias U[0] Rhs;

			static if (is(Lhs == typeof(_)))		// ignore
			{
				enum result = true && satisfy!(I+1, U[1..$]).result;
			}
			else static if (is(Lhs == Rhs*))		// capture
			{
				enum result = true && satisfy!(I+1, U[1..$]).result;
			}
			else
			{
				enum result = false;
			}
		}
	}
	public template isMatchingTuple(U...)
	{
		static if (T.length == U.length)
		{
			enum isMatchingTuple = satisfy!(0, U).result;
		}
		else
		{
			enum isMatchingTuple = false;
		}
	}

	T refs;

	void assignTuple(U...)(Tuple!U rhs)
	{
		static assert(isMatchingTuple!U);

		foreach (I,t; refs)
		{
			alias T[I] Lhs;
			alias U[I] Rhs;

			static if (is(T[I] == typeof(_)))							// ignore
			{
			}
			else static if (isPointer!(T[I]) && !is(T[I] == void*))		// capture
			{
				*refs[I] = rhs.field[I];
			}
		}
	}

public:
	/// 
	void opAssign(U)(U rhs)
	{
		static if (is(U X == Tuple!(W), W...))	// matching
		{
			assignTuple(rhs);
		}
		else static if (is(U == Tie))			// copy fields
		{
			this.tupleof = rhs.tupleof;
		}
		else									// signature mismatch
		{
			static assert(0);
		}
	}

}

template MakeTieSig(T...)
{
	static if (T.length == 0)
	{
		alias TypeTuple!() MakeTieSig;
	}
	else static if (!is(typeof(T[0]) == typeof(_)) && __traits(isRef, T[0]))
	{
		alias TypeTuple!(typeof(T[0])*, MakeTieSig!(T[1..$])) MakeTieSig;
	}
	else
	{
		alias TypeTuple!(typeof(T[0]), MakeTieSig!(T[1..$])) MakeTieSig;
	}
}


public:

/// 
auto tie(T...)(auto ref T tup)
{
//	pragma(msg, MakeTieSig!tup);

	Tie!(MakeTieSig!tup) ret;
	foreach (i,t; tup)
	{
		static if (is(typeof(t) == typeof(_)))			// ignore
		{
		}
		else static if (__traits(isRef, tup[i]))		// capture
		{
			ret.refs[i] = &tup[i];
		}
		else
		{
			static assert(0);
		}
	}
	return ret;
}

unittest
{
	pp("unittest: tuple_tie");

	// capture test
	{	int n = 10;
		double d = 3.14;
		tie(n, d) = tuple(20, 1.4142);
		assert(n == 20);
		assert(d == 1.4142);
	}

	// ignore test
	{	int n = 10;
		tie(n, _) = tuple(20, 1.4142);
		assert(n == 20);
	}
	{	double d = 3.14;
		tie(_, d) = tuple(20, 1.4142);
		assert(d == 1.4142);
	}

/+
	// nested tie
	{	int n = 10;
		double d = 3.14;
		string s;
		if (tie(n, tie(d, s)) = tuple(20, tuple(1.4142, "str")))
		{
			assert(n == 20);
			assert(d == 1.4142);
			assert(s == "str");
		}
		else
		{
			assert(0);
		}
	}
	{	double d = 3.14;
		if (tie(20, tie(d, "str")) = tuple(20, tuple(1.4142, "str")))
		{
			assert(d == 1.4142);
		}
		else
		{
			assert(0);
		}
	}
+/

	// defect signature mismatch
	{	int n;
		double d;
		static assert(!__traits(compiles, tie(n, d) = 10));
	}
	{	int n;
		double d;
		static assert(!__traits(compiles, tie(n, d) = tuple(20, tuple(1.4142, "str"))));
	}
	{	int n;
		static assert(!__traits(compiles, tie(n, 1.4142) = tuple(20, 1.4142)));
	}
}
