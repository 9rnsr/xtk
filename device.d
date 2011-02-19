/**
*/
//module std.device;
module device;

import std.array, std.algorithm, std.range, std.traits;
import std.stdio;
version(Windows)
{
	import core.sys.windows.windows;
}

/*
	std.file.File.ByChunkの問題点：
		ubyte[]のレンジである
		説明：
			Fileは論理的にはubyteのストリームであるが、
			レンジを使用する側(bLineやalgorithmなど)はbyChunkを考慮するために
			ubyte[]のレンジを特別扱いしなくてはならない
		結論：
			バッファリングされたストリームは、バッファにアクセスするための
			IFを別途必要とする。Range I/Fではこれは満たせない。

	The problem of std.file.File.ByChunk is that ElementType!ByChunk is ubyte[].
	This means that ByChunk is range of ubyte[], but File is stream of ubyte.
	Then, wrapper ranges using ByChunk as original range (e.g. byLine) 
	should have special case. This is bad design.
	
	Filters buffering data from original source(e.g. File) should different
	interface with neither File or Range, I call it Pool.
	
	This module defines two interface to read, Source and Pool.
	- Source is pulled data specificated N length by user of source.
	- Pool is referenced already cached data by user of pool.
	Normally pools wrap a source or other pools, and provide range interface if it can.
	
	Decoder
		Conversion filter.
		When input is a pool of dchar, Decoder can become slicing filter.
	Lined
		if string type is const(char)[], lines that enumerated with range I/F will be
		slices of input pool as can as possilble.
		Slicing filter.
	
	Pool has an array of data it caches, and you can see it through its property $(D available).
	Users of pool can reduce the cost of copying by getting slices of it.
	
	On the other hand, Source does'nt have cached data in itself.
	Pools that take Source as input may ...
	
	
*/

/**
Returns $(D true) if $(D S) is a $(I source). A Source must define the
primitive $(D pull). The following code should compile for any source.
$(D S)が$(I Source)の場合に$(D true)を返す。$(BR)

----
Source s;                   // when s is source, it
ubyte[] buf;                // can read ubyte[] data into buffer
bool empty = s.pull(buf);   // can check source was already empty
----

Basic element of source is ubyte.

The operations of $(I Source):$(BR)
$(I Source)の操作:$(BR)
$(DDOC_MEMBERS
$(DDOC_DECL bool pull(ref ubyte[] buf))
$(DDOC_DECL_DD
	This operation read data from source into $(D buf).$(BR)
	この操作はsourceからデータを読み出し、$(D buf)に格納する。$(BR)
	
	If $(D buf.length) is 0, then you can check only source is valid.$(BR)
	$(D buf.length)が0の場合、sourceが読み出し可能状態であるかのみをチェックできる。$(BR)
	
	$(DDOC_SECTION_H InAssertion:$(BR)In契約:)
	$(DDOC_SECTION
	source is not yet $(D pull)ed, or previous $(D pull) operation returns $(D true).$(BR)
	sourceはまだ$(D pull)されたことがないか、あるいは前回の$(D pull)操作で$(D true)を返している。$(BR)
	)
	
	$(DDOC_SECTION_H Returns:$(BR)返値:)
	$(DDOC_SECTION
	If source was valid before reading, $(D buf) filled the read data(its length >= 0) and returns $(D true).$(BR)
	読み出し前にsourceが有効な状態だった場合、$(D buf)を読み出したデータで埋め、$(D true)を返す。$(BR)
	Otherwise returns $(D false).$(BR)
	そうでない場合、$(D false)を返す。$(BR)
	)
))
*/
template isSource(S)
{
	enum isSource =
		is(typeof({
			void dummy(ref S s)
			{
				ubyte[] buf;
				bool empty = s.pull(buf);
			}
		}()));
}

/**

In definition, initial state of pool has 0 length $(D available).$(BR)
定義では、poolの初期状態は長さ0の$(D available)を持つ。$(BR)
You can assume that pool is not $(D fetch)-ed yet.$(BR)
これはpoolがまだ一度も$(D fetch)されたことがないと見なすことができる。$(BR)

Basic element of sink is ubyte.

*/
template isInputPool(S)
{
	enum isInputPool =
		is(typeof({
			void dummy(ref S s)
			{
				if (s.fetch()){}
				auto buf = s.available;
				size_t n;
				s.consume(n);
			}
		}()));
}

template PoolElementType(S) if (isInputPool!S)
{
	alias typeof(S.init.available[0]) PoolElementType;
}

/+/*
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
}+/


/+
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
}+/


/**
	File is Seekable Device
*/
struct File
{
	import std.utf;
	import std.typecons;
private:
	HANDLE hFile;
	size_t* pRefCounter;

public:
	/**
	*/
	this(string fname)
	{
		int share = FILE_SHARE_READ | FILE_SHARE_WRITE;
		int access = GENERIC_READ;
		int createMode = OPEN_EXISTING;
		hFile = CreateFileW(
			std.utf.toUTF16z(fname), access, share, null, createMode, 0, null);
		pRefCounter = new size_t();
		*pRefCounter = 1;
	}
	this(this)
	{
		if (pRefCounter) ++(*pRefCounter);
	}
	~this()
	{
		if (pRefCounter)
		{
			if (--(*pRefCounter) == 0)
			{
				//delete pRefCounter;	// trivial: delegate management to GC.
				CloseHandle(cast(HANDLE)hFile);
			}
			//pRefCounter = null;		// trivial: do not need
		}
	}

	/**
	Request n number of elements.
	Returns:
		$(UL
			$(LI $(D true ) : You can request next pull.)
			$(LI $(D false) : No element exists.))
	*/
	bool pull(ref ubyte[] buf)
	{
		DWORD size = void;
		debug writefln("ReadFile : buf.ptr=%08X, len=%s", cast(uint)buf.ptr, len);
		if (ReadFile(hFile, buf.ptr, buf.length, &size, null))
		{
			debug(File)
				writefln("pull ok : hFile=%08X, buf.length=%s, size=%s, GetLastError()=%s",
					cast(uint)hFile, buf.length, size, GetLastError());
			buf = buf[0 .. size];
			return (size > 0);	// valid on only blocking read
		}
		else
		{
			debug(File)
				writefln("pull ng : hFile=%08X, size=%s, GetLastError()=%s",
					cast(uint)hFile, size, GetLastError());
			throw new Exception("pull(ref buf[]) error");
			
		//	// for overlapped I/O
		//	eof = (GetLastError() == ERROR_HANDLE_EOF);
		}
	}

	/**
	*/
	bool push(ref const(ubyte)[] buf)
	{
		DWORD size = void;
		if (WriteFile(hFile, buf.ptr, buf.length, &size, null))
		{
			buf = buf[size .. $];
			return true;	// (size == buf.length);
		}
		else
		{
			throw new Exception("push error");	//?
	}
	}
	
/+	void seek(long offset, SeekPos whence)
	{
	}+/
}
unittest
{
	static assert(isSource!File);
	//static assert(isDevice!File);
	assert(0);	// todo
}

/**
構築済みのInputをBufferedで包むための補助関数
*/
Buffered!Input buffered(Input)(Input i, size_t bufferSize = 2048)
{
	return Buffered!Input(move(i), bufferSize);
}

/**
InputとしてSource/配列/InputRangeを取り、ubyteのPool I/Fを提供する
*/
struct Buffered(Input) if (isSource!Input)
{
private:
	Input input;
	ubyte[] buffer;
	ubyte[] view;	// Not yet popFront/pulled data view on buffer

private:
	this(T)(T i, size_t bufferSize) if (is(T == Input))
	{
		move(i, input);
		buffer.length = bufferSize;
	}
public:
	/**
	Params:
	Inputにconstructionを委譲する
		args		= input constructor arguments
		bufferSize	= バッファリングされる要素数
	*/
	this(Args...)(Args args, size_t bufferSize)
	{
		move(Input(args), input);
		buffer.length = bufferSize;
	}

	/**
	Interfaces of pool.
	*/
	bool fetch()
	in { assert(available.length == 0); }
	body
	{
		view = buffer[0 .. $];
		return input.pull(view);
		//debug(Decoder) writefln("Buffered fetch, input.empty = %s", input.empty);
	}
	
	/// ditto
	@property const(ubyte)[] available() const
	{
		return view;
	}
	
	/// ditto
	void consume(size_t n)
	in { assert(n <= available.length); }
	body
	{
		view = view[n .. $];
	}
}
unittest
{
	static assert(isInputPool!(Buffered!File));
	assert(0);	// todo
}

/// ditto
struct Buffered(Input) if (isArray!Input)
{
private:
	alias Unqual!(ElementType!Input) E;
	Input input;
	size_t vewLen;

public:
	/*
	bufferSizeは無視される
	*/
	this(Input i, size_t bufferSize)
	{
		move(i, input);
	}

	/**
	Interfaces of pool.
	*/
	bool fetch()
	in { assert(available.length == 0); }
	body
	{
		if (input.empty)
			return false;
		return true;
	}
	
	/// ditto
	@property const(E)[] available() const
	{
		return input;
	}
	
	/// ditto
	void consume(size_t n)
	in { assert(n <= available.length); }
	body
	{
		input = input[1 .. $];
	}
}
unittest
{
	assert(0);	// todo
}

/// ditto
struct Buffered(Input) if (!isArray!Input && isInputRange!Input)
{
private:
	alias Unqual!(ElementType!Input) E;
	Input input;
	Unqual!E[] buffer;
	Unqual!E[] view;

public:
	/**
	*/
	this(Input i, size_t bufferSize)
	{
		move(i, input);
		buffer.length = bufferSize;
	}

	/**
	Interfaces of pool.
	*/
	bool fetch()
	in { assert(available.length == 0); }
	body
	{
		if (input.empty)
			return false;
		
		size_t i = 0;
		for (; input.empty && i<buffer.length; ++i)
		{
			buffer[i] = input.front;
			input.popFront();
		}
		view = buffer[0 .. i];
		return true;
	}
	
	/// ditto
	@property const(E)[] available() const
	{
		return view;
	}
	
	/// ditto
	void consume(size_t n)
	in { assert(n <= available.length); }
	body
	{
		view = view[1 .. $];
	}
}
unittest
{
	assert(0);	// todo
}

/**
構築済みのInputをRangedで包むための補助関数
*/
Ranged!Input ranged(Input)(Input input)
{
	return Ranged!Input(move(input));
}

/**
PoolをInputRangeに変換する
Design:
	Rangeはコンストラクト直後にemptyが取れる、つまりPoolでいうfetch済みである必要があるが、
	Poolは未fetchであることが必要なので互いの要件が矛盾する。よってPoolはInputRangeを
	同時に提供できないため、これをWrapするRangedが必要となる。
*/
struct Ranged(Input) if (isInputPool!Input)
{
private:
	Input input;
	bool eof;

private:
	this(T)(T i) if (is(T == Input))
	{
		move(i, input);
		eof = !input.fetch();
	}
public:
	/**
	Inputにconstructionを委譲する
	Params:
		args		= input constructor arguments
	*/
	this(Args...)(Args args)
	{
		move(Input(args), input);
		eof = !input.fetch();
	}

	/**
	Interfaces of input range.
	*/
	@property bool empty() const
	{
		return eof;
	}
	
	/// ditto
	@property ubyte front()
	{
		return input.available[0];
	}
/+	/// ditto
	@property void front(ubyte e)
	{
		input.available[0] = e;
	}+/
	
	/// ditto
	void popFront()
	{
		input.consume(1);
		if (input.available.length == 0)
			eof = !input.fetch();
	}
}

/**
Decoder構築用の補助関数
*/
auto decoder(Char=char, Input)(Input input, size_t bufferSize = 2048)
{
	return Decoder!(Input, Char)(move(input), bufferSize);
}

/**
	Source、またはubyteのRangeをChar型のバイト表現とみなし、
	これをdecodeしたdcharのRangeを構成する

	//----
	Poolを取ったときはPoolに
	Sourceを取ったときはコンストラクタで与えられたbufferSizeのPoolになる
	どちらも、Decoder自体はRange I/Fを持つ(予定)
Bugs:
	未完成
*/
struct Decoder(Input, Char)
	if (isSource!Input ||
		(isInputRange!Input && is(ElementType!Input : const(ubyte))))
{
	static assert(0);	// todo
private:
	Input input;
	bool eof;
  static if (isSource!Input)
	dchar[] buffer;
  static if (isInputPool!Input)
  {
	ElementType!Input[] remain;
	Appender!(dchar[]) buffer;
	dchar[] view;
  }
  else
  {
	dchar ch;
  }

public:
  static if (isSource!Input)
	this(Input i, size_t bufferSize = 2048)
	{
		buffer.length = 2048;
		
		move(i, input);
		popFront();		// fetch front
	}
  static if (isInputPool!Input)
	this(Input i)
	{
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
	
  static if (isInputPool!Input)
  {
	bool fetch()
	in { assert(available.length == 0); }
	body
	{
		buffer.clear();
		
		remain = input.available;
		if (remain.length)
			remain = remain.idup, input.consume(remain.length);
		
		if (!input.fetch())
			return false;	// remainがorphan byteとして残る
		
		if (!available.length)
			return true;	// NonBlocking I/O
		
		assert(remain.length >= 0);
		assert(input.available.length > 0);
		
		auto buf = chain(remain, input.available);
		size_t i = 0;
		foreach (e; buf)
		{
			try{
				c = decode(buf[i .. $], i);		// decode はslicableなRangeを取れない...
			}catch (UtfException e){
				break;
			}
			buffer.put(c);
		}
		if (i < remain.length)
			remain = remain[i .. $];
		else
			input.consume(i - remain.length);
			delete remain;
		
		view = buffer.data;
	}
	@property const(dchar)[] available()
	{
		return view;
	}
	void consume(size_t n)
	in { assert(n <= available.length); }
	body
	{
		view = view[n .. $];
	}
	
  }
	void popFront()
	{
		
		
		
		
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


//pragma(msg, "is( char : ubyte) = ", is( char : ubyte));
//pragma(msg, "is(wchar : ubyte) = ", is(wchar : ubyte));
//pragma(msg, "is(dchar : ubyte) = ", is(dchar : ubyte));

/**
	Examples:
		lined!string(buffered(File("foo.txt")))
		lined!(const(char))("foo\nbar\nbaz", "\n")
*/
auto lined(String=string, R)(R r)
{
	return Lined!(R, dstring, String)(move(r), cast(dstring)NativeNewLine);
}
/// ditto
auto lined(String=string, R, Delim)(R r, in Delim delim)
{
	return Lined!(R, Delim, String)(move(r), move(delim));
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
	
	
	//----
	より抽象的な表現
	InputからDelimを区切りとして、Inputの要素配列を切り出す
*/
struct Lined(Input, Delim, String : Char[], Char)
/+	if (is(typeof(
	{
		void dummy(ref Appender!(Unqual!Char[]) app, ref Input r)
		{
			app.put(r.front);
		}
	}())))	// →Inputの要素をmutableな配列にコピーできるか
+/
	if (isSomeChar!Char)
{
	static assert(isInputPool!Input && is(PoolElementType!Input : const(ubyte)) && is(Char : const(char)));

private:
	Input input;
	Delim delim;
//	Appender!(Unqual!Char[]) buffer;	// trivial: reduce initializing const of appender
	Appender!(Unqual!ubyte[]) buffer;	// trivial: reduce initializing const of appender
	String line;
	bool eof;

public:
	/**
	*/
	this(Input r, Delim d)
	{
		move(r, input);
		move(d, delim);
		popFront();
	}

	/**
	Interfaces of input range.
	*/
	@property bool empty() const
	{
		return eof;
	}
	
	/// ditto
	@property String front() const
	{
		return line;
	}
	
	/// ditto
	void popFront()
	in { assert(!empty); }
	body
	{
		const(ubyte)[] view;
		
		bool fetchExact()	// fillAvailable?
		{
			view = input.available;
			while (view.length == 0)
			{
				//writefln("fetched");
				if (!input.fetch())
					return false;
				view = input.available;
			}
			return true;
		}
		if (!fetchExact())
			return eof = true;
		
		buffer.clear();
		
		//writefln("Buffered.popFront : ");
		for (size_t vlen=0, dlen=0; ; )
		{
			if (vlen == view.length)
			{
				line = cast(String)(buffer.put(view), buffer.data);
				input.consume(vlen);
				if (!fetchExact())
					break;
				
				vlen = 0;
				continue;
			}
			
			auto e = view[vlen];
			++vlen;
			//writef("%02X ", e);
			if (e == delim[dlen])
			{
				++dlen;
				if (dlen == delim.length)
				{
					if (buffer.data.length)
					{
						//writefln("%s@%s : %s %s %s %s", __FILE__, __LINE__, view, view.length, vlen, dlen);
						line = cast(String)(buffer.put(view[0 .. vlen]), buffer.data[0 .. $ - dlen]);
					}
					else
						line = cast(String)view[0 .. vlen - dlen];
					
					input.consume(vlen);
					break;
				}
			}
			else
				dlen = 0;
		}
		
	  static if (is(Char == immutable))
		line = line.idup;
	}


/+
  static if (isOutputRange!(Input, String))
	void put()
	{
	}+/
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


import std.exception : pointsTo;
void move(T, int line=__LINE__)(ref T source, ref T target)
{
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
            static T empty;
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
T move(T)(ref T src)
{
    T result;
    move(src, result);
    return result;
}




template CharType(T) if (isSomeString!T)
{
	alias ForeachType!T CharType;
}
