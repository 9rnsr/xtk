module typecons.tag_union;

public import typecons.tuple_match;

version(unittest)
{
	import std.stdio : pp=writefln;
}


/// 
template TagUnion(T...)
{
private:
	import typecons.meta;
	import std.conv : to;
	import std.metastrings;

	/// BUG shuld be inner template, though dmd dead
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

	template GetNames(E...)
	{
		static if (E.length == 0)
		{
			alias TypeTuple!() GetNames;
		}
		else static if (is(typeof(E[0])) && isSomeString!(typeof(E[0])))
		{
			alias TypeTuple!(E[0], GetNames!(E[1..$])) GetNames;
		}
		else
		{
			alias GetNames!(E[1..$]) GetNames;
		}
	}
	template GetFieldsStart(size_t N)
	{
		enum GetFieldsStart = staticIndexOf!(GetNames!T[N], T) + 1;
	}
	template GetFieldsEnd(size_t N)
	{
		static if (N==GetNames!T.length-1)
		{
			enum GetFieldsEnd = T.length;
		}
		else
		{
			enum GetFieldsEnd = staticIndexOf!(GetNames!T[N+1], T);
		}
	}

  // basic parameters
	alias GetNames!T TyconTags;
	enum TyconCnt = TyconTags.length;
	template TyconTag(size_t N)
	{
		enum TyconTag = GetNames!T[N];
	}
	template TyconSig(size_t N)
	{
		alias TypeTuple!(T[GetFieldsStart!N .. GetFieldsEnd!N]) TyconSig;
	}


	template LeastUnsignedType(size_t N)
	{
		     static if (N <= ubyte .max) alias ubyte	LeastUnsignedType;
		else static if (N <= ushort.max) alias ushort	LeastUnsignedType;
		else static if (N <= uint  .max) alias uint		LeastUnsignedType;
		else static if (N <= ulong .max) alias ulong	LeastUnsignedType;
		else static assert(0, "tag-size is too big");
		
	}

  // tycon tags
	enum MakeTyconTags = mixin(expand!q{
		enum Tag:${ LeastUnsignedType!TyconCnt }{
			${ staticReduce!(q{A==""?B~"=0":A~", "~B}, "", TyconTags) }
		}
	});

  // tycon types
	template MakeTyconTypeField(size_t N)
	{
		template MakeTyconTypeField(size_t I)
		{
			enum MakeTyconTypeField = ToLongString!(TyconSig!N[I])~" _"~to!string(I);
		}
	}
	template MakeTyconType(size_t N)
	{
		enum MakeTyconType = mixin(expand!q{
			static struct ${ TyconTag!N }_T
			{
				Tag tag;
				${ staticReduce!(q{A==""?B:A~"; "~B}, "", generateTuple!(0, TyconSig!N.length, MakeTyconTypeField!N)) };
			}
		});
	}
	enum MakeTyconTypes =
		staticReduce!(q{A==""?B:A~"\n"~B}, "", generateTuple!(0, TyconCnt, MakeTyconType));

  // tycon datas
	template MakeTyconData(size_t N)
	{
		enum MakeTyconData = mixin(expand!q{
			${ TyconTag!N }_T data$N;
		});
	}
	enum MakeTyconDatas = mixin(expand!q{
		union
		{
			Tag tag;
			${ staticReduce!(q{A==""?B:A~" "~B}, "", generateTuple!(0, TyconCnt, MakeTyconData)) }
		}
	});

  // ctors
	template MakeCtor(size_t N)
	{
		enum MakeCtor = mixin(expand!q{
			this(ref ${ TyconTag!N }_T data){ data$N = data; }
		});
	}
	enum MakeCtors =
		staticReduce!(q{A==""?B:A~"\n"~B}, "", generateTuple!(0, TyconCnt, MakeCtor));

  // tycons
	template MakeTycon(size_t N)
	{
		enum MakeTycon = mixin(expand!q{
			static auto ${ TyconTag!N }(U...)(U args){
				static if (is(U == TypeTuple!(
						${ staticReduce!(q{A==""?B:A~", "~B}, "", staticMap!(ToLongString, TyconSig!N)) }))

				//TODO: 派生型の値が与えられたときに上手いこと判定してくれない

//						||is(U : TypeTuple!(
//						${ staticReduce!(q{A==""?B:A~", "~B}, "", staticMap!(ToLongString, TyconSig!N)) }))
																											)
				{
					return new typeof(this)(${ TyconTag!N }_T(Tag.${ TyconTag!N }, args));
				}
				else static if (canMatch!(Match!U, Tuple!(
						${ staticReduce!(q{A==""?B:A~", "~B}, "", staticMap!(ToLongString, TyconSig!N)) })))
				{
					return pattern(Tag.${ TyconTag!N }, args);
				}
				else
				{
					static assert(0, "tycon: "~typeof(args).stringof~", TypeTuple!("~
						`${ staticReduce!(q{A==""?B:A~", "~B}, "", staticMap!(ToLongString, TyconSig!N)) })`);
				}
			}
		});
	}
	enum MakeTycons =
		staticReduce!(q{A==""?B:A~"\n"~B}, "", generateTuple!(0, TyconCnt, MakeTycon));

  // opMatch
	template MakeMatchCase(size_t N)
	{
		enum MakeMatchCase = mixin(expand!q{
			case Tag.${ TyconTag!N }:
			  static if (canMatch!(Match!U, Tuple!(Tag, TyconSig!$N)))
				return m = tuple(data$N.tupleof);
			  else
				return false;
		});
	}
	template MakeMatchInstanceIf(size_t N)
	{
		enum MakeMatchInstanceIf = mixin(expand!q{
			canMatch!(Match!U, Tuple!(Tag, TyconSig!$N))
		});
	}
	enum MakeMatch = mixin(expand!q{
		bool opMatch(U...)(ref Match!U m){
			static if (!(
				${ staticReduce!(q{A==""?""~B:A~" || "~B}, "", generateTuple!(0, TyconCnt, MakeMatchInstanceIf)) }
			))
			{
				static assert(0, "match");
			}
			final switch( tag ){
			${ staticReduce!(q{A==""?B:A~"\n"~B}, "", generateTuple!(0, TyconCnt, MakeMatchCase)) }
			}
		}
	});

  // export tycons out of class/struct
	enum MakeTyconAlias = mixin(expand!q{
		import typecons.meta;
		template MakeAlias(size_t N)
		{
			enum MakeAlias =
				"alias "
					~ToLongString!(typeof(this))~"."~
						TypeTuple!(${ staticReduce!(q{A=="" ? "\""~B : A~"\", \""~B}, "", TyconTags)~"\"" })[N]
						~" "~
						TypeTuple!(${ staticReduce!(q{A=="" ? "\""~B : A~"\", \""~B}, "", TyconTags)~"\"" })[N]
					~";";
		}
		template Tycons()
		{
			enum Tycons =
				staticReduce!(q{A==""?B:A~"\n"~B}, "", generateTuple!(0, ${to!string(TyconCnt)}, MakeAlias));
		}
	});

private:
	mixin(MakeTyconTags);
	mixin(MakeTyconTypes);
	mixin(MakeTyconDatas);
	mixin(MakeMatch);
public:
	mixin(MakeCtors);
	mixin(MakeTycons);
	mixin(MakeTyconAlias);
}


//==============================================================================

version(unittest)
{
	alias int IntT;
	class temp
	{
		static class Label{}
	}
	enum BinOp:ubyte{ ADD,SUB }
	enum Relop:ubyte{ EQ,NE,LT,GT,LE,GE }

	class Exp
	{
		mixin TagUnion!(
			"CONST",IntT,
			"NAME",	temp.Label,
			"ESEQ",	Stm, Exp
		);
	}
	mixin(Exp.Tycons!());

	class Stm
	{
		mixin TagUnion!(
			"MOVE",	Exp, Exp,
			"LABEL",temp.Label
		);
	}
	mixin(Stm.Tycons!());
}
unittest
{
	pp("unittest: tag_union");

	auto l = new temp.Label();

	Stm s = LABEL(l);
	assert(s.tag == 1);
	assert(s.data1._0 is l);

	Exp e = CONST(10);
	assert(e.tag == 0);
	assert(e.data0._0 == 10);

	Exp eseq = ESEQ(s, e);
	assert(eseq.tag == 2);
	assert(eseq.data2._0 is s);
	assert(eseq.data2._1 is e);

	Exp eseq2 = ESEQ(s, CONST(20));
	assert(eseq2.tag == 2);
	assert(eseq2.data2._0 is s);
	assert(eseq2.data2._1.tag == 0);
	assert(eseq2.data2._1.data0._0 == 20);

	// match
	{	Stm s_;
		Exp e_;
		int n;
		// pattern match(OK)
		if (ESEQ(&s_, &e_) = eseq)
		{
			assert(s is s_);
			assert(e is e_);
		}
		else
		{
			assert(0);
		}
		s_ = null, e_ = null;

		// nested pattern match(OK)
		if (ESEQ(&s_, CONST(&n)) = eseq2)
		{
			assert(s is s_);
			assert(n == 20);
		}
		else
		{
			assert(0);
		}

		// signature mismatch(tag-value, fields...)
		static assert(!__traits(compiles, ESEQ(&s_, &e_) = tuple(7, s, e)));

		// tag pattern match(OK)
		if (ESEQ(&s_, e) = eseq)
		{
			assert(s is s_);
		}
		else
		{
			assert(0);
		}

		// tag pattern match(NG)
		if (CONST(&n) = eseq)
		{
			assert(0);
		}

		// value pattern match(NG)
		s_ = null, e_ = null;
		if (ESEQ(&s_, e_) = eseq)
		{
			assert(0);
		}

		// tycon-signature mismatch
		static assert(!__traits(compiles, ESEQ(&s_) = eseq));

		// data-type mismatch
		static assert(!__traits(compiles, MOVE(&e_, &e_) = eseq));

		// raw match
		Exp.Tag t;
		if (pattern(&t, &s_, &e_) = eseq)
		{
			assert(t == Exp.Tag.ESEQ);
			assert(s is s_);
			assert(e is e_);
		}
		else
		{
			assert(0);
		}
	}
}

unittest
{
	pp("unittest: tag_union ->match");

	auto x = CONST(1);
	
	int d;
	temp.Label l;
	
	match(x,
		CONST(&d),	{ assert(d == 1); },
		_,			{ assert(0); }
	);
	match(x,
		NAME(&l),	{ assert(0); },
		_,			{ /*otherwise*/; }
	);
}
