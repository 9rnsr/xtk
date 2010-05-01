module tuple_tie;

public import std.typecons : Tuple;
public import std.typecons : tuple;

import std.typetuple;
import std.traits;

version(unittest)
{
	import std.stdio : pp=writefln;
}


private:
	struct Placeholder{}
	static Placeholder wildcard;
	/// 
	alias wildcard _;

	// check partial specialization of templates
	template isTie(U)
	{
		enum isTie = __traits(compiles, {void f(X...)(Tie!X x){}; f(U.init);});
	}
	template isTuple(U)
	{
		enum isTuple = __traits(compiles, {void f(X...)(Tuple!X x){}; f(U.init);});
	}

public:
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

			static if (is(Lhs == typeof(wildcard)))
			{
				// wildcard
				enum result = true && satisfy!(I+1, U[1..$]).result;
			}
			else static if (is(Rhs : Lhs) || (is(Lhs==void*) && is(Rhs == class)))
			{
				// value
				enum result = true && satisfy!(I+1, U[1..$]).result;
			}
			else static if (is(Lhs == Rhs*))
			{
				// capture
				enum result = true && satisfy!(I+1, U[1..$]).result;
			}
		//	else static if (is(Lhs V : Tie!W, W...) && is(Rhs X : Tuple!Y, Y...))		// BUG
			else static if (isTie!Lhs && isTuple!Rhs)
			{
				// pattern
		//		enum result = Lhs.isMatchingTuple!W && satisfy!(I+1, U[1..$]).result;	// BUG
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

	bool assignTuple(U...)(Tuple!U rhs)
	{
		static if (isMatchingTuple!U)
		{
			auto result = true;
			foreach( int I,t; refs ){
				alias T[I] Lhs;
				alias U[I] Rhs;

				static if (is(T[I] == typeof(wildcard)))					// wildcard
				{
					result = result && true;
				}
				else static if (isPointer!(T[I]) && !is(T[I] == void*))		// capture
				{
					*refs[I] = rhs.field[I];
					result = result && true;
				}
				else static if (is(T[I] V == Tie!W, W...))					// pattern
				{
					result = result && t.opAssign(rhs.field[I]);
				}
				else														// value
				{
					static if (is(T[I] == void*))	// null and class|pointer
					{
						static assert(is(Rhs == class) || isPointer!(Rhs));
						result = result && (cast(Rhs)refs[I] is rhs.field[I]);
					}
					else
					{
						static if (is(Lhs == class) && is(Rhs == class))
						{
							result = result && object.opEquals(refs[I], rhs.field[I]);
						}
						else
						{
							static assert(!is(Lhs == class) && !is(Rhs == class));
							result = result && (refs[I] == rhs.field[I]);
						}
					}
				}
			}
			return result;
		}
		else
		{
			static assert(0);
		}
	}

public:
	/// 
	auto opAssign(U)(U rhs)
	{
		static if (is(U X == Tuple!(W), W...))	// matching
		{
			return assignTuple(rhs);
		}
		else static if (__traits(compiles, rhs.opTieMatch))	// user-type
		{
			// if signatures mismatch, member function template instantiation should fail.
			return rhs.opTieMatch(this);
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

/// 
Tie!T tie(T...)(T tup)
{
	Tie!T ret;
	foreach( i,t; tup )
	{
		static if (is(typeof(t) == typeof(wildcard)))	// wildcard
		{
		}
		else static if (isPointer!(T[i]))				// capture
		{
			ret.refs[i] = tup[i];
		}
		else											// pattern
		{
			ret.refs[i] = tup[i];
		}
	}
	return ret;
}

unittest
{
	pp("tuple_tie.unittest");
	// capture test
	{	int n = 10;
		double d = 3.14;
		if (tie(&n, &d) = tuple(20, 1.4142))
		{
			assert(n == 20);
			assert(d == 1.4142);
		}
		else
		{
			assert(0);
		}
	}

	// wildcard test
	{	int n = 10;
		double d = 3.14;
		if (tie(&n, _) = tuple(20, 1.4142))
		{
			assert(n == 20);
			assert(d == 3.14);
		}
		else
		{
			assert(0);
		}
	}
	{	int n = 10;
		double d = 3.14;
		if (tie(_, &d) = tuple(20, 1.4142))
		{
			assert(n == 10);
			assert(d == 1.4142);
		}
		else
		{
			assert(0);
		}
	}

	// value-matching test(basic type, tuple)
	{	int n = 10;
		if (tie(&n, 1.4142) = tuple(20, 1.4142))
		{
			assert(n == 20);
		}
		else
		{
			assert(0);
		}
	}
	{	int n = 10;
		double d = 1.4142;
		if (tie(&n, tuple(d, "str")) = tuple(20, tuple(1.4142, "str")))
		{
			assert(n == 20);
		}
		else
		{
			assert(0);
		}
	}
	// value-matching test(null)
	{	int n = 10;
		int* p = null;
		if ( tie(&n, null) = tuple(10, p)){
		}
		else
		{
			assert(0);
		}

		p = &n;
		if (tie(&n, null) = tuple(10, p)){
			assert(0);
		}
	}
	{	int n = 10;
		static class A{}
		A a;
		if (tie(&n, null) = tuple(10, a))
		{
			assert(n == 10);
		}
		else
		{
			assert(0);
		}
		a = new A();
		if (tie(&n, null) = tuple(10, a))
		{
			assert(0);
		}
	}

	// nested tie
	{	int n = 10;
		double d = 3.14;
		string s;
		if (tie(&n, tie(&d, &s)) = tuple(20, tuple(1.4142, "str")))
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
		if (tie(20, tie(&d, "str")) = tuple(20, tuple(1.4142, "str")))
		{
			assert(d == 1.4142);
		}
		else
		{
			assert(0);
		}
	}

	// user-defined type
	{	static class C
		{
			int m_n; double m_d;
			this(int n, double d){ m_n=n, m_d=d; }
			bool opTieMatch(U...)(ref Tie!U tie){
				return tie = tuple(m_n, m_d);
			}
		}
		auto c = new C(10, 3.14);
		int n;
		double d = 3.14;
		if (tie(&n, d) = c){
			assert(n == 10);
		}
		else
		{
			assert(0);
		}
	}

	// defect signature mismatch
	{	int n = 10;
		double d = 3.14;
		static assert(!__traits(compiles, tie(&n, d) = 10));
	}
	{	int n = 10;
		double d = 3.14;
		static assert(!__traits(compiles, tie(&n, d) = tuple(20, tuple(1.4142, "str"))));
	}
	{	int n = 10;
		double d = 3.14;
		static assert(!__traits(compiles, tie(&n, null) = tuple(20, 1.4142)));
	}
	{	static class N
		{
			int m_n; double m_d;
			this(int n, double d){ m_n=n, m_d=d; }
		}
		auto c = new N(10, 3.14);
		int n;
		double d = 3.14;
		static assert(!__traits(compiles, tie(&n, d) = c));
	}
	pp("-> test ok");
}
