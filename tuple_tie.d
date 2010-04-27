module tuple_tie;

public import std.typecons : Tuple;
public import std.typecons : tuple;

import std.typetuple;
import std.traits;

// compile-time debug
//debug = PP_Satisfy;
//debug = PP_assignT;

// run-time debug
//debug = PP_Runtime;
debug(PP_Runtime){
	import std.stdio : pp=writefln;
}else{
	void pp(T...)(T args){}
}


private:
	struct Placeholder{}
	static Placeholder wildcard;
	alias wildcard _;

	// 部分特殊化テンプレートのマッチ判定用
  version(none){
	template Match(alias T, U){
		pragma(msg, "<Match, T=", T, ", U=", U, ", Result=", __traits(compiles, {void f(X...)(T!X x){}; f(U.init);}), ">");
		enum Match = __traits(compiles, {void f(X...)(T!X x){}; f(U.init);});
	}
	template TieMatch(U)	{ enum TieMatch = Match!(.Tie, U); }
	template TupleMatch(U)	{ enum TupleMatch = Match!(.Tuple, U); }
  }else{
	template TieMatch(U)
	{
		enum TieMatch = __traits(compiles, {void f(X...)(Tie!X x){}; f(U.init);});
	}
	template TupleMatch(U)
	{
		enum TupleMatch = __traits(compiles, {void f(X...)(Tuple!X x){}; f(U.init);});
	}
  }

public:
struct Tie(T...)
{
private:
	template satisfy(int I, U...)
	{
		static assert(T.length == I + U.length);
		static if( U.length == 0 ){
			enum result = true;
			debug(PP_Satisfy) pragma(msg, "* TieMatch.satisfy[-] -> OK");
		}else{
			alias T[I] Lhs;
			alias U[0] Rhs;
			
		//	pragma(msg, "> Lhs=", Lhs, ", TieMatch = ", TieMatch!Lhs);
		//	pragma(msg, "> Rhs=", Rhs, ", TupleMatch = ", TupleMatch!Rhs);
		//	//static if( TieMatch!Lhs ) static assert(0);
			
			debug(PP_Satisfy) pragma(msg, "- TieMatch.satisfy[",I,"] -> ???? (T,U)=(",Lhs,", ",Rhs,")");
			static if( is(Lhs == typeof(wildcard)) ){
				//wildcard
				debug(PP_Satisfy) pragma(msg, "- TieMatch.satisfy[",I,"] -> Wildcard (T,U)=(",Lhs,", ",Rhs,")");
				enum result = true && satisfy!(I+1, U[1..$]).result;
			}else static if( is(Rhs : Lhs) || (is(Lhs==void*) && is(Rhs == class)) ){
				//value
				debug(PP_Satisfy) pragma(msg, "- TieMatch.satisfy[",I,"] -> Value (T,U)=(",Lhs,", ",Rhs,")");
				enum result = true && satisfy!(I+1, U[1..$]).result;
			}else static if( is(Lhs == Rhs*) ){
				// capture
				debug(PP_Satisfy) pragma(msg, "- TieMatch.satisfy[",I,"] -> Capture (T,U)=(",Lhs,", ",Rhs,")");
				enum result = true && satisfy!(I+1, U[1..$]).result;
		//	}else static if( is(Lhs V : Tie!W, W...) && is(Rhs X : Tuple!Y, Y...) ){	//is式だと現状タプルを取れない&DMDが落ちる
		//	}else static if( __traits(compiles, TieMatch!Lhs) && __traits(compiles, TupleMatch!Rhs) ){
			}else static if( TieMatch!Lhs && TupleMatch!Rhs ){
				//pattern
				debug(PP_Satisfy) pragma(msg, "- TieMatch.satisfy[",I,"] -> Pattern (T,U)=(",Lhs,", ",Rhs,")");
				//pragma(msg, "* Pattern.Params "~(isPartialTemplate!(Tuple, Rhs).params).stringof);
			//pragma(msg, "W=", W, ", Y=", Y);
				//isPartialTemplateでparamsが取れないため、NestしたTieのマッチ可能判定はopEquals内部でのCode生成時に行う
				//TODO: ネストしたTieのシグネチャ判定をコンパイル時に行う
			//	enum result = Lhs.isMatchingTuple!W && satisfy!(I+1, U[1..$]).result;
				enum result = true && satisfy!(I+1, U[1..$]).result;
			}else{
				debug(PP_Satisfy) pragma(msg, "* TieMatch.satisfy[",I,"] -> Error (T,U)=(",Lhs,", ",Rhs,")");
				enum result = false;
			}
		}
	}
	public template isMatchingTuple(U...)
	{
		static if( T.length == U.length ){
			enum isMatchingTuple = satisfy!(0, U).result;
		}else{
			enum isMatchingTuple = false;
		}
		//pragma(msg, "- isMatchingTuple: T=", T, ", U=", U, ", result=", isMatchingTuple);
	}

	T refs;
	
	// U...を取り出すためにprivate関数にする
	bool assignTuple(U...)(Tuple!U rhs){
		
		static if( isMatchingTuple!U ){
			debug(PP_assignT) pragma(msg, "* ", Tie.stringof, ".assignTuple(", (Tuple!U).stringof, ") rhs)", " -> isMatchingTuple OK ...");
			auto result = true;
			foreach( int I,t; refs ){
				alias T[I] Lhs;
				alias U[I] Rhs;
				
				//debug(PP_assignT) pragma(msg, "Tie.opAssign, T[", cast(int)I, "]=", T[I].stringof);
				debug(PP_Runtime) pp("Tie.opAssign, T[%s]=%s", I, T[I].stringof);
				static if( is(T[I] == typeof(wildcard)) ){			//wildcard
					debug(PP_assignT) pragma(msg, "- [",I,"] wildcard (T,U)=(",T[I],", ",U[I],")");
					debug(PP_Runtime) pp("  wildcard (T,U)=(%s, %s)",(T[I]).stringof,(U[I]).stringof);
					result = result && true;
				}else static if( isPointer!(T[I]) && !is(T[I] == void*) ){	// capture
					debug(PP_assignT) pragma(msg, "- [",I,"] capture (T,U)=(",T[I],", ",U[I],")");
					debug(PP_Runtime) pp("  capture (T,U)=(%s, %s)",(T[I]).stringof,(U[I]).stringof);
					debug(PP_Runtime) pp("  refs[%s]=%s, rhs.field[%s]=%s", I, refs[I], I, rhs.field[I]);
					*refs[I] = rhs.field[I];
					pp("cap");
					result = result && true;
					pp("cap end");
				}else static if( is(T[I] V == Tie!W, W...) ){				//pattern
					debug(PP_assignT) pragma(msg, "- [",I,"] pattern (T,U)=(",T[I],", ",U[I],")");
					debug(PP_Runtime) pp("  pattern (T,U)=(%s, %s)",(T[I]).stringof,(U[I]).stringof);
					result = result && t.opAssign(rhs.field[I]);
				}else{												//value
					debug(PP_assignT) pragma(msg, "- [",I,"] value (T,U)=(",T[I],", ",U[I],")");
					debug(PP_Runtime) pp("  value (T,U)=(%s, %s)",(T[I]).stringof,(U[I]).stringof);
					static if( is(T[I] == void*) ){	//null and class|pointer
						static assert( is(Rhs == class) || isPointer!(Rhs) );
						pp("val0 ");
						result = result && (cast(Rhs)refs[I] is rhs.field[I]);
						pp("val0 end");
					}else{
						pp("val1");
						static if( is(Lhs == class) && is(Rhs == class) ){
							pp("val1-class", refs[I]);
							result = result && object.opEquals(refs[I], rhs.field[I]);
						}else{
							static assert(!is(Lhs == class) && !is(Rhs == class));
							pp("val1-non-class", refs[I]);
							result = result && (refs[I] == rhs.field[I]);
						}
						pp("val1 end");
					}
				}
			}
			return result;
		}else{
			debug(PP_assignT) pragma(msg, "* ", Tie.stringof, ".assignTuple(", (Tuple!U).stringof, ") rhs)", " -> isMatchingTuple NG");
			//return false;
			static assert(0);
		}
	}

public:
	auto opAssign(U)(U rhs){
		///pragma(msg, U, ".opTieMatch exist? ", __traits(compiles, rhs.opTieMatch(this)));	//already false
		///pragma(msg, "opTieMatch has? ", __traits(hasMember, rhs, opTieMatch));			//ditto
		//pragma(msg, U, ".opTieMatch exist? ", __traits(compiles, rhs.opTieMatch));
		
		static if( is(U X == Tuple!(W), W...) ){
			debug(PP_assignT) pragma(msg, typeof(this).stringof, ".opAssign(", U.stringof, ")", " -> tuple match");
			return assignTuple(rhs);
		}else static if( __traits(compiles, rhs.opTieMatch) ){
			//ユーザー定義型に対しては、opTieMatchによってマッチ処理を委譲する
			//opTieMatchの実体化に失敗 == シグネチャ不一致検出
			debug(PP_assignT) pragma(msg, typeof(this).stringof, ".opAssign(", U.stringof, ")", " -> user-defined opTieMatch");
			return rhs.opTieMatch(this);
		}else static if( is(U == Tie) ){
			//Tieメンバのコピー
			debug(PP_assignT) pragma(msg, typeof(this).stringof, ".opAssign(", U.stringof, ")", " -> field copy");
			this.tupleof = rhs.tupleof;
		}else{
			// シグネチャ不一致
			debug(PP_assignT) pragma(msg, typeof(this).stringof, ".opAssign(", U.stringof, ")", " -> match fail");
			static assert(0);
		}
	}
	
}

Tie!T tie(T...)(T tup)
{
	//pragma(msg, "tie[...]: T="~T.stringof);
	Tie!T ret;
	foreach( i,t; tup ){
		pp("tie, T[%s]=%s", i, T[i].stringof);
		static if( is(typeof(t) == typeof(wildcard)) ){
			pp("  wildcard");
		}else static if( isPointer!(T[i]) ){			// capture
			pp("  capture");
			ret.refs[i] = tup[i];
			pp("  ret.refs[%s]=%s, tup[%s]=%s", i, ret.refs[i], i, tup[i]);
		}else{											//pattern
			//pragma(msg, "Pattern: "~T[i].stringof);
			pp("  pattern");
			ret.refs[i] = tup[i];
		}
	}
	return ret;
}

unittest{
	pp("tuple_tie.unittest");
	//キャプチャ
	{	int n = 10;
		double d = 3.14;
		if( tie(&n, &d) = tuple(20, 1.4142) ){
			assert(n == 20);
			assert(d == 1.4142);
		}else{
			assert(0);
		}
	}

	//ワイルドカード
	{	int n = 10;
		double d = 3.14;
		if( tie(&n, _) = tuple(20, 1.4142) ){
			assert(n == 20);
			assert(d == 3.14);
		}else{
			assert(0);
		}
	}
	{	int n = 10;
		double d = 3.14;
		if( tie(_, &d) = tuple(20, 1.4142) ){
			assert(n == 10);
			assert(d == 1.4142);
		}else{
			assert(0);
		}
	}

	//値一致(基本型、tuple)
	{	int n = 10;
		if( tie(&n, 1.4142) = tuple(20, 1.4142) ){
			assert(n == 20);
		}else{
			assert(0);
		}
	}
	{	int n = 10;
		double d = 1.4142;
		if( tie(&n, tuple(d, "str")) = tuple(20, tuple(1.4142, "str")) ){
			assert(n == 20);
		}else{
			assert(0);
		}
	}
	//値一致(null)
	{	int n = 10;
		int* p = null;
		if( tie(&n, null) = tuple(10, p) ){
		}else{
			assert(0);
		}
		
		p = &n;
		if( tie(&n, null) = tuple(10, p) ){
			assert(0);
		}
	}
	{	int n = 10;
		static class A{}
		A a;
		if( tie(&n, null) = tuple(10, a) ){
			assert(n == 10);
		}else{
			assert(0);
		}
		a = new A();
		if( tie(&n, null) = tuple(10, a) ){
			assert(0);
		}
	}

	//ネストしたtie
	{	int n = 10;
		double d = 3.14;
		string s;
		if( tie(&n, tie(&d, &s)) = tuple(20, tuple(1.4142, "str")) ){
			assert(n == 20);
			assert(d == 1.4142);
			assert(s == "str");
		}else{
			assert(0);
		}
	}
	{	double d = 3.14;
		if( tie(20, tie(&d, "str")) = tuple(20, tuple(1.4142, "str")) ){
			assert(d == 1.4142);
		}else{
			assert(0);
		}
	}

	//ユーザー定義型
	{	static class C{
			int m_n; double m_d;
			this(int n, double d){ m_n=n, m_d=d; }
			bool opTieMatch(U...)(ref Tie!U tie){
				return tie = tuple(m_n, m_d);
			}
		}
		auto c = new C(10, 3.14);
		int n;
		double d = 3.14;
		if( tie(&n, d) = c ){
			assert(n == 10);
		}else{
			assert(0);
		}
	}

	//シグネチャ不一致検出
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
	{	static class N{
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
