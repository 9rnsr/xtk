﻿/**

Source,Pool,Sinkの3つを基本I/Fと置く
(バッファリングされたSinkを明示的に扱う手段はなくす)

それぞれがやり取りする要素の型は任意だが、Fileはubyteをやり取りする
(D言語的にはvoid[]でもいいかも)

Encodedはubyteを任意型にcastする機能を提供する
Bufferedはバッファリングを行う

*/
//module std.device;
module device;

import std.array, std.algorithm, std.range, std.traits;
import std.stdio;
version(Windows)
{
	import core.sys.windows.windows;
	enum : uint { ERROR_BROKEN_PIPE = 109 }
}

//version = MeasPerf;
version (MeasPerf)
{
	import std.perf, std.file;
	version = MeasPerf_LinedIn;
	version = MeasPerf_BufferedOut;
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
//	__traits(allMembers, T)にはstatic ifで切られたものも含まれている…
//	enum isSource = hasMember!(S, "pull");
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
定義では、poolの初期状態は長さ0の$(D available)を持つ。$(BR)
You can assume that pool is not $(D fetch)-ed yet.$(BR)
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
Returns $(D true) if $(D S) is a $(I sink). A Source must define the
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
Device supports both operations of source and sink.
*/
template isDevice(S)
{
	enum isDevice = isSource!S && isSink!S;
}

deprecated alias isPool isInputPool;

deprecated template isOutputPool(S)
{
	enum isOutputPool = is(typeof({
		S s;
		do
		{
			auto buf = s.usable;
			size_t n;
			s.commit(n);
		}while (s.flush())
	}()));
}

/+
alias isInputPool isPoolSource;
alias isOutputPool isPoolSink;
template isPoolDevice(S)
{
	enum isPoolDevice = isPoolSource!S && isPoolSink!S;
}+/

/**
ElementType for Device (Source/Pool/Sink)
Naming:
	?
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
Check that $(D S) is seekable source or sink.
Seekable source/sink supports $(D seek) operation.
*/
template isSeekable(S)
{
	enum isSeekable = is(typeof({
		S s;
		s.seek(0, SeekPos.Set);
	}()));
}


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
unittest
{
	static assert(isSource!File);
	static assert(isSink!File);
	static assert(isDevice!File);
}

/**
Modifier templates to limit operations of $(D Device).
*/
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
		Delegate construction to $(D Device).
		*/
		this(A...)(A args)
		{
			move(Device(args), device);
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
		Delegate construction to $(D Device).
		*/
		this(A...)(A args)
		{
			move(Device(args), device);
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

/**
*/
struct Encoded(Device, E)
{
private:
	Device device;
//	pragma(msg, "Encoded!(", Device, ", ", E, ") :");
//	pragma(msg, "  isSource!Device = ", isSource!Device);
//	pragma(msg, "  isPool  !Device = ", isPool  !Device);
//	pragma(msg, "  isSink  !Device = ", isSink  !Device);

public:
	/**
	*/
	this(Device d)
	{
		move(d, device);
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
	Interfaces of Pool.
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
	Interface of Sink
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

/**
*/
struct Buffered(Device)
	if (isSource!Device || isSink!Device)
{
private:
	alias ElementType!Device E;
//	pragma(msg, "Buffered!(", Device, ") : E = ", E);
//	pragma(msg, "  isSource!Device = ", isSource!Device);
//	pragma(msg, "  isPool  !Device = ", isPool  !Device);
//	pragma(msg, "  isSink  !Device = ", isSink  !Device);

	Device device;
	E[] buffer;
	static if (isSink  !Device) size_t rsv_start = 0, rsv_end = 0;
	static if (isSource!Device) size_t ava_start = 0, ava_end = 0;
	static if (isDevice!Device) long base_pos = 0;

public:
	/**
	*/
	this(Device d, size_t bufferSize)
	{
		move(d, device);
		buffer.length = bufferSize;
	}
	
  static if (isSink!Device)
	~this()
	{
		while (reserves.length > 0)
			flush();
	}

  static if (isSource!Device)
	/**
	Interfaces of pool.
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
	/**
	Interfaces of output pool?
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
	/// ditto
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
	Interfaces of output pool?
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
	Interfaces of sink.
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
//	din  = BufferedSource!File(GetStdHandle(STD_INPUT_HANDLE ), 2048);
//	dout = BufferedSink  !File(GetStdHandle(STD_OUTPUT_HANDLE), 2048);
//	derr = BufferedSink  !File(GetStdHandle(STD_ERROR_HANDLE ), 2048);
	din  = Sourced!File(GetStdHandle(STD_INPUT_HANDLE));
	dout = Sinked !File(GetStdHandle(STD_OUTPUT_HANDLE));
	derr = Sinked !File(GetStdHandle(STD_ERROR_HANDLE));
}
/*__gshared
{*/
//	BufferedSource!File din;
//	BufferedSink  !File dout;
//	BufferedSink  !File derr;
	Sourced!File din;
	Sinked !File dout;
	Sinked !File derr;
/*}*/














/**
Deprected:
	for performance test only.
*/
deprecated struct BufferedSink(Output) if (isSink!Output)
{
private:
	Output output;
	ubyte[] buffer;
	size_t rsv_start = 0, rsv_end = 0;

private:
	this(T)(T o, size_t bufferSize) if (is(T == Output))
	{
		move(o, output);
		buffer.length = bufferSize;
	}
public:
	/*
	Outputにconstructionを委譲する
	Params:
		args		= output constructor arguments
		bufferSize	= バッファリングされる要素数
	*/
	this(A...)(A args, size_t bufferSize)
	{
		__ctor(Output(args), bufferSize);
	}
	~this()
	{
		while (reserves.length > 0)
			flush();
	}
	
	/*
	Interfaces of OutputPool.
	*/
	@property ubyte[] usable()
	{
		return buffer[rsv_end .. $];
	}
	private @property const(ubyte)[] reserves()
	{
		return buffer[rsv_start .. rsv_end];
	}
	
	// ditto
	void commit(size_t n)
	{
		assert(rsv_end + n <= buffer.length);
		rsv_end += n;
	}
	
	// ditto
	bool flush()
	in { assert(reserves.length > 0); }
	body
	{
		auto rsv = buffer[rsv_start .. rsv_end];
		auto result = output.push(rsv);
		if (result)
		{
			rsv_start = rsv_end - rsv.length;
			if (reserves.length == 0)
			{
				rsv_start = rsv_end = 0;
			}
		}
		return result;
	}

	/*
	*/
	bool push(const(ubyte)[] data)
	{
	//	フリー関数使用だと性能が1/10ぐらいに落ちる
	//	.put(this, data);
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

/**
Deprected:
	for performance test only.
*/
deprecated struct BufferedDevice(Device)
	if (isDevice!Device)					// Bufferedの側でSource/Sink/Deviceを明示して区別する
//	if (isSource!Device || isSink!Device)	// オリジナルのdeviceに応じて最大公約数のI/Fを提供する
{
private:
	Device device;
	ubyte[] buffer;
	static if (isSink  !Device) size_t rsv_start = 0, rsv_end = 0;
	static if (isSource!Device) size_t ava_start = 0, ava_end = 0;
	static if (isDevice!Device) long base_pos = 0;

private:
	this(T)(T d, size_t bufferSize) if (is(T == Device))
	{
		move(d, device);
		buffer.length = bufferSize;
	}
public:
	/*
	Deviceにconstructionを委譲する
	Params:
		args		= device constructor arguments
		bufferSize	= バッファリングされる要素数
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
	/*
	Interfaces of InputPool.
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
	// ditto
	@property const(ubyte)[] available() const
	{
		return buffer[ava_start .. ava_end];
	}
	
  static if (isSource!Device)
	// ditto
	void consume(size_t n)
	in { assert(n <= available.length); }
	body
	{
		ava_start += n;
	}

  static if (isSink!Device)
	/*
	Interfaces of OutputPool.
	*/
	@property ubyte[] usable()
	{
	  static if (isDevice!Device)
		return buffer[ava_start .. $];
	  else
		return buffer[rsv_end .. $];
	}
  static if (isSink!Device)
	private @property const(ubyte)[] reserves()
	{
		return buffer[rsv_start .. rsv_end];
	}
	
  static if (isSink!Device)
	// ditto
	void commit(size_t n)
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
	
  static if (isSink!Device)
	// ditto
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
	/*
	*/
	bool push(const(ubyte)[] data)
	{
	//	フリー関数使用だと性能が1/10ぐらいに落ちる
	//	.put(this, data);
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

/+
struct BufferedSource(Input) if (isArray!Input)
{
}
+/

/+
struct BufferedSource(Input) if (!isArray!Input && isInputRange!Input)
{
}
+/

/+/**
OutputRange I/F
Native implement for PoolSink
*/
void put(Sink, T)(Sink sink, const(T)[] data) if (isPoolSink!Sink)
out {assert(sink.usable.length > 0); }
body
{
	while (data.length > 0)
	{
		if (sink.usable.length == 0)
			sink.flush();
		auto len = min(data.length, sink.usable.length);
		sink.usable[0 .. len] = data[0 .. len];
		data = data[len .. $];
		sink.commit(len);
	}
	if (sink.usable.length == 0)
		sink.flush();
}+/



/**
構築済みのInputをRangedで包むための補助関数
*/
Ranged!Device ranged(Device)(Device device)
{
	return Ranged!Device(move(device));
}

/**
PoolをInput/OutputRangeに変換する
Design:
	Rangeはコンストラクト直後にemptyが取れる、つまりPoolでいうfetch済みである必要があるが、
	Poolは未fetchであることが必要なので互いの要件が矛盾する。よってPoolはInputRangeを
	同時に提供できないため、これをWrapするRangedが必要となる。
Design:
	Sourceは先読みが出来ない＝emptyを計算できないので不可能
	OutputRangeはempty無関係なのでSinkのpushでいける
*/
struct Ranged(Device) if (isPool!Device || isSink!Device)
{
private:
	alias ElementType!Device E;
	Device device;
	bool eof;

public:
	this(Device d)
	{
		move(d, device);
	  static if (isPool!Device)
		eof = !device.fetch();
	}

  static if (isPool!Device)
  {
	/**
	Interfaces of input range.
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
	Interface of output range.
	*/
	void put(const(E)[] data)
	{
		if (data.length == 0)
			return;
		
		do
		{
			if (!device.push(data))
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

/+/**
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
	
/*	void print(string msg, ubyte[] data)
	{
		writefln("%s", msg);
		foreach (n ; 0 .. data.length/16 + (data.length%16>0 ? 1:0))
		{
			writefln("%(%02X %)", data[16*n .. min(16*(n+1), data.length)]);
		}
	}
	print("UTF8",  cast(ubyte[])strc);
	print("UTF16", cast(ubyte[])strw);
	print("UTF32", cast(ubyte[])strd);*/
	
	void decode_test(Char, R)(R data, dstring expect)
	{
		assert(equal(decoder!Char(data), expect));
	}
	decode_test!( char)(cast(ubyte[])strc, strd);
	decode_test!(wchar)(cast(ubyte[])strw, strd);
	decode_test!(dchar)(cast(ubyte[])strd, strd);
}+/


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
	lined!string(File("foo.txt"))
//	lined!(const(char))("foo\nbar\nbaz", "\n")
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
	// フィルタの順番を逆にしても動作する
	alias Unqual!(typeof(String.init[0]))   Char;
	alias Buffered!(Source)				Buf;
	alias Encoded!(Buf, Char)          Enc;
	alias Lined!(Enc, String, String) LinedType;
	return LinedType(Enc(Buf(move(source), bufferSize)), cast(String)NativeNewLine);
+/
}
auto lined(String=string, Source, Delim)(Source source, in Delim delim, size_t bufferSize=2048)
	if (isSource!Source && isInputRange!Delim)
{
	alias Unqual!(typeof(String.init[0]))	Char;
	alias Encoded!(Source, Char)			Enc;
	alias Buffered!(Enc)					Buf;
	alias Lined!(Buf, Delim, String)		LinedType;
	return LinedType(Buf(Enc(move(source)), bufferSize), move(delim));
}


/**
CharのPoolを取り、Delimを区切りとして切り出されたLineのInputRangeを構成する

Naming:
	LineReader?
	LineStream?
*/
struct Lined(Pool, Delim, String : Char[], Char)
	if (isPool!Pool && isSomeChar!Char)
{
//	pragma(msg, "Lined : ElementType!(", Pool, ") = ", ElementType!Pool);
	//static assert(is(ElementType!Pool == Unqual!Char));	// 評価バグ？
	alias ElementType!Pool E;
	static assert(is(E == Unqual!Char));

private:
	alias Unqual!Char MutableChar;

	Pool pool;
	Delim delim;
	Appender!(MutableChar[]) buffer;	// trivial: reduce initializing const of appender
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
				buffer.put(cast(MutableChar[])view);	//Generic input rangeとして扱わせないためのworkaround
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
						buffer.put(cast(MutableChar[])view[0 .. vlen]);	//Generic input rangeとして扱わせないためのworkaround
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

/+unittest
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
			assert(expect[ln] == line,
				format(
					"%s -> lined!%s fails\n"
					"\t[%s] = \tline   = %(%02X %)\n\t\texpect = %(%02X %)",
					Str1.stringof, Str2.stringof,
					ln, cast(ubyte[])line, cast(ubyte[])expect[ln]));
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
}+/


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


template CharType(T) if (isSomeString!T)
{
	alias ForeachType!T CharType;
}

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

	test_replying_cat();
}

void test_replying_cat()
{
	void put(Sink, E)(Sink s, const(E)[] data)
	{
		auto v = cast(const(ubyte)[])data;
		while (v.length > 0)
			s.push(v);
	}
	
	foreach (line; lined!(const(char)[])(din))
	{
		//writeln("> ", line);
		put(dout, "> ");
		put(dout, line);
		put(dout, "\r\n");
	//	std.format.formattedWrite(dout, "%s\r\n", line);
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
	test_std_out                 ("out_test1.txt",        "std out");
	test_dev_out!(BufferedSink)  ("out_test2.txt", "  sink dev out");
	test_dev_out!(BufferedDevice)("out_test3.txt", "device dev out");
	test_dev_out!(Buffered)      ("out_test4.txt", "device dev out");
}
