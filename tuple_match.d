module typecons.tuple_match;

public import std.typecons : Tuple;
public import std.typecons : tuple;

import std.typetuple;
import std.traits;
import typecons.meta;

version(unittest)
{
	import std.stdio : pp=writefln;
}


private:
	struct Placeholder{}
	static Placeholder ignore;
	/// 
	alias ignore _;

	// check partial specialization of templates
	template isMatch(U)
	{
		enum isMatch = __traits(compiles, {void f(X...)(Match!X x){}; f(U.init);});
	}
	template isTuple(U)
	{
		enum isTuple = __traits(compiles, {void f(X...)(Tuple!X x){}; f(U.init);});
	}

	template Through(alias V){ enum Through = V; }

	template canMatch(Ptn, Val)
	{
		static if (is(Ptn == typeof(ignore)))
		{
			// ignore
			enum canMatch = true;
		}
		else static if (is(Val : Ptn) || (is(Ptn==void*) && is(Val==class)))
		{
			// value
			enum canMatch = true;
		}
		else static if (is(Ptn == Val*))
		{
			// capture
			enum canMatch = true;
		}
		else static if (isMatch!Ptn && isTuple!Val && (Ptn.field.length==Val.field.length))
		{
			// pattern & tuple
			enum canMatch = allSatisfy!(Through,
				staticZip!(.canMatch, Seq!(Ptn.field), Seq!(typeof(Val.field)))
			);
		}
		else static if (isMatch!Ptn && __traits(compiles, Val.opMatch))
		{
			// pattern & user-type
		  version(none){	// too eager that check signatures?
			enum canMatch = __traits(compiles, typeof((Ptn m){
				if( Val.opMatch(m) ){}
			}));
		  }else{
			enum canMatch = true;
		  }
		}
		else
		{
			enum canMatch = false;
		}
	}

public:
/// 
struct Match(T...)
{
private:
	alias T field;
	
	T refs;

	bool assignTuple(U...)(Tuple!U rhs)
	{
		static if (canMatch!(typeof(this), Tuple!U))
		{
			auto result = true;
			foreach (I,t; refs)
			{
				alias T[I] Lhs;
				alias U[I] Rhs;

				static if (is(T[I] == typeof(ignore)))						// ignore
				{
					result = result && true;
				}
				else static if (isPointer!(T[I]) && !is(T[I] == void*))		// capture
				{
					*refs[I] = rhs.field[I];
					result = result && true;
				}
				else static if (is(T[I] V == Match!W, W...))				// pattern
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
		else static if (__traits(compiles, rhs.opMatch))	// user-type
		{
			// if signatures mismatch, member function template instantiation should fail.
			return rhs.opMatch(this);
		}
		else static if (is(U == Match))			// copy fields
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
Match!T pattern(T...)(T tup)
{
	Match!T ret;
	foreach (i,t; tup)
	{
		static if (is(typeof(t) == typeof(ignore)))		// ignore
		{
			//do nothing
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
	pp("unittest: tuple_match");
	
	// capture test
	{	int n = 10;
		double d = 3.14;
		if (pattern(&n, &d) = tuple(20, 1.4142))
		{
			assert(n == 20);
			assert(d == 1.4142);
		}
		else
		{
			assert(0);
		}
	}

	// ignore test
	{	int n = 10;
		double d = 3.14;
		if (pattern(&n, _) = tuple(20, 1.4142))
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
		if (pattern(_, &d) = tuple(20, 1.4142))
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
		if (pattern(&n, 1.4142) = tuple(20, 1.4142))
		{
			assert(n == 20);
		}
		else
		{
			assert(0);
		}
	}
	{	int n = 10;
		if (pattern(&n, tuple(1.4142, "str")) = tuple(20, tuple(1.4142, "str")))
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
		if ( pattern(&n, null) = tuple(10, p))
		{
		}
		else
		{
			assert(0);
		}

		p = &n;
		if (pattern(&n, null) = tuple(10, p))
		{
			assert(0);
		}
	}
	{	int n = 10;
		static class A{}
		A a;
		if (pattern(&n, null) = tuple(10, a))
		{
			assert(n == 10);
		}
		else
		{
			assert(0);
		}
		a = new A();
		if (pattern(&n, null) = tuple(10, a))
		{
			assert(0);
		}
	}

	// nested pattern
	{	int n = 10;
		double d = 3.14;
		string s;
		if (pattern(&n, pattern(&d, &s)) = tuple(20, tuple(1.4142, "str")))
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
		if (pattern(20, pattern(&d, "str")) = tuple(20, tuple(1.4142, "str")))
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
			bool opMatch(U...)(ref Match!U m)
			{
				return m = tuple(m_n, m_d);
			}
		}
		auto c = new C(10, 3.14);
		int n;
		if (pattern(&n, 3.14) = c)
		{
			assert(n == 10);
		}
		else
		{
			assert(0);
		}
	}

	// defect signature mismatch
	{	int n = 10;
		static assert(!__traits(compiles, pattern(&n, 3.14) = 10));
	}
	{	int n = 10;
		static assert(!__traits(compiles, pattern(&n, 3.14) = tuple(20, tuple(1.4142, "str"))));
	}
	{	int n = 10;
		double d = 3.14;
		static assert(!__traits(compiles, pattern(&n, null) = tuple(20, 1.4142)));
	}
	{	static class N
		{
			int m_n; double m_d;
			this(int n, double d){ m_n=n, m_d=d; }
		}
		auto c = new N(10, 3.14);
		int n;
		static assert(!__traits(compiles, pattern(&n, 3.14) = c));
	}
	
/+	// match-object cannot copy
	static assert(!__traits(compiles, delegate()
	{
		int n;
		auto m = pattern(&n, _);
		m = tuple(10, 3.14);
	}));+/
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
				if (matches[I] = x)
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
unittest
{
	pp("unittest: tuple_match ->match");

	// statement version
	int d;
	match(tuple(1, 3.14),
		pattern(&d, 3.14),		{ assert(d == 1); },
		_,						{ assert(0); }
	);
	match(tuple(1, "hello"),
		pattern(&d, "bad"),		{ assert(0); },
		_,						{ /*otherwise*/; }
	);
	static assert(!__traits(compiles, ()
	{
		match(tuple(1, "hello"),
			pattern(&d, 3.14),	{ },
			_,					{ }
		);
	}));

	// expression version
	assert(
		match(tuple(1, "hello"),
			pattern(&d, "hello"),	{ return 1; },
			pattern(&d, "bad"),		{ return 2; }
		)
		== 1);
	assert(
		match(tuple(1, "hello"),
			pattern(&d, "bad1"),	{ return 1; },
			pattern(&d, "bad2"),	{ return 2; },
			_,						{ return 3; }
		)
		== 3);
	assert(
		match(tuple(1, "hello"),
			pattern(&d, "bad1"),	{ return 1; },
			pattern(&d, "bad2"),	{ return 2; }
		)
		== int.init);
}
