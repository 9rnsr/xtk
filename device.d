/**
	定義
	Source/Sinkの基本要素はubyteである
*/
//module std.device;
import std.algorithm, std.range, std.traits;
version(Windows)
{
	import core.sys.windows.windows;
}

import std.stdio;
void main(string[] args)
{
	if (args.length != 2) return;

/+	foreach (char c; buffered(File(args[1])))
	{
		if (c != '\r') write(c);
	}	// +/

	foreach (line; lined!wstring(buffered(File(args[1]))))
		writeln(line);
}


/*
	Check that S is source.
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
			const(ubyte)[] data = .pull(s, len, buf);
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


/+/**
	get empty status from source or sink.
	this is free funcion version.
*/
@property bool empty(S)(in S s)
	if (!isInputRange!S && (isSource!S || isSink!S))
{
    return s.empty;
}+/


/*
	sからlenバイトを読み出し、bufへ格納する
	→	1.callerから与えられたバッファを埋める
		2.calleeでバッファを確保し、Viewを返す
*/
const(ubyte)[] pull(S)(ref S s, size_t len, ubyte[] buf=null)
{
	static if (is(typeof(s.pull(len, buf))))
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
		static assert(is(ElementType!S : ubyte));
		
		if (buf.length > 0)
			len = min(buf.length, len);
		else
			buf.length = len;
		
		buf = buf[0 .. len];
		
		// rangeをSourceとして扱う場合はすべてputに任せる
		put(buf, s);
		return buf;
	}
	else
	{
		static assert(0, S.stringof~" does not support pull operation");
	}
}

/+
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
	auto data = .pull(s, len, buf);
	if (data.length < len)
	{
		auto req = len - data.length;
		while (!s.empty)
		{
			
		}
	}
}+/

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

/+/**
*/
void seek(S)(ref S s, long offset, SeekPos whence)
{
	s.seek(offset, whence);
}+/


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
	
  static if (isSource!R)
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
		debug writefln("hFile=%08X, GetLastError()=%s", cast(uint)hFile, GetLastError());
	}
	this(this)
	{
		debug writefln("cpctor hFile=%08X, pRefCounter=%s", cast(uint)hFile, *pRefCounter);
		if (pRefCounter) ++(*pRefCounter);
	}
	~this()
	{
		debug writefln("dtor hFile=%08X, pRefCounter=%s", cast(uint)hFile, pRefCounter);
		if (pRefCounter && --(*pRefCounter) == 0)
		{
			debug writefln("%s", typeof(this).stringof ~ " dtor");
			delete pRefCounter;
			CloseHandle(cast(HANDLE)hFile);
		}
	}

	@property bool empty() const
	{
		return eof;
	}
	
	const(ubyte)[] pull(size_t len, ubyte[] buf)
	{
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
			eof = (size == 0);
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


auto buffered(Source)(Source s, size_t bufferSize=1024)
{
	return Buffered!Source(s, bufferSize);
}

/**
?	BufferedはSourceで、かつInputRangeのI/Fを持つ
	
?	Bufferedは入力(Range/Source)をPartial Random Access Rangeにマップする

	バッファのアロケーションについては積極的
	
	
	RangeまたはSourceを取り、InputRangeとなる
	
	
	
	別名ByChunk
*/
struct Buffered(Source)
{
	Source source;
	ubyte[] buffer, view;
	
	this(Source s, size_t bufferSize)
	{
		source = s;
		buffer.length = bufferSize;
		fetch();
	}
	
	@property bool empty() const
	{
		return view.length==0 && source.empty;
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
		auto v = .pull(source, buffer.length, buffer);
		view = buffer[0 .. v.length];
	}
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
auto lined(String=string, Range, Delim=String)(Range r, in Delim delim=NativeNewLine)
{
	return Lined!(Range, String)(r, delim);
}

/**
	Rangeを取り、行のRangeを返す
	
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
struct Lined(Range, String)
//	if (is(typeof({ Unqial!(ElementType!String) x == ElementType!Range.init; }())))
//	→Rangeの要素をmutableな配列にコピーできるか、stringはdecode/encodeが走るので上の条件ではうまく判定できない
{
//	alias immutable(ubyte)[] RawString;
	//	pragma(msg, String, ": is(", typeof(String.init[0]), " == immutable) = ", UniqueLine);
//	enum UniqueLine = is(typeof(String.init[0]) == immutable);

private:
	Range input;
	String delim;
	Unqual!(typeof(String.init[0]))[] lineBuffer;
	String line;

public:
	this(Range r, in String d)
	{
		input = r;
		delim = d;
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
		auto app = appender(lineBuffer);
		app.clear();
		
		size_t dlen = 0;
	//	foreach (e; input)	inputがここでコピーされるので、inputそのものは進まない！
		while (!input.empty)
		{
			auto e = input.front;
			input.popFront();
		
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
	
  static if (isOutputRange!(Range, String))
	void put()
	{
	}
}
void testParseLines(String)()
{
	String[] lines;
	foreach (line; lined!String(cast(String)"head\nmiddle\nend", cast(String)"\n"))
		lines ~= line;
	assert(lines == [cast(String)"head", cast(String)"middle", cast(String)"end"]);
}
unittest
{
	testParseLines!string();
	testParseLines!wstring();
	testParseLines!dstring();

}
