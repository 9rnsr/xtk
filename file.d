module file.file;

import win32.windows;
import std.typecons;
//import std.stdio;
import std.string;


enum EOF = char.init;
enum LF = '\n';


struct FileSource
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
	@disable this(this);
	
	~this()
	{
		CloseHandle(hFile);
		hFile = null;
	//	writefln(, typeof(this).stringof ~ " dtor");
	}
	
	void read(ref ubyte[] buf)
	{
		size_t len;
		if (ReadFile(hFile, buf.ptr, buf.length, &len, null) == 0)
			throw new Exception("read error");
		
		buf = buf[0 .. len];
	}
}

template IsSource(T)
{
	enum isSource = is(typeof({
		f(ref T source){
			ubyte[] buf;
			source.read(buf);
		}));
}

static assert(isSource!FileSource);

void pull(Source, T)(ref Source s, ref T[] buf)
{
	static if (isSource!Source)
	{
		s.pull(buf);
	}
	else static if (isInputRange!Source)
	{
		
	}
}

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
struct Typed(Input, T)
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
}


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
struct Buffered(Source, size_t bufferSize=1024)
{
	/* implementation:
		ring buffer
	*/
	static assert(isSource!Source/* || isInputRange!Source*/);
	
	Source src;
	ubyte[] buffer, buf;
	
	this(Source s)
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
			source.read(buf);	// fetch buffer
		}
		else static if (isInputRange!Source)
		{
			assert(0, "yet not planed");
			size_t len = 0;
			foreach (c; source)
			{
				buf[len] = c;
				if (len == bufferSize - 1) break;
			}
			buf = buf[0 .. len];
		}
	}
}

struct Lined(Source, Char=char, immutable(Char[]) Term="\r\n")
{
	alias immutable(Char)[] String;
	
	Source src;
	
	this(Source s)
	{
		source = s;
	}
	
	@property String front()
	{
		
	}
}



struct FilePos
{
	ulong line = 0;
	ulong column = 0;
	
	this(ulong ln, ulong col){
		line = ln;
		column = col;
	}
	
	string toString(){
		return (cast(const(FilePos))this).toString();
	}
	string toString() const{
		return format("[%s:%s]", line+1, column+1);
	}
}


struct FilePos_TextFile_Source
{
private:
	TextFile_Source src;
	FilePos pos;

public:
	this(string fname){
	//	writefln("FilePos_TextFile_Source ctor");
		src = TextFile_Source(fname);
	}
	~this(){
	//	writefln("FilePos_TextFile_Source dtor");
	}
	
	Tuple!(FilePos, char) read(){
		char ch;
		auto cur_pos = pos;
		
		if( (ch = src.read()) != EOF ){
			if( ch == LF ){
				pos.line += 1;
				pos.column = 0;
			}else{
				pos.column += 1;
			}
		}else{
			pos.column += 1;
		}
		
		return tuple(cur_pos, ch);
	}
}
