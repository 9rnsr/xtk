/**
	定義
	Source/Sinkの基本要素はubyteである
*/
//module std.device;
import std.array, std.algorithm, std.range, std.traits;
version(Windows)
{
	import core.sys.windows.windows;
}

//debug = Move;

import std.stdio;
import std.perf;
void main(string[] args)
{
	if (args.length == 2)
	{

	/+	foreach (char c; buffered(File(args[1])))
		{
			if (c != '\r') write(c);
		}	// +/
		
		auto pc = new PerformanceCounter;
		pc.start;
		
		size_t nlines = 0;
	//	//バイト列をchar列のバイト表現とみなし、decoder!dcharでcharのRangeに変換する
	//	foreach (line; lined!string(decoder!char(buffered(File(args[1])))))
		
		foreach (i; 0 .. 1000)
		{
			// ubyteの列をstringとみなしてLine分割する
		//	foreach (line; lined!string(buffered(File(args[1]), 2048)))
		
			// ubyteの列(バッファリング有り)をconst(char)[]のsliceで取る
			foreach (line; lined!(const(char)[])(buffered(File(args[1]), 2048)))
			{
				line.dup, ++nlines;
			}
			//assert(0);
		}
		pc.stop;
		
		printf("%g line/sec\n", nlines / (1.e-6 * pc.microseconds));
	}
}


/*
	Check that S is source.	(exact)
	Source supports empty and pull operation.
*/
template isSource(S)
{
	enum isSource = is(typeof({
		void dummy(ref S s)
		{
			if (s.empty){}
			ubyte[] buf;
			size_t len = 0;
			const(ubyte)[] data = s.pull(len, buf);
		}
	}()));
}

/*
	Check that S is sink.
	Sink supports empty(?) and push operation.
*/
template isSink(T)
{
	enum isSink = is(typeof({
		void dummy(ref S s)
		{
			if (s.empty){}	//?
			const(ubyte)[] buf;
			if (push(s, buf)) {}
		}
	}()));
}

/*
	Device supports both operations of source and sink.
*/
template isDevice(S)
{
	enum isDevice = isSource!S && isSink!S;
}

// seek whence...
enum SeekPos {
	Set,
	Cur,
	End
}

/*
	Check that S is seekable source or sink.
	Seekable source/sink supports seek operation.
*/
template isSeekable(S)
{
	enum isSeekable = is(typeof({
		void dummy(ref S s)
		{
			s.seek(0, SeekPos.Set);
		}
	}()));
}


/*
	sからlenバイトを読み出し、bufへ格納する
	→	1.callerから与えられたバッファを埋める
		2.calleeでバッファを確保し、Viewを返す
*/
const(ubyte)[] pull(S)(ref S s, size_t len, ubyte[] buf=null)
{
	static if (hasMember!(S, "pull") && is(typeof(s.pull(len, buf))))
	{
		return s.pull(len, buf);
	}
//	else static if (hasSlicing!S && hasLength!S)
//	{
//		//todo
//	}
	else static if (isInputRange!S)
	{
		// todo バイト列とオブジェクト型の変換(serialization)はどうする？
		static assert(is(ElementType!S : const(ubyte)));
		
		if (buf.length > 0)
			len = min(buf.length, len);
		else
			buf.length = len;
		
		auto outbuf = buf[0 .. len];
		
		// rangeをSourceとして扱う場合はすべてputに任せる
		//writefln("S == %s, outbuf.length == %s, s.length == %s", S.stringof, outbuf.length, s.length);
		
	//	put(outbuf, s);
		// outbufを埋め尽くすか、sが空になるまでputする
		// std.range.putはsからすべて吐き出せない場合にbreakしてくれない
		for (; !s.empty && !outbuf.empty; s.popFront())
		{
			put(outbuf, s.front);
		}
		
		return buf[0 .. $-outbuf.length];
	}
	else
	{
		static assert(0, S.stringof~" does not support pull operation");
	}
}
unittest
{
	ubyte[] arr = [1,2,3];
	ubyte[] src = arr;
	const(ubyte)[] buf = src.pull(2);
	assert(src == [3]);
	assert(buf == [1,2]);
	
	struct ByteRange
	{
		ubyte[] arr;
		@property bool empty() const{ return arr.length == 0; }
		@property ref ubyte front()	{ return arr[0]; }
		void popFront()				{ arr = arr[1 .. $]; }
	}
	auto r = ByteRange(arr);
	buf = .pull(r, 2);
	assert(array(r) == [3]);
	assert(buf == [1, 2]);
}

/**
	sourceの終端に達するか、もしくは正しくlenバイトのデータをpullする
*/
const(ubyte)[] pullExact(S)(ref S s, size_t len, ubyte[] buf=null)
out(data)
{
	assert(s.empty || data.length == len);
}
body
{
	//debug(Decoder) writefln("pullExact len = %s", len);

	if (buf.length > 0)
		len = min(buf.length, len);
	else
		buf.length = len;	// allocation
	
	auto data = .pull(s, len, buf);
	if (data.length < len)
	{
		auto rem = buf[data.length .. $];
		while (!s.empty && rem.length > 0)
		{
			data = .pull(s, rem.length, rem);
			rem = rem[data.length .. $];
		}
		//data = buf[0 .. $ - rem.length];
		//debug(Decoder) writefln("pullExact rem.length = %s, s.empty = %s", rem.length, s.empty);
		if (rem.length > 0)
			throw new /*Read*/Exception("not enough data in stream");	// from std.stream.readExact
	}
	//return data;
	return buf;
}
unittest
{
}

/**
	引数bufのslicingと、返値の2方向で処理後の状態を返している
	→あんまりよくないデザインかな…
	
*/
bool push(S)(ref S s, ref const(ubyte)[] buf)
{
	static if (isOutputRange!S)
	{
		// todo バイト列とオブジェクト型の変換(serialization)はどうする？
		static assert(is(ElementType!S : ubyte));
		
		//rangeをsinkとして扱う場合は、putにすべてを任せる
		put(s, buf);
		return buf.length > 0 || !s.empty;
	}
	else static if (is(typeof(s.push(buf))))
	{
		return s.push(buf);
	}
	else
	{
		static assert(0, S.stringof~" does not support push operation");
	}
}

/**
	RがRandomAccessRangeでない場合、Cur + |offset|以外の操作がO(n)となる
	→isRandomAccessRange!R を要件とする (いろいろ考えたが、おそらくこれが妥当と思われる)
	→最低限の用件としては「ForwardかつLengthとSlicingを持つ」となる
*/
struct Seekable(R)
	if (isForwardRange!R && hasLength!R && hasSlicing!R)
{
	R orig;
	R view;
	size_t pos;
	
	this(R r)
	{
		orig = r.save;
		view = r.save;
		pos = 0;
	}
	
	alias view this;	// map operations
	
	@property bool empty() const
	{
		return view.empty;
	}
	
//static if (isSource!R)	//Rangeなら少なくともInput可能＝pull可能
	const(ubyte)[] pull(S)(size_t len, ubyte[] buf=null)
	{
		return .pull(view, len, buf);
	}
	
  static if (isSink!R)
	bool push(S)(ref const(ubyte)[] buf)
	{
		return .push(view, buf);
	}
	
	void seek(long offset, SeekPos whence)
	{
		if (whence == SeekPos.Cur)
		{
			if (offset >= 0)
			{
				pos += min(view.length, offset);
				view = orig[pos .. $];
			}
			else
			{
				pos -= min(pos, -offset);
				view = orig[pos .. $];
			}
		}
		else if (whence == SeekPos.Set)
		{
			if (offset > 0)
			{
				pos = min(orig.length, offset);
				view = orig[pos .. $];
			}
			else
				view = orig.save;
		}
		else	// whence == SeekPos.End
		{
			if (offset < 0)
			{
				auto len = orig.length;
				pos = len - min(len, -offset);
				view = orig[pos .. $];
			}
			else
				view = orig[$ .. $];
		}
	}
}


/**
	バッファのアロケーションについては消極的
	
	File is Seekable Device
	pure Device (doesn't have Range I/F)
*/
struct File
{
	import std.utf;
	import std.typecons;
private:
	HANDLE hFile;
	size_t* pRefCounter;
	bool eof = false;

public:
	this(string fname)
	{
	//	writefln(typeof(this).stringof ~ " ctor");
		
		int share = FILE_SHARE_READ | FILE_SHARE_WRITE;
		int access = GENERIC_READ;
		int createMode = OPEN_EXISTING;
		hFile = CreateFileW(
			std.utf.toUTF16z(fname), access, share, null, createMode, 0, null);
		pRefCounter = new size_t();
		*pRefCounter = 1;
		debug(Move) writefln("ctor   this=%08s, hFile=%08s, cnt=%s",
			&this, cast(uint)hFile, pRefCounter ? *pRefCounter : 0);
	}
	this(this)
	{
		if (pRefCounter) ++(*pRefCounter);
		debug(Move) writefln("cpctor this=%08s, hFile=%08s, cnt=%s",
			&this, cast(uint)hFile, pRefCounter ? *pRefCounter : 0);
	}
	~this()
	{
		debug(Move) writefln("dtor   this=%08s, hFile=%08s, cnt=%s",
			&this, cast(uint)hFile, pRefCounter ? *pRefCounter : 0);
		if (pRefCounter)
		{
			if (--(*pRefCounter) == 0)
			{
				debug(Move) writefln("%s", typeof(this).stringof ~ " dtor");
				delete pRefCounter;
				CloseHandle(cast(HANDLE)hFile);
			}
			pRefCounter = null;
		}
	}

	@property bool empty() const
	{
		return eof;
	}
	
	const(ubyte)[] pull(size_t len, ubyte[] buf)
	{
		enum : uint { ERROR_HANDLE_EOF = 38 }	// todo

		// yet support only synchronous read
		
		if (buf.length > 0)
			len = min(buf.length, len);
		else
			buf.length = len;	// allocation
		
		DWORD size = void;
		debug writefln("ReadFile : buf.ptr=%08X, len=%s", cast(uint)buf.ptr, len);
		if (ReadFile(hFile, buf.ptr, len, &size, null))
		{
			buf = buf[0 .. size];
			//eof = (size == 0);
			eof = (size < len);		// valid on only synchronous read
			//writefln("File pull, len = %s, size = %s, GetLastError == %s, ERROR_HANDLE_EOF = %s", len, size, GetLastError(), ERROR_HANDLE_EOF);
		}
		else
		{
			debug writefln("hFile=%08X, size=%s, GetLastError()=%s", cast(uint)hFile, size, GetLastError());
			
			throw new Exception("pull error");	//?
			
		//	// for overlapped I/O
		//	eof = (GetLastError() == ERROR_HANDLE_EOF);
		}
		
		return buf;
	}
	
	bool push(ref const(ubyte)[] buf)
	{
		bool result;
		
		size_t len;
		if (WriteFile(hFile, buf.ptr, buf.length, &len, null))
			result = (len == buf.length);
		else
			throw new Exception("push error");	//?
		
		buf = buf[len .. $];
		return result;
	}
	
	void seek(long offset, SeekPos whence)
	{
	}
}
static assert(isSource!File);
//static assert(isDevice!File);


auto buffered(Source)(Source s, size_t bufferSize=2048)
{
	debug(Move) ScopePrint!"buffered" sp = 0;
	return Buffered!Source(move(s), bufferSize);
}

/**
?	BufferedはSourceで、かつInputRangeのI/Fを持つ
	
?	Bufferedは入力(Range/Source)をPartial Random Access Rangeにマップする

	バッファのアロケーションについては積極的
	
	
	RangeまたはSourceを取り、InputRangeとなる
	
	
	
	別名ByChunk
	
	x	BufferedはRangeとして扱ったほうが効率がよいため、Souce I/Fは提供しない
	o	Souce/InputRangeのどちらで扱ってもコストはほぼ同じはず
*/
struct Buffered(Source)
{
	Source source;
	ubyte[] buffer;
	ubyte[] view;	// Not yet popFront/pulled data view on buffer
	
	this(Source s, size_t bufferSize)
	{
		debug(Move) ScopePrint!"Buffered.this" sp = 0;
		move(s, source);
		buffer.length = bufferSize;
		fetch();
	}
	
	@property bool empty() const
	{
		//debug(Decoder) writefln("Buffered empty, view.length = %s, source.empty = %s", view.length, source.empty);
		return view.length==0 && source.empty;
		//return view.length==0;	// synchronous read only
	}
	
	/**
		バッファを空にすることを優先する
		fetchはバッファが空のときのみ行う
	*/
	const(ubyte)[] pull(size_t len, ubyte[] buf=null)
	{
		if (view.length == 0)
			fetch();
		
		len = min(len, view.length);
		if (buf.length > 0)
		{
			len = min(len, buf.length);
			buf[0 .. len] = view[0 .. len];
			view = view[len .. $];
			return buf[0 .. len];
		}
		else
		{
			buf = view[0 .. len];
			view = view[len .. $];
			return buf;
		}
	}
	
	
	@property ref ubyte front()
	{
		return view[0];
	}
	
	void popFront()
	{
		view = view[1 .. $];
		if (view.length == 0)
			fetch();
	}

private:
	void fetch()
	{
		auto v = source.pull(buffer.length, buffer);
		view = buffer[0 .. v.length];
		//debug(Decoder) writefln("Buffered fetch, source.empty = %s", source.empty);
	}
}


auto decoder(Char=char, Input)(Input input)
{
	debug(Move) ScopePrint!"decoder" sp = 0;
	return Decoder!(Input, Char)(move(input));
}

/**
	Source、またはubyteのRangeをChar型のバイト表現とみなし、
	これをdecodeしたdcharのRangeを構成する
*/
struct Decoder(Input, Char)
	if (isSource!Input ||
		(isInputRange!Input && is(ElementType!Input : const(ubyte))))
{

private:
	Input input;
	bool eof;
	dchar ch;

public:
	this(Input i)
	{
		debug(Move) ScopePrint!"Decoder.this" sp = 0;
		move(i, input);
		popFront();		// fetch front
	}
	
	@property bool empty() const
	{
		return eof;
	}
	
	@property dchar front()
	{
		return ch;
	}
	
	void popFront()
	in{
		assert(!eof);
	}
	body
	{
		if (input.empty)
			eof = true;
		else
		{
			// Change range status to empty when reading fails
			scope(failure) eof = true;
			
			void pullN(Char[] buf)
			{
			  static if (isSource!Input)
			  {
				.pullExact(	input,
							Char.sizeof * buf.length,
							(cast(ubyte*)buf.ptr)[0 .. Char.sizeof * buf.length]);
			  }
			  else
			  {
				auto bytebuf = (cast(char*)buf.ptr)[0 .. Char.sizeof * buf.length];
				foreach (i; 0 .. bytebuf.length)	// todo staticIota?
				{
					if (input.empty)
						throw new /*Read*/Exception("not enough data in stream");	// from std.stream.readExact
					
					bytebuf[i] = input.front;
					input.popFront();
				}
			  }
			}
			
			static if (is(Char == char))
			{
				char[6] buf;
				pullN(buf[0..1]);
				auto len = std.utf.stride(buf[0..1], 0);
				if (len == 0xFF)
			        throw new std.utf.UtfException("Not the start of the UTF-8 sequence");
				pullN(buf[1..len]);
				
				size_t i = 0;
				ch = std.utf.decode(buf, i);
			}
			static if (is(Char == wchar))
			{
				wchar[2] buf;
				pullN(buf[0..1]);
				if (buf[0] >= 0xD800 && buf[0] <= 0xDBFF)	// surrogate
					pullN(buf[1..2]);
				//writefln("Decode buf = %04X %04X", buf[0], buf[1]);
				
				size_t i = 0;
				ch = std.utf.decode(buf, i);
				//writefln("Decode ch = %08X, buf = %04X %04X", ch, buf[0], buf[1]);
			}
			static if (is(Char == dchar))
			{
			  	dchar[1] buf;
				pullN(buf[0..1]);
				
				size_t i = 0;
				ch = std.utf.decode(buf, i);
			}
		}
	}
}
unittest
{
	 string strc = "test UTFxx\r\nあいうえお漢字\r\n"c;
	wstring strw = "test UTFxx\r\nあいうえお漢字\r\n"w;
	dstring strd = "test UTFxx\r\nあいうえお漢字\r\n"d;
	
/+	void print(string msg, ubyte[] data)
	{
		writefln("%s", msg);
		foreach (n ; 0 .. data.length/16 + (data.length%16>0 ? 1:0))
		{
			writefln("%(%02X %)", data[16*n .. min(16*(n+1), data.length)]);
		}
	}
	print("UTF8",  cast(ubyte[])strc);
	print("UTF16", cast(ubyte[])strw);
	print("UTF32", cast(ubyte[])strd);+/
	
	void decode_test(Char, R)(R data, dstring expect)
	{
		assert(equal(decoder!Char(data), expect));
	}
	decode_test!( char)(cast(ubyte[])strc, strd);
	decode_test!(wchar)(cast(ubyte[])strw, strd);
	decode_test!(dchar)(cast(ubyte[])strd, strd);
}


version(Windows)
{
	enum NativeNewLine = "\r\n";
}
else
{
	static assert(0, "not yet supported");
}

/**
	Examples:
		lined!string(buffered(File("foo.txt")))
		lined!(const(char))("foo\nbar\nbaz", "\n")
*/
auto lined(String=string, R)(R r)
//	if (isSomeChar!(ElementType!R))
{
	debug(Move) ScopePrint!"lined1" sp = 0;
	debug(Move) writefln("&r = %08X", cast(uint)&r);
	//pragma(msg, "0: lined : String=", String, ", R=", R/*, ", Delim=", Delim*/);
	return Lined!(R, String, dstring)(move(r), cast(dstring)NativeNewLine);
}
/// ditto
auto lined(String=string, R, Delim)(R r, in Delim delim)
//	if (isSomeChar!(ElementType!R) && is(Unqual!(ElementType!R) == Unqual!(ElementType!Delim)))
{
	debug(Move) ScopePrint!"lined2" sp = 0;
	//pragma(msg, "1: lined : String=", String, ", R=", R, ", Delim=", Delim);
//static if (is(typeof(delim) : const(dchar)[]))
	return Lined!(R, String, Delim)(move(r), move(delim));
//else
//	return Lined!(R, String)(r, array(delim));
}

/**
	string Rangeを取り、String型の行Rangeを返す
	
	As Source
		Tがmutableなとき
		String == T[] || String == const(T)[]
			frontが返す配列の要素の値は次のpopFrontを呼ぶまで保障される
			必要ならdupやidupを呼ぶこと
		String == immutable(T)
			frontが返す配列の要素の値は不変
	
	As Sink
		lineへの書き込みが行える場合(String == T[])の挙動
		o	書き換えられるが、値の寿命は次のpopFrontまで
		x	書き換えによってオリジナルのSink(Fileなど)への書き込みが行われる
	
	別名ByLine
*/
struct Lined(Range, String : Char[], Delim, Char)
	if (is(typeof(
	{
		void dummy(ref Appender!(Unqual!Char[]) app, ref Range r)
		{
			app.put(r.front);
		}
	}())))	// →Rangeの要素をmutableな配列にコピーできるか
{
private:
	Range input;
	Delim delim;
	Unqual!(typeof(String.init[0]))[] lineBuffer;
	String line;

public:
	this(Range r, Delim d)
	{
		debug(Move) ScopePrint!"Lined.this" sp = 0;
		move(r, input);
		move(d, delim);
		debug(Move) writefln("Lined.this -> r.source = %08s, pRefCounter = %08s", &r.source, r.source.pRefCounter ? *r.source.pRefCounter : 0);
		popFront();
	}
	
	@property bool empty() const
	{
		return line.length==0 && input.empty;
	}
	
	@property String front() const
	{
		return line;
	}
	
	void popFront()
	{
	  static if (is(Range R : Buffered!U, U) && is(String == const(char)[]))
	  {
		pragma(msg, "Lined!(Buffered special case");
		
		auto app = appender(lineBuffer);
		app.clear();
		
		bool fetched = false;
		
		auto view = input.view;	// todo
		if (input.view.length == 0)
		{
			input.fetch(), view = input.view;	// todo
		}
		
		size_t vlen = 0;
		size_t dlen = 0;
		
		//writefln("Buffered.popFront : ");
	  Retry:
		for (vlen = 0; ; )
		{
			if (vlen == view.length)
			{
				app.put(view);
				input.fetch, view = input.view;
				fetched = true;
				//writefln("fetched");
				goto Retry;
			}
			
			auto e = view[vlen];
			++vlen;
			//writef("%02X ", e);
			if (e == delim[dlen])
			{
				++dlen;
				if (dlen == delim.length)
				{
					input.view = view[vlen .. $];
					
					if (fetched)
						app.put(view[0 .. vlen - dlen]);
					else
						vlen -= dlen;
					
					break;
				}
			}
			else
				dlen = 0;
		}
		
		if (fetched)
			line = app.data;
		else
			line = cast(const(char)[])view[0 .. vlen];
		
		//writefln("");
	  }
	  else
	  {
		auto app = appender(lineBuffer);
		app.clear();
		
		size_t dlen = 0;
	//	foreach (e; input)	inputがここでコピーされるので、inputそのものは進まない！
		while (!input.empty)
		{
			auto e = input.front;
			input.popFront();
		//	size_t i = 0;
		//	writefln("Lined.popFront, input.front(%s) = %0*X, stride = %s",
		//		typeof(e).stringof, typeof(e).sizeof*2, e, std.utf.stride((&e)[0 .. 1], i));
			app.put(e);
			if (e == delim[dlen])
			{
				++dlen;
				if (dlen == delim.length)
				{
					app.shrinkTo(app.data.length - delim.length);
					break;
				}
			}
			else
				dlen = 0;
		}
	  static if (is(typeof(String.init[0]) == immutable))
		line = app.data.idup;
	  else
		line = app.data;
		
		/*
		mutableな配列を返す場合は、その要素の寿命について
		1. ほかから共有されていない
		2. ほかから共有されており、書き換わる可能性がある
		の2種類がある。現実装は2.になっている(1.が必要な時は.dupが必要となる)
		*/
	  }
	}
	
  static if (isOutputRange!(Range, String))
	void put()
	{
	}
}
unittest
{
	void testParseLines(Str1, Str2)()
	{
		Str1 data = cast(Str1)"head\nmiddle\nend";
		Str2[] expects = ["head", "middle", "end"];
		
		auto indexer = sequence!"n"();
		foreach (e; zip(indexer, lined!Str2(data, "\n")))
		{
			auto ln = e[0], line = e[1];
			
			assert(line == expects[ln],
				std.string.format(
					"lined!%s(%s) failed : \n"
					"[%s]\tline   = %s\n\texpect = %s",
						Str2.stringof, Str1.stringof,
						ln, line, expects[ln]));
		}
	}
	
	testParseLines!( string,  string)();
	testParseLines!( string, wstring)();
	testParseLines!( string, dstring)();
	testParseLines!(wstring,  string)();
	testParseLines!(wstring, wstring)();
	testParseLines!(wstring, dstring)();
	testParseLines!(dstring,  string)();
	testParseLines!(dstring, wstring)();
	testParseLines!(dstring, dstring)();
}

unittest
{
	// decoderとlinedの組み合わせ
	
	 string		encoded_c = "test UTFxx\r\nあいうえお漢字\r\n"c;
	wstring		encoded_w = "test UTFxx\r\nあいうえお漢字\r\n"w;
	dstring		encoded_d = "test UTFxx\r\nあいうえお漢字\r\n"d;
	
	 string[]	expects_c = ["test UTFxx"c, "あいうえお漢字"c];
	wstring[]	expects_w = ["test UTFxx"w, "あいうえお漢字"w];
	dstring[]	expects_d = ["test UTFxx"d, "あいうえお漢字"d];
	
	void decode_encode(Str1, Str2, R)(R data, Str2[] expect)
	{
		//writefln("%s -> lined!%s", Str1.stringof, Str2.stringof);
		auto ln = 0;
		alias Unqual!(typeof(Str1.init[0])) Char1;
		foreach (line; lined!Str2(decoder!Char1(data)))
		{
			// worksaround for std.string.format doesn't support formatting array.
			string msg()
			{
				writefln("\n\t[%s] = \tline   = %(%02X %)\n\t\texpect = %(%02X %)",
					ln, cast(ubyte[])line, cast(ubyte[])expect[ln]);
				return std.string.format("%s -> lined!%s fails", Str1.stringof, Str2.stringof);
			}
			
			assert(expect[ln] == line, msg());
			++ln;
		}
		assert(ln == expect.length);
	}
	
	// ubyte[]をDecoderに食わせる
	decode_encode!( string,  string)(cast(ubyte[])encoded_c, expects_c);
	decode_encode!( string, wstring)(cast(ubyte[])encoded_c, expects_w);
	decode_encode!( string, dstring)(cast(ubyte[])encoded_c, expects_d);
	decode_encode!(wstring,  string)(cast(ubyte[])encoded_w, expects_c);
	decode_encode!(wstring, wstring)(cast(ubyte[])encoded_w, expects_w);
	decode_encode!(wstring, dstring)(cast(ubyte[])encoded_w, expects_d);
	decode_encode!(dstring,  string)(cast(ubyte[])encoded_d, expects_c);
	decode_encode!(dstring, wstring)(cast(ubyte[])encoded_d, expects_w);
	decode_encode!(dstring, dstring)(cast(ubyte[])encoded_d, expects_d);
	
	// Range of ubyteをDecoderに食わせる
	struct ByteRange
	{
		ubyte[] arr;
		@property bool empty() const	{ return arr.length == 0; }
		@property ubyte front()			{ return arr[0]; }
		void popFront()					{ arr = arr[1 .. $]; }
	}
	decode_encode!( string,  string)(ByteRange(cast(ubyte[])encoded_c), expects_c);
	decode_encode!( string, wstring)(ByteRange(cast(ubyte[])encoded_c), expects_w);
	decode_encode!( string, dstring)(ByteRange(cast(ubyte[])encoded_c), expects_d);
	decode_encode!(wstring,  string)(ByteRange(cast(ubyte[])encoded_w), expects_c);
	decode_encode!(wstring, wstring)(ByteRange(cast(ubyte[])encoded_w), expects_w);
	decode_encode!(wstring, dstring)(ByteRange(cast(ubyte[])encoded_w), expects_d);
	decode_encode!(dstring,  string)(ByteRange(cast(ubyte[])encoded_d), expects_c);
	decode_encode!(dstring, wstring)(ByteRange(cast(ubyte[])encoded_d), expects_w);
	decode_encode!(dstring, dstring)(ByteRange(cast(ubyte[])encoded_d), expects_d);

	// Source of ubyteをDecoderに食わせる
	struct ByteSource
	{
		ubyte[] arr;
		
		@property bool empty() const	{ return arr.length==0; }
		
		const(ubyte)[] pull(size_t len, ubyte[] buf)
		{
			if (buf.length > 0)
				len = min(len, buf.length);
			else
				buf.length = len;
			len = min(len, arr.length);
			buf[0 .. len] = arr[0 .. len];
			arr = arr[len .. $];
			return buf[0 .. len];
		}
	}
	decode_encode!( string,  string)(ByteSource(cast(ubyte[])encoded_c), expects_c);
	decode_encode!( string, wstring)(ByteSource(cast(ubyte[])encoded_c), expects_w);
	decode_encode!( string, dstring)(ByteSource(cast(ubyte[])encoded_c), expects_d);
	decode_encode!(wstring,  string)(ByteSource(cast(ubyte[])encoded_w), expects_c);
	decode_encode!(wstring, wstring)(ByteSource(cast(ubyte[])encoded_w), expects_w);
	decode_encode!(wstring, dstring)(ByteSource(cast(ubyte[])encoded_w), expects_d);
	decode_encode!(dstring,  string)(ByteSource(cast(ubyte[])encoded_d), expects_c);
	decode_encode!(dstring, wstring)(ByteSource(cast(ubyte[])encoded_d), expects_w);
	decode_encode!(dstring, dstring)(ByteSource(cast(ubyte[])encoded_d), expects_d);
}



debug(Move)
struct ScopePrint(string msg)
{
	this(int dummy)
	{
		writefln("Scope enter : %s", msg);
	}
	@disable this(this);
	~this()
	{
		writefln("Scope exit  : %s", msg);
	}
}

import std.exception : pointsTo;
void move(T, int line=__LINE__)(ref T source, ref T target)
{
	debug(Move) pragma(msg, "move instantiate : line=", line);
	debug(Move) writefln("move &source=%08X, &target=%08X", cast(uint)&source, cast(uint)&target);
	
    if (&source == &target) return;
    assert(!pointsTo(source, source));
    static if (is(T == struct))
    {
        // Most complicated case. Destroy whatever target had in it
        // and bitblast source over it
//      static if (is(typeof(target.__dtor()))) target.__dtor();
		static if (hasElaborateDestructor!(typeof(source))) typeid(T).destroy(&target);
        memcpy(&target, &source, T.sizeof);
        // If the source defines a destructor or a postblit hook, we must obliterate the
        // object in order to avoid double freeing and undue aliasing
//      static if (is(typeof(source.__dtor())) || is(typeof(source.__postblit())))
		static if (hasElaborateDestructor!(typeof(source)))
        {
			debug(Move) pragma(msg, "  hasElaborateDestructor!T");
            static T empty;
            debug(Move) writefln("%s source clear", T.stringof);
            memcpy(&source, &empty, T.sizeof);
        }
    }
    else
    {
        // Primitive data (including pointers and arrays) or class -
        // assignment works great
        target = source;
        // static if (is(typeof(source = null)))
        // {
        //     // Nullify the source to help the garbage collector
        //     source = null;
        // }
    }
}
/// Ditto
T move(T)(ref T src)
{
    T result;
    move(src, result);
    return result;
}
