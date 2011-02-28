/*
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
module device;

import std.array, std.algorithm, std.range, std.traits;
import std.stdio;
version(Windows)
{
	import core.sys.windows.windows;
	enum : uint { ERROR_BROKEN_PIPE = 109 }
}

version = MeasPerf;
version (MeasPerf)
{
	import std.perf, std.file;
	version = MeasPerf_LinedIn;
	version = MeasPerf_BufferedOut;
}

debug = Workarounds;
debug (Workarounds)
{
	debug = Issue5661;	// std.algorithm.move
	debug = Issue5663;	// std.array.Appender.put
}

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
template ElementType(S)
	if (isSource!S || isPool!S || isSink!S)
{
	static if (isSource!S)
		alias Unqual!(typeof(ParameterTypeTuple!(typeof(S.init.pull))[0].init[0])) ElementType;
	static if (isPool!S)
		alias Unqual!(typeof(S.init.available[0])) ElementType;
	static if (isSink!S)
	{
		alias Unqual!(typeof(ParameterTypeTuple!(typeof(S.init.push))[0].init[0])) ElementType;
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
		alias ElementType!Device E;
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
		alias ElementType!Device E;
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
Buffered!(Device) buffered(Device)(Device device, size_t bufferSize)
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
	alias ElementType!Device E;
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
	alias ElementType!Device E;
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
		if (data.length == 0)
			return;
		
		do
		{	if (!device.push(data))
				throw new Exception("");
		}while (data.length > 0)
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
	//static assert(is(ElementType!Pool == Unqual!Char));	// compile-time evaluation bug？
	alias ElementType!Pool E;
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
			  debug (Issue5663)
				buffer.put(cast(MutableChar[])view);
			  else
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
					  debug (Issue5663)
						buffer.put(cast(MutableChar[])view[0 .. vlen]);
					  else
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


debug (Issue5661)
{
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
}	// Issue5661

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
Return $(D true) if $(D_PARAM T) is template.
*/
template isTemplate(alias T)
{
	enum isTemplate = is(typeof(T)) && !__traits(compiles, { auto v = T; });
}


/**
This may improvement of std.string.format.
*/
import std.format;
string format(Char, A...)(in Char[] fmt, A args)
{
    auto writer = appender!string();
    formattedWrite(writer, fmt, args);
	return writer.data;
}
unittest
{
	auto s = format("%(%02X %)", [1,2,3]);
	assert(s == "01 02 03");
}

void main(string[] args)
{
  version (MeasPerf)
  {
	version (MeasPerf_LinedIn)		doMeasPerf_LinedIn();
	version (MeasPerf_BufferedOut)	doMeasPerf_BufferedOut();
  }
}

version (MeasPerf)
void doMeasPerf_LinedIn()
{
	void test_file_buffered_lined(String)(string fname, string msg)
	{
		enum CalcPerf = true;
		size_t nlines = 0;
		
		auto pc = new PerformanceCounter;
		pc.start;
		{	foreach (i; 0 .. 100)
			{
				auto f = lined!String(device.File(fname), 2048);
				foreach (line; f)
				{
					line.dup, ++nlines;
					static if (!CalcPerf) writefln("%s", line);
				}
				static if (!CalcPerf) assert(0);
			}
		}pc.stop;
		
		writefln("%24s : %10.0f line/sec", msg, nlines / (1.e-6 * pc.microseconds));
	}
	void test_std_lined(string fname, string msg)
	{
		size_t nlines = 0;
		
		auto pc = new PerformanceCounter;
		pc.start;
		{	foreach (i; 0 .. 100)
			{
				auto f = std.stdio.File(fname);
				foreach (line; f.byLine)
				{
					line.dup, ++nlines;
				}
				f.close();
			}
		}pc.stop;
		
		writefln("%24s : %10.0f line/sec", msg, nlines / (1.e-6 * pc.microseconds));
	}

	writefln("Lined!(BufferedSource!File) performance measurement:");
	auto fname = __FILE__;
	test_std_lined							(fname,        "char[] std in ");
	test_file_buffered_lined!(const(char)[])(fname, "const(char)[] dev in ");	// sliceed line
	test_file_buffered_lined!(string)		(fname,        "string dev in ");	// idup-ed line
}

version (MeasPerf)
void doMeasPerf_BufferedOut()
{
	enum RemoveFile = true;
	size_t nlines = 100000;
//	auto data = "ABCDEFGHIJKLMNOPQRSTUVWXYZ\r\n";
	auto data = "1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz\r\n";
	
	void test_std_out(string fname, string msg)
	{
		auto pc = new PerformanceCounter;
		pc.start;
		{	auto f = std.stdio.File(fname, "wb");
			foreach (i; 0 .. nlines)
			{
				f.write(data);
			}
		}pc.stop;
		writefln("%24s : %10.0f line/sec", msg, nlines / (1.e-6 * pc.microseconds));
		static if (RemoveFile) std.file.remove(fname);
	}
	void test_dev_out(alias Sink)(string fname, string msg)
	{
		auto bytedata = cast(ubyte[])data;
		
		auto pc = new PerformanceCounter;
		pc.start;
		{	auto f = Sink!(device.File)(fname, "w", 2048);
			foreach (i; 0 .. nlines)
			{
				f.push(bytedata);
			}
		}pc.stop;
		writefln("%24s : %10.0f line/sec", msg, nlines / (1.e-6 * pc.microseconds));
		static if (RemoveFile) std.file.remove(fname);
	}

	writefln("BufferedSink/Device!File performance measurement:");
	test_std_out                  ("out_test1.txt",        "std out");
	test_dev_out!(Buffered!Sinked)("out_test2.txt", "  sink dev out");
	test_dev_out!(Buffered)       ("out_test3.txt", "device dev out");
}
