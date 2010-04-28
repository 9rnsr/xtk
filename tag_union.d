module tag_union;

public import tuple_tie;

//version(unittest){
	import std.stdio : pp=writefln;
//}else{
//	void pp(T...)(T args){}
//}


template TagUnion(T...)
{
private:
	import meta;
	import std.conv : to;
	
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
	
	
	public enum MakeTyconTags =
		"enum Tag:"~(LeastUnsignedType!TyconCnt).stringof~"{ "
			~staticReduce!(q{A==""?B~"=0":A~", "~B}, "", TyconTags)~" "
		"}";
	
	template MakeTyconTypeField(size_t N)
	{
		template MakeTyconTypeField(size_t I)
		{
			enum MakeTyconTypeField = ToLongString!(TyconSig!N[I])~" _"~to!string(I);
		}
	}
	template MakeTyconType(size_t N)
	{
		enum MakeTyconType =
			"static struct "~TyconTag!N~"_T{ "
				"Tag tag; "
				~staticReduce!(q{A==""?B:A~"; "~B}, "", generateTuple!(0, TyconSig!N.length, MakeTyconTypeField!N))~"; "
			"}";
	}
	public enum MakeTyconTypes =
		staticReduce!(q{A==""?B:A~"\n"~B}, "", generateTuple!(0, TyconCnt, MakeTyconType));
	
	template MakeTyconData(size_t N)
	{
		enum MakeTyconData = TyconTag!N~"_T data"~to!string(N)~";";
	}
	public enum MakeTyconDatas =
		"union{ "~
			"Tag tag; "
			~staticReduce!(q{A==""?B:A~" "~B}, "", generateTuple!(0, TyconCnt, MakeTyconData))~
		" }";

	template MakeCtor(size_t N){
		enum MakeCtor =
			"this(ref "~TyconTag!N~"_T data){ data"~to!string(N)~" = data; }";
	}
	public enum MakeCtors =
		staticReduce!(q{A==""?B:A~"\n"~B}, "", generateTuple!(0, TyconCnt, MakeCtor));
	
	template MakeTycon(size_t N){
		enum MakeTycon =
			`static auto `~TyconTag!N~`(U...)(U args){`															"\n"
			`	static if (is(U == TypeTuple!(`
						~staticReduce!(q{A==""?B:A~", "~B}, "", staticMap!(ToLongString, TyconSig!N))~	`)))`	"\n"
			`	{`																								"\n"
			`		return new typeof(this)(`~TyconTag!N~`_T(Tag.`~TyconTag!N~`, args));`						"\n"
			`	}`																								"\n"
			`	else static if (Tie!U.isMatchingTuple!(`
						~staticReduce!(q{A==""?B:A~", "~B}, "", staticMap!(ToLongString, TyconSig!N))~	`))`	"\n"
			`	{`																								"\n"
			`		return tie(Tag.`~TyconTag!N~`, args);`														"\n"
			`	}`																								"\n"
			`	else`																							"\n"
			`	{`																								"\n"
			`		static assert(0);`																			"\n"
			`	}`																								"\n"
			`}`;
	}
	public enum MakeTycons =
		staticReduce!(q{A==""?B:A~"\n"~B}, "", generateTuple!(0, TyconCnt, MakeTycon));
	
	
	template MakeTieMatchCase(size_t N){
		enum MakeTieMatchCase =
			`	case Tag.`~TyconTag!N~`:`														"\n"
			`		static if (Tie!U.isMatchingTuple!(Tag, TyconSig!`~to!string(N)~`))`			"\n"
			`		{`																			"\n"
			`			return tie = tuple(data`~to!string(N)~`.tupleof);`						"\n"
			`		}`
			`		else`																		"\n"
			`		{`																			"\n"
			`			return false;`															"\n"
			`		}`;
	}
	template MakeTieMatchInstanceIf(size_t N)
	{
		enum MakeTieMatchInstanceIf =
			`Tie!U.isMatchingTuple!(Tag, TyconSig!`~to!string(N)~`)`;
	}
	public enum MakeTieMatch = 
		`bool opTieMatch(U...)(ref Tie!U tie){`													"\n"
		`	static if (!(`
				~staticReduce!(q{A==""?""~B:A~" || "~B}, "", generateTuple!(0, TyconCnt, MakeTieMatchInstanceIf))~
			`))`																				"\n"
		`	{`																					"\n"
		`		static assert(0);`																"\n"
		`	}`																					"\n"
		"	\n"
		`	final switch( tag ){`																"\n"
		~staticReduce!(q{A==""?B:A~"\n"~B}, "", generateTuple!(0, TyconCnt, MakeTieMatchCase))~	"\n"
		`	}`																					"\n"
		`}`;
	
	
	enum MakeTyconAlias =
		`import meta;`																							"\n"
		`template MakeAlias(size_t N)`																			"\n"
		`{`																										"\n"
		`	enum MakeAlias =`																					"\n"
		`		"alias "`																						"\n"
		`			~ToLongString!(typeof(this))~"."~`															"\n"
		`				TypeTuple!(`~staticReduce!(q{A==""?"\""~B:A~"\", \""~B}, "", TyconTags)~`")[N]`			"\n"
		`				~" "~`																					"\n"
		`				TypeTuple!(`~staticReduce!(q{A==""?"\""~B:A~"\", \""~B}, "", TyconTags)~`")[N]`			"\n"
		`			~";";`																						"\n"
		`}`																										"\n"
		`template Tycons()`																						"\n"
		`{`																										"\n"
		`	enum Tycons =`																						"\n"
		`		staticReduce!(q{A==""?B:A~"\n"~B}, "", generateTuple!(0, `~to!string(TyconCnt)~`, MakeAlias));`	"\n"
		`}`;

public:
  private:
	mixin(MakeTyconTags);
	mixin(MakeTyconTypes);
	mixin(MakeTyconDatas);
	mixin(MakeTieMatch);
  public:
	mixin(MakeCtors);
	mixin(MakeTycons);
	mixin(MakeTyconAlias);
}


//==============================================================================

alias int IntT;
class temp
{
	static class Label{}
	static class Temp{}
}
enum BinOp:ubyte{ ADD,SUB }
enum Relop:ubyte{ EQ,NE,LT,GT,LE,GE }


class Exp
{
	mixin TagUnion!(
		"VINT",	IntT,
		"VFUN",	Exp, temp.Label,
		"NAME",	temp.Label,
		"TEMP",	temp.Temp,
		"BIN", 	BinOp, Exp, Exp,
		"MEM", 	Exp,
		"CALL",	Exp, Exp[],
		"ESEQ",	Stm, Exp
	);
}
mixin(Exp.Tycons!());
static assert(__traits(classInstanceSize, Exp) == 24);

class Stm
{
	mixin TagUnion!(
		"MOVE",	Exp, Exp,
		"EXP",	Exp,
		"JUMP",	Exp, temp.Label[],
		"CJUMP",Relop, Exp, Exp, temp.Label, temp.Label,
		"SEQ",	Stm[],
		"LABEL",temp.Label
	);
}
mixin(Stm.Tycons!());
static assert(__traits(classInstanceSize, Stm) == 28);


unittest
{
	pp("tag_union.unittest");
	
	auto l = new temp.Label();
	
	Stm s = LABEL(l);
	assert(s.tag == 5);
	assert(s.data5._0 is l);
	
	Exp e = VINT(100);
	assert(e.tag == 0);
	assert(e.data0._0 == 100);
	
	Exp eseq = ESEQ(s, e);
	assert(eseq.tag == 7);
	assert(eseq.data7._0 is s);
	assert(eseq.data7._1 is e);
	
	// tie match
	{	Stm s_;
		Exp e_;
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
		if (MEM(&e_) = eseq)
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
		if (tie(&t, &s_, &e_) = eseq)
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
	
	pp("-> test ok");
}
