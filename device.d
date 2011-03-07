﻿/*
Source,Pool,Sinkの3つを基本I/Fと置く
→Buffered-sinkは明示的に扱えるようにする？

それぞれがやり取りする要素の型は任意だが、Fileはubyteをやり取りする
(D言語的にはvoid[]でもいいかも→Rangeを考えるとやりたくない)

基本的なFilter
・Encodedはubyteを任意型にcastする機能を提供する
・Bufferedはバッファリングを行う

filter chainのサポート
Bufferedの例:
	(1) 構築済みのdeviceをwrapする
		auto f = File("test.txt", "r");
		auto sf = sinked(f);
		auto bf = bufferd(sf, 2048);
	(2) 静的に決定したfilterを構築する
		alias Buffered!Sinked BufferedSink;
		auto bf = BufferedSink!File("test.txt", "r", 2048)

*/
module xtk.device;

import std.array, std.algorithm, std.range, std.traits;
import std.stdio;
version(Windows) import xtk.windows;

import xtk.workaround;

debug = Workarounds;
debug (Workarounds)
{
	debug = Issue5661;	// replace of std.algorithm.move
	debug = Issue5663;	// replace of std.array.Appender.put
	
	debug (Issue5661)	alias issue5661fix_move move;
	debug (Issue5663)	alias issue5663fix_Appender Appender;
}

import xtk.meta : isTemplate;

/**
Returns $(D true) if $(D_PARAM S) is a $(I source). A Source must define the
primitive $(D pull). 
*/
template isSource(S)
{
	enum isSource = __traits(hasMember, S, "pull");
}

///ditto
template isSource(S, E)
{
	enum isSource = is(typeof({
		S s;
		E[] buf;
		while(s.pull(buf))
		{
			// ...
		} 
	}()));
}

/**
In definition, initial state of pool has 0 length $(D available).$(BR)
You can assume that pool is not $(D fetch)-ed yet.$(BR)
定義では、poolの初期状態は長さ0の$(D available)を持つ。$(BR)
これはpoolがまだ一度も$(D fetch)されたことがないと見なすことができる。$(BR)
*/
template isPool(S)
{
	enum isPool = is(typeof({
		S s;
		while (s.fetch())
		{
			auto buf = s.available;
			size_t n;
			s.consume(n);
		}
	}()));
}

/**
Returns $(D true) if $(D_PARAM S) is a $(I sink). A Source must define the
primitive $(D push). 
*/
template isSink(S)
{
//	__traits(allMembers, T)にはstatic ifで切られたものも含まれている…
//	enum isSink = hasMember!(S, "push");
	enum isSink = __traits(hasMember, S, "push");
}

///ditto
template isSink(S, E)
{
	enum isSink = is(typeof({
		S s;
		const(E)[] buf;
		do
		{
			// ...
		}while (s.push(buf))
	}()));
}

/**
Device supports both primitives of source and sink.
*/
template isDevice(S)
{
	enum isDevice = isSource!S && isSink!S;
}

/**
Retruns element type of device.
Naming:
	More good naming.
*/
template UnitType(S)
	if (isSource!S || isPool!S || isSink!S)
{
	static if (isSource!S)
		alias Unqual!(typeof(ParameterTypeTuple!(typeof(S.init.pull))[0].init[0])) UnitType;
	static if (isPool!S)
		alias Unqual!(typeof(S.init.available[0])) UnitType;
	static if (isSink!S)
	{
		alias Unqual!(typeof(ParameterTypeTuple!(typeof(S.init.push))[0].init[0])) UnitType;
	}
}

// seek whence...
enum SeekPos {
	Set,
	Cur,
	End
}

/**
Check that $(D_PARAM S) is seekable source or sink.
Seekable device supports $(D seek) primitive.
*/
template isSeekable(S)
{
	enum isSeekable = is(typeof({
		S s;
		s.seek(0, SeekPos.Set);
	}()));
}


/**
File is seekable device
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
	this(HANDLE h)
	{
		hFile = h;
		pRefCounter = new size_t();
		*pRefCounter = 1;
	}
	this(string fname, in char[] mode = "r")
	{
		int share = FILE_SHARE_READ | FILE_SHARE_WRITE;
		int access = void;
		int createMode = void;
		
		// fopenにはOPEN_ALWAYSに相当するModeはない？
		switch (mode)
		{
			case "r":
				access = GENERIC_READ;
				createMode = OPEN_EXISTING;
				break;
			case "w":
				access = GENERIC_WRITE;
				createMode = CREATE_ALWAYS;
				break;
			case "a":
				assert(0);
			
			case "r+":
				access = GENERIC_READ | GENERIC_WRITE;
				createMode = OPEN_EXISTING;
				break;
			case "w+":
				access = GENERIC_READ | GENERIC_WRITE;
				createMode = CREATE_ALWAYS;
				break;
			case "a+":
				assert(0);
			
			// do not have binary mode(binary access only)
		//	case "rb":
		//	case "wb":
		//	case "ab":
		//	case "rb+":	case "r+b":
		//	case "wb+":	case "w+b":
		//	case "ab+":	case "a+b":
		}
		
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
			switch (GetLastError())
			{
			case ERROR_BROKEN_PIPE:
				return false;
			default:
				break;
			}
			
			//debug(File)
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
	
	/**
	*/
	ulong seek(long offset, SeekPos whence)
	{
	  version(Windows)
	  {
		int hi = cast(int)(offset>>32);
		uint low = SetFilePointer(hFile, cast(int)offset, &hi, whence);
		if ((low == INVALID_SET_FILE_POINTER) && (GetLastError() != 0))
			throw new /*Seek*/Exception("unable to move file pointer");
		ulong result = (cast(ulong)hi << 32) + low;
	  }
	  else
	  version (Posix)
	  {
		auto result = lseek(hFile, cast(int)offset, whence);
		if (result == cast(typeof(result))-1)
			throw new /*Seek*/Exception("unable to move file pointer");
	  }
		return cast(ulong)result;
	}
}
static assert(isSource!File);
static assert(isSink!File);
static assert(isDevice!File);


/**
Modifiers to limit primitives of $(D_PARAM Device) to source.
*/
Sourced!Device sourced(Device)(Device d)
{
	return Sourced!Device(d);
}

/// ditto
template Sourced(alias Device) if (isTemplate!Device)
{
	template Sourced(T...)
	{
		alias .Sourced!(Device!T) Sourced;
	}
}

/// ditto
template Sourced(Device)
{
  static if (isDevice!Device)
  {
	struct Sourced
	{
	private:
		alias UnitType!Device E;
		Device device;
	
	public:
		/**
		*/
		this(D)(D d) if (is(D == Device))
		{
			move(d, device);
		}
		/**
		Delegate construction to $(D_PARAM Device).
		*/
		this(A...)(A args)
		{
			__ctor(Device(args));
		}
	
		/**
		*/
		bool pull(ref E[] buf)
		{
			return device.pull(buf);
		}
	}
  }
  else static if (isSource!Device)
	alias Device Sourced;
  else
	static assert(0, "Cannot limit "~Device.stringof~" as source");
}


/**
Modifiers to limit primitives of $(D_PARAM Device) to sink.
*/
Sinked!Device sinked(Device)(Device d)
{
	return Sinked!Device(d);
}

/// ditto
template Sinked(alias Device) if (isTemplate!Device)
{
	template Sinked(T...)
	{
		alias .Sinked!(Device!T) Sinked;
	}
}

/// ditto
template Sinked(Device)
{
  static if (isDevice!Device)
  {
	struct Sinked
	{
	private:
		alias UnitType!Device E;
		Device device;
	
	public:
		/**
		*/
		this(D)(D d) if (is(D == Device))
		{
			move(d, device);
		}
		/**
		Delegate construction to $(D_PARAM Device).
		*/
		this(A...)(A args)
		{
			__ctor(Device(args));
		}
	
		/**
		*/
		bool push(ref const(E)[] buf)
		{
			return device.push(buf);
		}
	}
  }
  else static if (isSink!Device)
	alias Device Sinked;
  else
	static assert(0, "Cannot limit "~Device.stringof~" as sink");
}


/**
*/
Encoded!(Device, E) encoded(E, Device)(Device device)
{
	return typeof(return)(move(device));
}

/// ditto
template Encoded(alias Device) if (isTemplate!Device)
{
	template Encoded(T...)
	{
		alias .Encoded!(Device!T) Encoded;
	}
}

/// ditto
struct Encoded(Device, E)
{
private:
	Device device;

public:
	/**
	*/
	this(D)(D d) if (is(D == Device))
	{
		move(d, device);
	}
	/**
	*/
	this(A...)(A args)
	{
		__ctor(Device(args));
	}

  static if (isSource!Device)
	/**
	*/
	bool pull(ref E[] buf)
	{
		auto v = cast(ubyte[])buf;
		auto result = device.pull(v);
		if (result)
		{
			static if (E.sizeof > 1) assert(v.length % E.sizeof == 0);
			buf = cast(E[])v;
		}
		return result;
	}

  static if (isPool!Device)
  {
	/**
	primitives of pool.
	*/
	bool fetch()
	{
		return device.fetch();
	}
	
	/// ditto
	@property const(E)[] available() const
	{
		return cast(const(E)[])device.available;
	}
	
	/// ditto
	void consume(size_t n)
	{
		device.consume(E.sizeof * n);
	}
  }

  static if (isSink!Device)
	/**
	primitive of sink.
	*/
	bool push(ref const(E)[] data)
	{
		auto v = cast(const(ubyte)[])data;
		auto result = device.push(v);
		static if (E.sizeof > 1) assert(v.length % E.sizeof == 0);
		data = data[$ - v.length / E.sizeof .. $];
		return result;
	}

  static if (isSeekable!Device)
	/**
	*/
	ulong seek(long offset, SeekPos whence)
	{
		return device.seek(offset, whence);
	}
}


/**
*/
Buffered!(Device) buffered(Device)(Device device, size_t bufferSize = 4096)
{
	return typeof(return)(move(device), bufferSize);
}

/// ditto
template Buffered(alias Device) if (isTemplate!Device)
{
	template Buffered(T...)
	{
		alias .Buffered!(Device!T) Buffered;
	}
}

/// ditto
struct Buffered(Device)
	if (isSource!Device || isSink!Device)
{
private:
	alias UnitType!Device E;
	Device device;
	E[] buffer;
	static if (isSink  !Device) size_t rsv_start = 0, rsv_end = 0;
	static if (isSource!Device) size_t ava_start = 0, ava_end = 0;
	static if (isDevice!Device) long base_pos = 0;

public:
	/**
	*/
	this(D)(D d, size_t bufferSize) if (is(D == Device))
	{
		move(d, device);
		buffer.length = bufferSize;
	}
	/**
	*/
	this(A...)(A args, size_t bufferSize)
	{
		__ctor(Device(args), bufferSize);
	}
	
  static if (isSink!Device)
	~this()
	{
		while (reserves.length > 0)
			flush();
	}

  static if (isSource!Device)
	/**
	primitives of pool.
	*/
	bool fetch()
	body
	{
	  static if (isDevice!Device)
		bool empty_reserves = (reserves.length == 0);
	  else
		enum empty_reserves = true;
		
		if (empty_reserves && available.length == 0)
		{
			static if (isDevice!Device)	base_pos += ava_end;
			static if (isDevice!Device)	rsv_start = rsv_end = 0;
										ava_start = ava_end = 0;
		}
		
	  static if (isDevice!Device)
		device.seek(base_pos + ava_end, SeekPos.Set);
		
		auto v = buffer[ava_end .. $];
		auto result =  device.pull(v);
		if (result)
		{
			ava_end += v.length;
		}
		return result;
	}
	
  static if (isSource!Device)
	/// ditto
	@property const(E)[] available() const
	{
		return buffer[ava_start .. ava_end];
	}
	
  static if (isSource!Device)
	/// ditto
	void consume(size_t n)
	in { assert(n <= available.length); }
	body
	{
		ava_start += n;
	}

  static if (isSink!Device)
  {
	/*
	primitives of output pool?
	*/
	private @property E[] usable()
	{
	  static if (isDevice!Device)
		return buffer[ava_start .. $];
	  else
		return buffer[rsv_end .. $];
	}
	private @property const(E)[] reserves()
	{
		return buffer[rsv_start .. rsv_end];
	}
	// ditto
	private void commit(size_t n)
	{
	  static if (isDevice!Device)
	  {
		assert(ava_start + n <= buffer.length);
		ava_start += n;
		ava_end = max(ava_end, ava_start);
		rsv_end = ava_start;
	  }
	  else
	  {
		assert(rsv_end + n <= buffer.length);
		rsv_end += n;
	  }
	}
  }
	
  static if (isSink!Device)
	/**
	flush buffer.
	primitives of output pool?
	*/
	bool flush()
	in { assert(reserves.length > 0); }
	body
	{
	  static if (isDevice!Device)
		device.seek(base_pos + rsv_start, SeekPos.Set);
		
		auto rsv = buffer[rsv_start .. rsv_end];
		auto result = device.push(rsv);
		if (result)
		{
			rsv_start = rsv_end - rsv.length;
			
		  static if (isDevice!Device)
			bool empty_available = (available.length == 0);
		  else
			enum empty_available = true;
			
			if (reserves.length == 0 && empty_available)
			{
				static if (isDevice!Device)	base_pos += ava_end;
				static if (isDevice!Device)	ava_start = ava_end = 0;
											rsv_start = rsv_end = 0;
			}
		}
		return result;
	}

  static if (isSink!Device)
	/**
	primitive of sink.
	*/
	bool push(const(E)[] data)
	{
	//	return device.push(data);
		
		while (data.length > 0)
		{
			if (usable.length == 0)
				if (!flush()) goto Exit;
			auto len = min(data.length, usable.length);
			usable[0 .. len] = data[0 .. len];
			data = data[len .. $];
			commit(len);
		}
		if (usable.length == 0)
			if (!flush()) goto Exit;
		
		return true;
	  Exit:
		return false;
	}
}


/*shared */static this()
{
	din  = Sourced!File(GetStdHandle(STD_INPUT_HANDLE));
	dout = Sinked !File(GetStdHandle(STD_OUTPUT_HANDLE));
	derr = Sinked !File(GetStdHandle(STD_ERROR_HANDLE));
}
//__gshared
//{
	Sourced!File din;
	Sinked !File dout;
	Sinked !File derr;
//}


/**
Convert pool to input range.
Convert sink to output range.
Design:
	Rangeはコンストラクト直後にemptyが取れる、つまりPoolでいうfetch済みである必要があるが、
	Poolは未fetchであることが必要なので互いの要件が矛盾する。よってPoolはInputRangeを
	同時に提供できないため、これをWrapするRangedが必要となる。
Design:
	OutputRangeはデータがすべて書き込まれるまでSinkのpushを繰り返す。
*/
Ranged!Device ranged(Device)(Device device)
{
	return Ranged!Device(move(device));
}

/// ditto
template Ranged(alias Device) if (isTemplate!Device)
{
	template Ranged(T...)
	{
		alias .Ranged!(Device!T) Ranged;
	}
}

/// ditto
struct Ranged(Device) if (isPool!Device || isSink!Device)
{
private:
	alias UnitType!Device E;
	Device device;
	bool eof;

public:
	/**
	*/
	this(D)(D d) if (is(D == Device))
	{
		move(d, device);
	  static if (isPool!Device)
		eof = !device.fetch();
	}
	/**
	*/
	this(A...)(A args)
	{
		__ctor(Device(args));
	}

  static if (isPool!Device)
  {
	/**
	primitives of input range.
	*/
	@property bool empty() const
	{
		return eof;
	}
	
	/// ditto
	@property E front()
	{
		return device.available[0];
	}
	
	/// ditto
	void popFront()
	{
		device.consume(1);
		if (device.available.length == 0)
			eof = !device.fetch();
	}
  }

  static if (isSink!Device)
	/**
	primitive of output range.
	*/
	void put(const(E)[] data)
	{
		while (data.length > 0)
		{
			if (!device.push(data))
				throw new Exception("");
		}
	}
}
unittest
{
	auto fname = "dummy.txt";
	{	auto r = ranged(Sinked!File(fname, "w"));
		ubyte[] data = [1,2,3];
		r.put(data);
	}
	{	auto r = ranged(buffered(Sourced!File(fname, "r"), 1024));
		auto i = 1;
		foreach (e; r)
		{
			static assert(is(typeof(e) == ubyte));
			assert(e == i++);
		}
	}
	std.file.remove(fname);
}


version(Windows)
{
	enum NativeNewLine = "\r\n";
}
else version(Posix)
{
	enum NativeNewLine = "\n";
}
else
{
	static assert(0, "not yet supported");
}


/**
Lined receives pool of char, and makes input range of lines separated $(D delim).
Naming:
	LineReader?
	LineStream?
Examples:
	lined!string(File("foo.txt"))
*/
auto lined(String=string, Source)(Source source, size_t bufferSize=2048)
	if (isSource!Source)
{
	alias Unqual!(typeof(String.init[0]))	Char;
	alias Encoded!(Source, Char)			Enc;
	alias Buffered!(Enc)					Buf;
	alias Lined!(Buf, String, String)		LinedType;
	return LinedType(Buf(Enc(move(source)), bufferSize), cast(String)NativeNewLine);
/+
	// Revsersing order of filters also works.
	alias Unqual!(typeof(String.init[0]))   Char;
	alias Buffered!(Source)				Buf;
	alias Encoded!(Buf, Char)          Enc;
	alias Lined!(Enc, String, String) LinedType;
	return LinedType(Enc(Buf(move(source), bufferSize)), cast(String)NativeNewLine);
+/
}
/// ditto
auto lined(String=string, Source, Delim)(Source source, in Delim delim, size_t bufferSize=2048)
	if (isSource!Source && isInputRange!Delim)
{
	alias Unqual!(typeof(String.init[0]))	Char;
	alias Encoded!(Source, Char)			Enc;
	alias Buffered!(Enc)					Buf;
	alias Lined!(Buf, Delim, String)		LinedType;
	return LinedType(Buf(Enc(move(source)), bufferSize), move(delim));
}

/// ditto
struct Lined(Pool, Delim, String : Char[], Char)
	if (isPool!Pool && isSomeChar!Char)
{
	//static assert(is(UnitType!Pool == Unqual!Char));	// compile-time evaluation bug？
	alias UnitType!Pool E;
	static assert(is(E == Unqual!Char));

private:
	alias Unqual!Char MutableChar;

	Pool pool;
	Delim delim;
	Appender!(MutableChar[]) buffer;
	String line;
	bool eof;

public:
	/**
	*/
	this(Pool p, Delim d)
	{
		move(p, pool);
		move(d, delim);
		popFront();
	}

	/**
	primitives of input range.
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
		const(MutableChar)[] view;
		const(MutableChar)[] nextline;
		
		bool fetchExact()	// fillAvailable?
		{
			view = pool.available;
			while (view.length == 0)
			{
				//writefln("fetched");
				if (!pool.fetch())
					return false;
				view = pool.available;
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
				buffer.put(view);
				nextline = buffer.data;
				pool.consume(vlen);
				if (!fetchExact())
					break;
				
				vlen = 0;
				continue;
			}
			
			auto e = view[vlen];
			++vlen;
			if (e == delim[dlen])
			{
				++dlen;
				if (dlen == delim.length)
				{
					if (buffer.data.length)
					{
						buffer.put(view[0 .. vlen]);
						nextline = (buffer.data[0 .. $ - dlen]);
					}
					else
						nextline = view[0 .. vlen - dlen];
					
					pool.consume(vlen);
					break;
				}
			}
			else
				dlen = 0;
		}
		
	  static if (is(Char == immutable))
		line = nextline.idup;
	  else
		line = nextline;
	}
}
/+unittest
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
				format(
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
}+/


alias Base64Impl!() Base64;

/**
fetch方法について改良案
ChunkRange提供
//Pool I/F提供版←必要なら置き換え可能
*/
//debug = B64Enc;
//debug = B64Dec;
template Base64Impl(char Map62th = '+', char Map63th = '/', char Padding = '=')
{
	static import std.base64;
	alias std.base64.Base64Impl!(Map62th, Map63th, Padding) StdBase64;
	
	void debugout(A...)(A args) { stderr.writefln(args); }

	/**
	*/
	Encoder!Device encoder(Device)(Device device, size_t bufferSize = 2048)
	{
		return Encoder!Device(move(device), bufferSize);
	}

	/**
	*/
	struct Encoder(Device) if (isPool!Device && is(UnitType!Device == ubyte))
	{
	private:
		Device device;
		char[] buf, view;
		ubyte[3] cache; size_t cachelen;
		bool eof;
	//	bool isempty;

	public:
		/**
		Ignore bufferSize (It's determined by pool size below)
		*/
		this(D)(D d, size_t bufferSize) if (is(D == Device))
		{
			move(d, device);
	//		isempty = !fetch();
		}
		/**
		*/
		this(A...)(A args, size_t bufferSize)
		{
			__ctor(Device(args), bufferSize);
		}
	
	/+
		/**
		primitives of input range.
		*/
		@property bool empty()
		{
			return isempty;
		}
		/// ditto
		@property const(char)[] front()
		{
			return view;
		}
		/// ditto
		void popFront()
		{
		//	view = view[1 .. $];
		//	// -inline -release前提で、こっちのほうが分岐予測ミスが少ない？
		//	if (view.length == 0)
			view = view[0 .. 0];
				isempty = !fetch();
		}	// +/
	
	//+
		@property const(char)[] available() const
		{
			return view;
		}
		void consume(size_t n)
		in{ assert(n <= view.length); }
		body
		{
			view = view[n .. $];
		}	// +/
		
		bool fetch()
		in { assert(view.length == 0); }
		body
		{
			if (eof) return false;
			
			debug (B64Enc) debugout("");
			
			// device.fetchの繰り返しによってdevice.availableが最低2バイト以上たまることを要求する
			// Needed that minimum size of the device pool should be more than 2 bytes.
			if (cachelen)	// eating cache
			{
				assert(buf.length >= 4);
				
				debug (B64Enc) debugout("usecache 0: cache = [%(%02X %)]", cache[0..cachelen]);
			  Continue:
				if (device.fetch())
				{
					auto ava = device.available;
					debug (B64Enc) debugout("usecache 1: ava.length = %s", ava.length);
					if (cachelen + ava.length >= 3)
					{
						final switch (cachelen)
						{
						case 1:	cache[1] = ava[0];
								cache[2] = ava[1];	break;
						case 2:	cache[2] = ava[0];	break;
						}
						StdBase64.encode(cache[], buf[0..4]);
						device.consume(3 - cachelen);
					}
					else
						goto Continue;
				}
				else
				{
					assert(device.available.length == 0);
					debug (B64Enc) debugout("usecache 2: cachelen = %s", cachelen);
					view = StdBase64.encode(cache[0..cachelen], view = buf[0..4]);
					return (eof = true, eof);
				}
			}
			else if (!device.fetch())
			{
				eof = true;
				return false;
			}
		
			auto ava = device.available;
			immutable capnum = ava.length / 3;
			immutable caplen = capnum * 3;
			immutable buflen = capnum * 4;
			debug (B64Enc) debugout(
					"capture1: ava.length = %s, capnum = %s, caplen = %s, buflen = %s+%s",
					ava.length, capnum, caplen, buflen, cachelen ? 4 : 0);
			if (caplen)
			{
				// cachelen!=0 -> has encoded from cache
				auto bs = cachelen ? 4 : 0, be = bs+buflen;
				if (buf.length < be)
					buf.length = be;
				view = buf[bs + StdBase64.encode(ava[0..caplen], buf[bs..be]).length];
			}
			if ((cachelen = ava.length - caplen) != 0)
			{
				final switch (cachelen)
				{
				case 1:	cache[0] = ava[$-1];	break;
				case 2:	cache[0] = ava[$-2];
						cache[1] = ava[$-1];	break;
				}
				// It will be needed that buf.length >= 4 on next fetch.
				if (buf.length < 4) buf.length = 4;
			}
			device.consume(ava.length);
			debug (B64Enc)
				debugout(
					"capture2: view.length = %s, cachelen = %s, ava.length = %s",
					view.length, cachelen, ava.length);
			return true;
		}
	}

	/**
	*/
	auto decoder(Device)(Device device, size_t bufferSize = 2048)
	{
		alias UnitType!Device U;	// workaround for type evaluation bug
		return Decoder!Device(move(device), bufferSize);
	}

	/**
	*/
	struct Decoder(Device) if (isPool!Device && is(UnitType!Device == char))
	{
	private:
		Device device;
		ubyte[] buf, view;
		char[4] cache; size_t cachelen;
		bool eof;
	//	bool isempty;

	public:
		/**
		Ignore bufferSize (It's determined by pool size below)
		*/
		this(D)(D d, size_t bufferSize) if (is(D == Device))
		{
			move(d, device);
	//		isempty = !fetch();
		}
		/**
		*/
		this(A...)(A args, size_t bufferSize)
		{
			__ctor(Device(args), bufferSize);
		}
	
	/+
		/**
		primitives of input range.
		*/
		@property bool empty() const
		{
			return isempty;
		}
		/// ditto
		@property const(ubyte)[] front()
		{
			return view;
		}
		/// ditto
		void popFront()
		{
		//	view = view[1 .. $];
		//	// -inline -release前提で、こっちのほうが分岐予測ミスが少ない？
		//	if (view.length == 0)
			view = view[0 .. 0];
				isempty = !fetch();
		}	// +/
	
	//+
		@property const(ubyte)[] available() const
		{
			return view;
		}
		void consume(size_t n)
		in{ assert(n <= view.length); }
		body
		{
			view = view[n .. $];
		}	// +/
		
		bool fetch()
		{
			if (eof) return false;
			
			// Needed that minimum size of the device pool should be more than 3 bytes.
			if (cachelen)	// eating cache
			{
				assert(buf.length >= 3);
				
				debug (B64Dec) debugout("usecache 0: cache = [%(%02X %)]", cache[0..cachelen]);
			  Continue:
				if (device.fetch())
				{
					auto ava = device.available;
					debug (B64Dec) debugout("usecache 1: ava.length = %s", ava.length);
					if (cachelen + ava.length >= 4)
					{
						final switch (cachelen)
						{
						case 1:	cache[1] = ava[0];
								cache[2] = ava[1];
								cache[3] = ava[2];	break;
						case 2:	cache[2] = ava[0];
								cache[3] = ava[1];	break;
						case 3:	cache[3] = ava[0];	break;
						}
						StdBase64.decode(cache[], buf[0..3]);
						device.consume(4 - cachelen);
					}
					else
						goto Continue;
				}
				else
				{
					assert(device.available.length == 0);
					debug (B64Dec) debugout("usecache 2: cachelen = %s", cachelen);
					view = StdBase64.decode(cache[0..cachelen], buf[0..3]);
					return (eof = true, eof);
				}
			}
			else if (!device.fetch())
			{
				eof = true;
				return false;
			}
		
			auto ava = device.available;
			immutable capnum = ava.length / 4;
			immutable caplen = capnum * 4;
			immutable buflen = capnum * 3;
			debug (B64Dec) debugout(
					"capture1: ava.length = %s, capnum = %s, caplen = %s, buflen = %s, (cache = %s)",
					ava.length, capnum, caplen, buflen, cachelen ? 4 : 0);
			if (caplen)
			{
				// cachelen!=0 -> has encoded from cache
				auto bs = cachelen ? 3 : 0, be = bs+buflen;
				if (buf.length < be)
					buf.length = be;
				view = buf[0 .. bs + StdBase64.decode(ava[0..caplen], buf[bs..be]).length];
			}
			if ((cachelen = ava.length - caplen) != 0)
			{
				final switch (cachelen)
				{
				case 1:	cache[0] = ava[$-1];	break;
				case 2:	cache[0] = ava[$-2];
						cache[1] = ava[$-1];	break;
				case 3:	cache[0] = ava[$-3];
						cache[1] = ava[$-2];
						cache[2] = ava[$-1];	break;
				}
				// It will be needed that buf.length >= 4 on next fetch.
				if (buf.length < 3) buf.length = 3;
			}
			device.consume(ava.length);
			debug (B64Dec)
				debugout(
					"capture2: view.length = %s, cachelen = %s, ava.length = %s",
					view.length, cachelen, ava.length);
			return true;
		}
	}
}


/*
	How to get PageSize:

	STLport
		void _Filebuf_base::_S_initialize()
		{
		#if defined (__APPLE__)
		  int mib[2];
		  size_t pagesize, len;
		  mib[0] = CTL_HW;
		  mib[1] = HW_PAGESIZE;
		  len = sizeof(pagesize);
		  sysctl(mib, 2, &pagesize, &len, NULL, 0);
		  _M_page_size = pagesize;
		#elif defined (__DJGPP) && defined (_CRAY)
		  _M_page_size = BUFSIZ;
		#else
		  _M_page_size = sysconf(_SC_PAGESIZE);
		#endif
		}
		
		void _Filebuf_base::_S_initialize() {
		  SYSTEM_INFO SystemInfo;
		  GetSystemInfo(&SystemInfo);
		  _M_page_size = SystemInfo.dwPageSize;
		  // might be .dwAllocationGranularity
		}
	DigitalMars C
		stdio.h
		
		#if M_UNIX || M_XENIX
		#define BUFSIZ		4096
		extern char * __cdecl _bufendtab[];
		#elif __INTSIZE == 4
		#define BUFSIZ		0x4000
		#else
		#define BUFSIZ		1024
		#endif

	version(Windows)
	{
		// from win32.winbase
		struct SYSTEM_INFO
		{
		  union {
		    DWORD dwOemId;
		    struct {
		      WORD wProcessorArchitecture;
		      WORD wReserved;
		    }
		  }
		  DWORD dwPageSize;
		  LPVOID lpMinimumApplicationAddress;
		  LPVOID lpMaximumApplicationAddress;
		  DWORD* dwActiveProcessorMask;
		  DWORD dwNumberOfProcessors;
		  DWORD dwProcessorType;
		  DWORD dwAllocationGranularity;
		  WORD wProcessorLevel;
		  WORD wProcessorRevision;
		}
		extern(Windows) export VOID GetSystemInfo(
		  SYSTEM_INFO* lpSystemInfo);

		void getPageSize()
		{
			SYSTEM_INFO SystemInfo;
			GetSystemInfo(&SystemInfo);
			auto _M_page_size = SystemInfo.dwPageSize;
			writefln("in Win32 page_size = %s", _M_page_size);
		}
	}
*/


/**
*/
ref Dst copy(Src, Dst)(ref Src src, ref Dst dst)
	if (!(isInputRange!Src && isOutputRange!(Dst, ElementType!Src)) &&
		(isPool!Src || isInputRange!Src) && (isSink!Dst || isOutputRange!Dst))
{
	void put_to_dst(E)(const(E)[] data)
	{
		while (data.length > 0)
		{
		  static if (isSink!Dst)
		  {
			if (!dst.push(data))
				throw new Exception("");
		  }
		  static if (isOutputRange!(Dst, typeof(data[0])))
		  {
			dst.put(data);
		  }
		}
	}
	
	static if (isPool!Src)
	{
		if (src.available.length == 0 && !src.fetch())
			return dst;
		
		do
		{
			// almost same with Ranged.put
			put_to_dst(src.available);
			src.consume(src.available.length);
		}while (src.fetch())
	}
	static if (isInputRange!Src)
	{
		static assert(isSink!Dst);
		
		static if (isArray!Src)
		{
			put_to_dst(src[]);
		}
		else
		{
			for (; !src.empty; src.popFront)
			{
				auto e = src.front;
				put_to_dst(&e[0 .. 1]);
			}
		}
	}
	return dst;
}