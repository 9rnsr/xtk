/**
This module supports converson of range from/to device.
*/
module inter_range;

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

