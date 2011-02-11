module file.file;

//import win32.windows;
import core.sys.windows.windows;
import std.typecons;
//import std.stdio;
import std.string;

import std.range;

enum EOF = char.init;
enum LF = '\n';


template isSource(T)
{
	enum isSource = is(typeof({
		void f(ref T source){
			ubyte[] buf;
			pull(source, buf);
		}
	}()));
}

/*
	pull is operation of Source.
	
	fill buf elements that read from source.
	Returns:
		after read, source has elements that can read.
	buf.length == 0
		
	if source has no elements that can read, return false;
*/
bool pull(Source, T)(ref Source s, ref T[] buf)
{
	static if (is(typeof(s.pull(buf))))
	{
		return s.pull(buf);
	}
	else static if (hasSlicing!Source && hasLength!Source)
	{
		// この実装で正しいのか？
		// 「RangeのSliceを取る」のが、単に要素の配列？を返すのではなく
		// 「また別のRangeを返す」ならこの実装だとだめな可能性がある
		
		auto len = min(buf.length, s.length)
		buf[len] = s[0 .. len];
		popFrontN(s, len);
		buf = buf[0 .. len];
		return !s.empty;
	}
	else static if (isInputRange!Source)
	{
		if (buf.length == 0)
			return !s.empty;
		else
		{
			auto len = 0;
			foreach (e; s)
			{
				buf[len++] = e;
				if (len == buf.length) break;
			}
			buf = buf[0 .. len];
			return true;
		}
	}
}

struct File
{
private:
	HANDLE hFile;
	char pushback = char.init;

public:
	this(string fname)
	{
	//	writefln(typeof(this).stringof ~ " ctor");
		
		int share = FILE_SHARE_READ | FILE_SHARE_WRITE;
		int access = GENERIC_READ;
		int createMode = OPEN_EXISTING;
		hFile = CreateFileW(
			std.utf.toUTF16z(fname), access, share, null, createMode, 0, null);
	}
	this(this)
	{
		// todo
	}
	
	~this()
	{
		CloseHandle(hFile);
		hFile = null;
	//	writefln(, typeof(this).stringof ~ " dtor");
	}
	
	bool pull(ref ubyte[] buf)
	{
		// yet support only synchronous read
		bool result;
		
		size_t len;
		if (ReadFile(hFile, buf.ptr, buf.length, &len, null))
			result = (len != 0);
		else
			throw new Exception("pull error");	//?
		
		buf = buf[0 .. len];
		return result;
	}
}
static assert(isSource!File);

/*
	Input
	↓	+ Sliced
	↓
	Forward
	↓	+ Sliced
	↓
	Bidirectional
	↓	+ Sliced
	↓
	RandomAccess

	Output
		+ Sliced
*/



/*
	Typed Input はオリジナルのSourceまたはRangeと同じように振舞う
	Input == SourceならSourceとして、RangeならRangeとして
	
	Typedはorphan byteをキャッシュするというStrategyもありか…
	この場合Bufferedと分離できないからなあ、BufferedにTを指定できるようにする？
*/
/+struct Typed(Input, T)
{
	static assert(isSource || is(ElementType!Input == ubyte));
	
	void read(ref T[] buf)
	{
		ubyte[] raw_buf = (cast(ubyte*)buf.ptr)[0 .. T.sizeof * buf.length];
		input.read(raw_buf);
		
		auto len = raw_buf.length / T.sizeof;
		if (raw_buf.length - len * T.sizeof > 0)
			throw new Exception("orphan bytes");
		buf = buf[0 .. len];
}+/


/*
	FilterはConstructor時点でRangeをFillする
	最初の読み出しまでFillを遅延する場合は、遅延用の仕組みを使用する
	参照：optionalなどによる初期化遅延(http://d.hatena.ne.jp/gintenlabo/20100428/1272470686)
*/

/*
	InputはSourceである必要がある？(設計としてまだ不確定)
	Buffered はRangeとして振舞う
*/
/*
	これってVLERangeってやつでは？
	SliceRangeという名前を思いついた
	→	InputSlice
			@property T[] front()
		BidirectionalSlice
			@property T[] back()
	→	特殊なElementTypeを持つRangeを特にこう呼ぶとか？
*/
/*
	もし型変換も担うとしたら
	Source
		pullを使って、Source/Rangeから取り出せる
	front
		T[]を返す
		内部で型変換を掛ける
			入出力で同じ型の場合は何もしない
			キャストで済む場合はメモリイメージを維持する
				CTFEできるかな…
			ユーザー定義型でopCastが定義されている場合は、個々の要素をCopyConstructする
				この場合、Inputは常にRangeとして扱う？
					中間処理用のバッファと、変換結果のバッファの2つに別れてしまう
					→明示的にsourceと同じ型のBufferedと型変換用のBufferedを分ければいい
	
	型変換は原理的にコピーを伴う
	(ビットコピーで済む場合は同じメモリ領域を型を変えて指せるが)
	また、型のサイズが異なる場合、orphan bytesを処理するためにキャッシュも必要となる
	よってBuffered+Convertをひとつにするのが望ましい
	→Bufferedという名前だとこの意図を十分に表現しきれないんだよなあ
*/

auto buffered(Source)(Source s, size_t bufferSize=1024)
{
	return Buffered!Source(s, bufferSize);
}

/**
	BufferedはSourceで、かつInputRangeのI/Fを持つ
	
	Bufferedは入力(Range/Source)をPartial Random Access Rangeにマップする
*/
struct Buffered(Source)
{
	/* implementation:
		ring buffer
	*/
	static assert(isSource!Source/* || isInputRange!Source*/);
	
	Source source;
	ubyte[] buffer, buf;
	
	this(Source s, size_t bufferSize)
	{
		source = s;
		buffer.length = bufferSize;
		popFront();
	}
	
	@property bool empty()
	{
		return buf.length == 0;
	}
	
	@property ubyte[] front()
	{
		return buf;
	}
	
	void popFront()
	{
		buf = buffer;
		static if (isSource!Source)
		{
			pull(source, buf);	// fetch buffer
		}
		else static if (isInputRange!Source)
		{
			assert(0, "yet not planed");
			size_t len = 0;
			foreach (c; source)
			{
				buf[len] = c;
				if (len == buffer.length - 1) break;
			}
			buf = buf[0 .. len];
		}
	}
}

version(Windows)
{
	enum ubyte[] NativeNewLine = [0x0d, 0x0a];
}
else
{
	static assert(0, "not yet supported");
}

template lined(String=string)
{
	auto lined(Source)(Source s, in ubyte[] delim=NativeNewLine)
	{
		return Lined!(Source, String)(s, delim);
	}
}

struct Lined(Source, String)
{
//	alias immutable(ubyte)[] RawString;
	//	pragma(msg, String, ": is(", typeof(String.init[0]), " == immutable) = ", UniqueLine);
	enum UniqueLine = is(typeof(String.init[0]) == immutable);
	
	Source source;
	const(ubyte)[] delim;
	
	this(Source s, in ubyte[] d)
	{
		source = s;
		delim = d;
	}
	
	@property bool empty() const
	{
		return false;
	}
	
	@property String front() const
	{
		static if (UniqueLine)
		{
			// バッファの再利用なし
			return null;
		}
		else
		{
			// バッファの再利用あり
			return null;
		}
	}
	
	void popFront()
	{
	}
}

/+template UTF8Lined(Source, alias Term=NativeNewLine)
{
	alias Lined!(string, Source, Term) UTF8Lined;
}+/



unittest
{
//	foreach (line; File("data.txt") | Buffered | Lined!string)
	foreach (line; lined!string(buffered(File("data.txt"))))
	{
		
	}
}

void main()
{
}
