module xtk.typecons;

import std.conv : emplace;
import std.algorithm : move, swap;
import std.traits;


private extern (C) static void _d_monitordelete(Object h, bool det);

// inner struct cannot return value optimization
private struct Scoped(T) if (is(T == class))
{
private:
	ubyte[__traits(classInstanceSize, T)] __payload;
	@property T __object(){ return cast(T)__payload.ptr; }

public:
	@disable this(this){}

	~this()
	{
		static void destroy(T)(T obj)
		{
			static if (is(typeof(obj.__dtor())))
			{
				obj.__dtor();
			}
			static if (!is(T == Object) && is(T Base == super))
			{
				Base b = obj;
				destroy(b);
			}
		}

		destroy(__object);
		if ((cast(void**)__payload.ptr)[1])	// if monitor is not null
		{
			_d_monitordelete(__object, true);
		}
	}

	//alias __object this;
	mixin ValueProxy!__object;	// blocking conversion Scoped!T to T
}

/**
*/
Scoped!T scoped(T, A...)(A args)
{
	// return value through hidden pointer. - need?
	static assert((Scoped!T).sizeof > 8, "too small object");

	//debug(0)
	//{
		ubyte* hidden;	// for assertion check
		asm{ mov hidden, EAX; }
	//}

	version(none)	// Issue 5777
	{
		auto s = Scoped!T();	// allocated on hidden[0 .. (Scoped!T).sizeof]
		assert(cast(void*)&s == cast(void*)hidden);
		emplace!T(cast(void[])s.__payload, args);
		return s;	// destructor defined object cannnot RVO through hidden pointer
	}
	else
	{
		auto s = cast(Scoped!T*)hidden;
		emplace!T(cast(void[])s.__payload, args);
		asm{
			pop EDI;
			pop ESI;
			pop EBX;
			leave;
			ret;
		}
	}
}
unittest
{
	// Issue 4500 - scoped moves class after calling the constructor
	static class A
	{
		static int cnt;

		this()		{ a = this; ++cnt; }
		this(int i)	{ a = this; ++cnt; }
		A a;
		bool check(){ return (this is a); }
		~this(){ --cnt; }
	}

	{
		auto a1 = scoped!A();
		assert(a1.check());
		assert(A.cnt == 1);

		auto a2 = scoped!A(1);
		assert(a2.check());
		assert(A.cnt == 2);
	}
	assert(A.cnt == 0);	// destructors called on scope exit
}


/**
TODO:
	const対応
	assumeUiqueによるuniqueness付加
Related:
	@mono_shoo	http://ideone.com/gH9AX
*/

//debug = Unique;

debug(Unique)	// for debug print
bool isInitialState(T)(ref T obj)
{
	static if (is(T == class) || is(T == interface) || isDynamicArray!T || isPointer!T)
		return obj is null;
	else
	{
		auto payload = (cast(ubyte*)&obj)[0 .. T.sizeof];
		auto obj_init = cast(ubyte[])typeid(T).init;
		if (obj_init.ptr)
			return payload[] != obj_init[];
		else
			return payload[] != (ubyte[T.sizeof]).init;
	}
}


template isClass(T)
{
	enum isClass = is(T == class);
}

template isInterface(T)
{
	enum isClass = is(T == interface);
}

template isReferenceType(T)
{
    enum isReferenceType = (isClass!T ||
                            isInterface!T ||
                            isPointer!T ||
                            isDynamicArray!T ||
                            isAssosiativeArray!T);
}


/**
Unique type
SeeAlso:
	Concurrent Clean
	http://sky.zero.ad.jp/~zaa54437/programming/clean/CleanBook/part1/Chap4.html#sc11

has ownership

Construction:
	Constructors receive only constrution arguments or
	rvalue T or Unique.

Example
----
Unique!T u;
assert(u == T.init);

Unique!T u = Unique!T(...);	// In-place construction
u = T(...);					// Replace unique object. Old object is destroyed.
u = T.init;					// Destroy unique object

//T t;
//Unique!T u = t;			// Initialize with lvalue is rejected
//u = t;					// Assignment with lvalue is rejected

Unique!T u = T(...);		// Move construction
//T t = u;					// implicit conversion from Unique!T to T is disabled
T t = u.extract;			// Release unique object
----
*/
struct Unique(T)
{
private:
	// Do not use union in order to initialize __object with T.init.
	T __object;	// initialized with T.init by default-construction
	@property ref ubyte[T.sizeof] __payload(){ return *(cast(ubyte[T.sizeof]*)&__object); }

public:
	/// In-place construction with args which constructor argumens of T
	//this(A...)(auto ref A args)	// @@@BUG5771@@@
	this(A...)(A args)
		if (!is(A[0] == Unique) && !is(A[0] == T))
	{
	  static if (isClass!T)	// emplaceはclassに対して値semanticsで動くので
		__object = new T(args);
	  else
		emplace!T(cast(void[])__payload[], args);
		debug(Unique) writefln("Unique.this%s", (typeof(args)).stringof);
	}
	/// Move construction with rvalue T
	//this(A...)(auto ref A args)	// @@@BUG5771@@@
	this(A...)(A args)
		if (A.length == 1 && is(A[0] == T) && !__traits(isRef, args[0]))	// Rvalue check is now always true...
	{
		move(args[0], __object);
		debug(Unique) writefln("Unique.this(T)");
	}

	// for debug print
	debug(Unique) ~this()
	{
		// for debug
		if (isInitialState(__object))
			debug(Unique) writefln("Unique.~this()");
	}

	/// Disable copy construction (Need fixing @@@BUG4437@@@ and @@@BUG4499@@@)
	@disable this(this){}

	/// Disable assignment with lvalue
	@disable void opAssign(ref const(T) u) {}
	/// ditto
	@disable void opAssign(ref const(Unique) u) {}

	/// Assignment with rvalue of T
	void opAssign(T u)
	{
		move(u, __object);
		debug(Unique) writefln("Unique.opAssign(T): u.val = %s, this.val = %s", u.val, this.val);
	}

	/// Assignment with rvalue of Unique!T
	void opAssign(Unique u)
	{
		move(u, this);
		debug(Unique) writefln("Unique.opAssign(U): u.val = %s, this.val = %s", u.val, this.val);
	}

	// Extract value and release uniqueness
	T extract()
	{
		return move(__object);
	}

	// moveに対しては特段の対応は必要ない
	@disable template proxySwap(T){}	// hack for std.algorithm.swap

	mixin ValueProxy!__object;	// Relay any operations to __object, and
								// blocking implicit conversion from Unique!T to T
}
unittest
{
	static struct S
	{
		int val;

		this(int n)	{ val = n; debug(Unique) writefln("S.this(%s)", val); }
		this(this)	{ debug(Unique) writefln("S.this(this)"); }
		~this()		{
		  debug(Unique)
			if (isInitialState(this))
				writefln("S.~this() val = %s", val); }
	}

	{	debug(Unique){ writefln(">>>> ---"); scope(exit) writefln("<<<< ---"); }
		Unique!S us;
		assert(us == S.init);
	}
	// Do not work correctly. See Issue 5771
/+	static assert(!__traits(compiles,
	{
		S s = S(99);
		Unique!S us = s;
	}));+/
	{	debug(Unique){ writefln(">>>> ---"); scope(exit) writefln("<<<< ---"); }
		auto us = Unique!S(10);
		assert(us.val == 10);
		Unique!S f(){ return Unique!S(20); }
		us = f();
		assert(us.val == 20);
		us = S(30);
		assert(us.val == 30);
	}
	{	debug(Unique){ writefln(">>>> ---"); scope(exit) writefln("<<<< ---"); }
		Unique!S us = S(10);
		assert(us.val == 10);
	}
	{	debug(Unique){ writefln(">>>> ---"); scope(exit) writefln("<<<< ---"); }
		Unique!S us1 = Unique!S(10);
		assert(us1.val == 10);
		Unique!S us2;
		move(us1, us2);
		assert(us2.val == 10);
	}
	{	debug(Unique){ writefln(">>>> ---"); scope(exit) writefln("<<<< ---"); }
		auto us1 = Unique!S(10);
		auto us2 = Unique!S(20);
		assert(us1.val == 10);
		assert(us2.val == 20);
		swap(us1, us2);
		assert(us1.val == 20);
		assert(us2.val == 10);
	}
	static assert(!__traits(compiles,
	{
		auto us = Unique!S(10);
		S s = us;
	}));
	{	debug(Unique){ writefln(">>>> ---"); scope(exit) writefln("<<<< ---"); }
		auto us = Unique!S(10);
		S s = us.extract;
	}

	{	debug(Unique){ writefln(">>>> ---"); scope(exit) writefln("<<<< ---"); }
		static class Foo
		{
			int val;
			this(Foo* foo, int n){ *foo = this; val = n; }
			int opCast(T : int)(){ return val; }
		}

		static assert(!__traits(compiles,
		{
			Foo foo;
			auto us = Unique!Foo(&foo, 10);
			Foo foo2 = cast(Foo)us;		// disable to bypass extract.
			assert(foo2 is foo);
		}));
		{
			Foo foo;
			auto us = Unique!Foo(&foo, 10);
			assert(us.__object is foo);	// internal test
			int val = cast(int)us;
			assert(val == 10);
		}
	}
}


/+
// todo
Unique!T assumeUnique(T t) if (is(Unqual!T == T) || is(T == const))
{
	return Unique!T(t);
}
T assumeUnique(T t) if (is(T == immutable))
{
	return Unique!T(t);
}+/


/**
Make operation proxy except conversion to T.
*/
template ValueProxy(alias a)
{
	auto ref opUnary(string op)()
	{
		return mixin(op ~ "a");
	}

	auto ref opIndexUnary(string op, Args...)(Args args)
	{
		return mixin(op ~ "a[args]");
	}

	auto ref opSliceUnary(string op, B, E)(B b, E e)
	{
		return mixin(op ~ "a[b .. e]");
	}
	auto ref opSliceUnary(string op)()
	{
		return mixin(op ~ "a[]");
	}

	auto ref opCast(T)()
	{
		// block extracting value by casting
		static assert(!is(T : typeof(a)), "Cannot extract object with casting.");
		return cast(T)a;
	}

	auto ref opBinary(string op, B)(B b)
	{
		return mixin("a " ~ op ~ " b");
	}

	bool opEquals(B)(B b)
	{
		return a == b;
	}

	int opCmp(B)(B b)
	{
		static assert(!(__traits(compiles, a.opCmp(b)) && __traits(compiles, a.opCmp(b))));

		static if (__traits(compiles, a.opCmp(b)))
			return a.opCmp(b);
		else static if (__traits(compiles, b.opCmp(a)))
			return -b.opCmp(a);
		else
		{
			return a < b ? -1 : a > b ? +1 : 0;
		}
	}

	auto ref opCall(Args...)(Args args)
	{
		return a(args);
	}

	auto ref opAssign(V)(V v)
	{
		return a = v;
	}

	auto ref opSiliceAssign(V)(V v)
	{
		return a[] = v;
	}
	auto ref opSiliceAssign(V, B, E)(V v, B b, E e)
	{
		return a[b .. e] = v;
	}

	auto ref opOpAssign(string op, V)(V v)
	{
		return mixin("a " ~ op~"= v");
	}
	auto ref opIndexOpAssign(string op, V, Args...)(V v, Args args)
	{
		return mixin("a[args] " ~ op~"= v");
	}
	auto ref opSliceOpAssign(string op, V, B, E)(V v, B b, E e)
	{
		return mixin("a[b .. e] " ~ op~"= v");
	}
	auto ref opSliceOpAssign(string op, V)(V v)
	{
		return mixin("a[] " ~ op~"= v");
	}

	auto ref opIndex(Args...)(Args args)
	{
		return a[args];
	}
	auto ref opSlice()()
	{
		return a[];
	}
	auto ref opSlice(B, E)(B b, E e)
	{
		return a[b .. e];
	}

	auto ref opDispatch(string name, Args...)(Args args)
	{
		// name is property?
		static if (is(typeof(__traits(getMember, s, name)) == function))
			return mixin("a." ~ name ~ "(args)");
		else
			static if (args.length == 0)
				return mixin("a." ~ name);
			else
				return mixin("a." ~ name ~ " = args");
	}
}
unittest
{
	static struct S
	{
		int value;
		mixin ValueProxy!value through;

		this(int n){ value = n; }

		@disable opBinary(string op, B)(B b) if (op == "/"){}
		//alias through.opBinary opBinary;
		auto opBinary(string op, B)(B b) { return through.opBinary!(op, B)(b); }
	}

	S s = S(10);
	++s;
	assert(s.value == 11);

	assert(cast(double)s == 11.0);

	assert(s * 2 == 22);
	static assert(!__traits(compiles, s / 2));
	S s2 = s * 10;
	assert(s2 == 110);
	s2 = s2 - 60;
	assert(s2 == 50);

	static assert(!__traits(compiles, { int x = s; }()));

	int mul10(int n){ return n * 10; }
	static assert(!__traits(compiles, { mul10(s) == 110; }()));
}


//void main(){}
