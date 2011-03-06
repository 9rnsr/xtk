module device_base64;

public import device;
import std.array, std.algorithm, std.range, std.traits;
alias device.move move;

alias Base64_0!() base64_0;
alias Base64_1!() base64_1;
alias Base64_2!() base64_2;
alias Base64_3!() base64_3;
alias Base64_4!(ImplKind.CharPool)   base64_4p;
alias Base64_4!(ImplKind.ChunkRange) base64_4x;
alias Base64_4!(ImplKind.CharRange)  base64_4c;
alias Base64_5!() base64_5;

/**
encode each chunk (same as std.base64)
*/
template Base64_0(char Map62th = '+', char Map63th = '/', char Padding = '=')
{
	//debug = Encoder;

	/**
	*/
	Encoder!Device encoder(Device)(Device d, size_t bufferSize = 2048)
	{
		return Encoder!Device(move(d), bufferSize);
	}

	/**
	*/
	struct Encoder(Device) if (isPool!Device)
	{
		import std.base64 : StdBase64 = Base64;
	private:
		Device device;
		bool eof;
		char[] buffer, view;
	public:
		// Ignore bufferSize
		this(Device d, size_t bufferSize)
		{
			move(d, device);
			chunk_fetch();
		}
		@property bool empty()		{ return eof; }
		@property char[] front()	{ return view; }
		void popFront()				{ chunk_fetch(); }
	private:
		void chunk_fetch()
		{
			if (device.fetch())
			{
				auto data = device.available;
				auto size = StdBase64.encodeLength(data.length);
				//writefln("data.length = %s, size = %s", data.length, size);
				if (size > buffer.length)
					buffer.length = size;
				
				view = StdBase64.encode(data, buffer);
				//assert(view.length > 0);
				device.consume(data.length);
			}
			else
				eof = true;
		}
	}
}

/**
encode each 3 bytes
*/
template Base64_1(char Map62th = '+', char Map63th = '/', char Padding = '=')
{
	//debug = Encoder;

	/**
	*/
	Encoder!Input encoder(Input)(Input input, size_t bufferSize = 2048)
	{
		return Encoder!Input(move(input), bufferSize);
	}

	/**
	*/
	struct Encoder(Input)
		if (isPool!Input)
	{
	private:
		Input input;
		bool eof;
		char[4] encoded;
		size_t pos;

		enum char Map62th = '+';
		enum char Map63th = '/';
		private immutable EncodeMap = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789" ~ Map62th ~ Map63th;
		enum char Padding = '=';

	public:
		this(Input i, size_t bufferSize)
		{
			move(i, input);
			
			pos = 4;
			popFront();
		}
		@property bool empty()	{ return eof; }
		@property char front()	{ return encoded[pos]; }
		void popFront()
		{
			if (++pos < encoded.length)
				return;
			
			ubyte[3] buf;
			
			auto view = input.available;
			auto rem = view.length;
			if (rem >= buf.length)
			{
				buf[0] = view[0];
				buf[1] = view[1];
				buf[2] = view[2];
				input.consume(3);
			}
			else
			{
				debug(Encoder) writefln("a: rem = %s", rem);
				size_t n = 0, i = 0;
				do{
				  Retry:
					if (i == rem)
					{
						debug(Encoder) writefln("b: i = %s, rem = %s", i, rem);
						input.consume(rem);
						eof = !input.fetch();
						if (eof)
						{
							final switch (n)
							{
							case 1:
								immutable val = buf[0] << 16;
								encoded[0] = EncodeMap[val >> 18       ];
								encoded[1] = EncodeMap[val >> 12 & 0x3f];
								encoded[2] = Padding;
								encoded[3] = Padding;
								break;		/** fall through */
							case 2:
								immutable val = buf[0] << 16 | buf[1] << 8;
								encoded[0] = EncodeMap[val >> 18       ];
								encoded[1] = EncodeMap[val >> 12 & 0x3f];
								encoded[2] = EncodeMap[val >>  6 & 0x3f];
								encoded[3] = Padding;
								break;
							}
							goto Exit;
						}
						view = input.available;
						rem = view.length;
						i = 0;
						debug(Encoder) writefln("c: rem = %s, i = %s", rem, i);
						goto Retry;
					}
					debug(Encoder) writefln("d: n = %s, i = %s", n, i);
					buf[n++] = view[i++];
				}while (n < 3);
				debug(Encoder) writefln("e: n = %s, i = %s", n, i);
				input.consume(i);
			}
			
			immutable val = buf[0] << 16 | buf[1] << 8 | buf[2];
			encoded[0] = EncodeMap[val >> 18       ];
			encoded[1] = EncodeMap[val >> 12 & 0x3f];
			encoded[2] = EncodeMap[val >>  6 & 0x3f];
			encoded[3] = EncodeMap[val       & 0x3f];
		  Exit:
			pos = 0;
			debug(Encoder) writefln("buf = [%(%02X %)], encoded = [%(%02X %)](%s), pos = %s",
				buf, cast(ubyte[])encoded, encoded, pos);
		}
	}

}

/**
encode each available
*/
template Base64_2(char Map62th = '+', char Map63th = '/', char Padding = '=')
{
	//debug = Encoder;

	/**
	*/
	Encoder!Input encoder(Input)(Input input, size_t bufferSize = 2048)
	{
		return Encoder!Input(move(input), bufferSize);
	}

	/**
	*/
	struct Encoder(Input)
		if (isPool!Input)
	{
		import std.base64;
	private:
		Input input;
		bool eof;
		char[] buffer;
		size_t inputLength;
		char[] view;

		private immutable EncodeMap = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789" ~ Map62th ~ Map63th;

	public:
		this(Input i, size_t bufferSize)
		{
			move(i, input);
			
			if (bufferSize < 128)	//最低限のサイズを確保
				bufferSize = 128;
			if (auto mod = bufferSize % 4)
				bufferSize += mod;
			inputLength = bufferSize / 4 * 3;
			buffer.length = bufferSize;
			view = buffer[0 .. 1];	//hack
			popFront();
		}
		@property bool empty()		{ return eof; }
		@property char front()		{ return view[0]; }
		void popFront()
		{
			// fetch is sync only
			
			view = view[1 .. $];
			if (view.length > 0)
				return;
			
			auto len = min(input.available.length, inputLength);
			if (len == 0)
			{
				eof = !input.fetch();
				if (eof) return;
				len = min(input.available.length, inputLength);
				assert(input.available.length >= 1);
			}
			
			if (len < 3 && len > 0)
			{
				ubyte[3] save;
				
				if (len >= 1) save[0] = input.available[0];
				if (len == 2) save[1] = input.available[1];
				input.consume(len);
				eof = !input.fetch();
				if (eof)
				{
					save[len] = '\x00';
					std.base64.Base64.encode(save[0 .. 3], view = buffer[0 .. 4]);
					if (len <= 2) buffer[3] = Padding;
					if (len == 1) buffer[2] = Padding;
				}
				else
				{
					assert(input.available.length >= 1);
					auto n = 3 - len;
					auto display = input.available;
					if (len <= 2) save[len] = display[0];
					if (len == 1) save[len] = (display.length==1 ? (n=1, '\x00') : display[1]);
					std.base64.Base64.encode(save[0 .. 3], view = buffer[0 .. 4]);
					if (len == 1 && n == 1) buffer[3] = Padding;
					input.consume(n);
				}
			}
			else
			{
				auto num = len / 3;
				len = num * 3;
				std.base64.Base64.encode(input.available[0 .. num*3], view = buffer[0 .. num*4]);
				input.consume(num * 3);
			}
		}
	}
}

/**
encode ranged input
*/
template Base64_3(char Map62th = '+', char Map63th = '/', char Padding = '=')
{
	//debug = Encoder;

	/**
	*/
	Encoder!(Ranged!Input) encoder(Input)(Input input, size_t bufferSize = 2048)
	{
		return Encoder!(Ranged!Input)(ranged(input), bufferSize);
	}

	/**
	*/
	struct Encoder(Input)
		if (isInputRange!Input)
	{
		import std.base64;
	private:
		Input input;
		bool eof;
		char[4] buf;
		char[] view;

		private immutable EncodeMap = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789" ~ Map62th ~ Map63th;

	public:
		this(Input i, size_t bufferSize)
		{
			move(i, input);
			view = buf[0 .. 1];	//hack
			popFront();
		}

		/**
		Interfaces of input range.
		*/
		@property bool empty()
		{
			debug(Encoder) writefln("base64.Encoder.empty, eof = %s", eof);
			return eof;
		}
		
		/// ditto
		@property char front()
		{
			debug(Encoder) writefln("base64.Encoder.front, view.length = %s", view.length);
			debug(Encoder) writefln("base64.Encoder.front, front = %s", view[0]);
			return view[0];
		}
		
		/// ditto
		void popFront()
		{
			view = view[1 .. $];
			if (view.length > 0)
				return;
			
			eof = input.empty;
			if (!eof)
			{
				ubyte[3] cap = void;
				
				void doEncode()
				{
					immutable val = cap[0] << 16 | cap[1] << 8 | cap[2];
					buf[0] = EncodeMap[val >> 18       ];
					buf[1] = EncodeMap[val >> 12 & 0x3f];
					buf[2] = EncodeMap[val >>  6 & 0x3f];
					buf[3] = EncodeMap[val       & 0x3f];
				}
				
				cap[0] = input.front, input.popFront();
				
				if (input.empty)
				{
					cap[1] = '\x00';
					cap[2] = '\x00';
					doEncode();
					buf[2] = Padding;
					buf[3] = Padding;
					goto End;
				}
				
				cap[1] = input.front, input.popFront();
				
				if (input.empty)
				{
					cap[2] = '\x00';
					doEncode();
					buf[3] = Padding;
					goto End;
				}
				
				cap[2] = input.front, input.popFront();
				
				doEncode();
			  End:
				view = buf[];
			}
		}
	}
}

enum ImplKind { CharPool, CharRange, ChunkRange }
/**
encode pre-fetch
buffer-size is expanded automatically
*/
template Base64_4(ImplKind Impl = ImplKind.CharPool)
{
	enum char Map62th = '+';
	enum char Map63th = '/';
	enum char Padding = '=';
	
	//debug = Encoder;

	/**
	*/
	Encoder!Input encoder(Input)(Input input, size_t bufferSize = 2048)
	{
		return Encoder!Input(move(input), bufferSize);
	}

	/**
	*/
	struct Encoder(Input) if (isPool!Input)
	{
		//import std.base64 : StdBase64 = Base64;
	private:
		Input input;
		bool eof;
	  static if (Impl != ImplKind.CharPool)
		bool isempty;
		char[] buf, view;

		private immutable EncodeMap = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789" ~ Map62th ~ Map63th;

	public:
		/**
		Ignore bufferSize
		*/
		this(Input i, size_t bufferSize)
		{
			move(i, input);
		  static if (Impl != ImplKind.CharPool)
			isempty = !fetch();
		}

	static if (Impl == ImplKind.CharPool)
	{
		@property const(char)[] available() const
		{
			return view;
		}
		void consume(size_t n)
		{
			assert(n <= view.length);
			view = view[n .. $];
		}
	}
	else
	{
		/**
		Interfaces of input range.
		*/
		@property bool empty()
		{
			return isempty;
		}
		
	  static if (Impl == ImplKind.CharRange)
	  {
		/// ditto
		@property char front()		{ return view[0]; }
		/// ditto
		void popFront()
		{
			view = view[1 .. $];
		  version (none)
		  {
			if (view.length > 0)
				return;
			isempty = !fetch();
		  }
		  else
		  {
			// -inline -release前提で、こっちのほうが分岐予測ミスが少ない？
			if (view.length == 0)
				isempty = !fetch();
		  }
		}
	  }
	  static if (Impl == ImplKind.ChunkRange)
	  {
		/// ditto
		@property char[] front()	{ return view; }
		/// ditto
		void popFront()				{ isempty = !fetch(); }
	  }
	
	private:
	}
		bool fetch()
		in {
		  static if (Impl == ImplKind.CharPool)
			assert(view.length == 0);
		}
		body
		{
			if (eof) return false;
			
			immutable len = input.available.length;
			if (len < 3 && len > 0)
			{
				ubyte[3] cap;
				buf.length = 4;	// resize buffer;
				
				void doEncode()
				{
					immutable val = cap[0] << 16 | cap[1] << 8 | cap[2];
					buf[0] = EncodeMap[val >> 18       ];
					buf[1] = EncodeMap[val >> 12 & 0x3f];
					buf[2] = EncodeMap[val >>  6 & 0x3f];
					buf[3] = EncodeMap[val       & 0x3f];
				}
				
				cap[0] = input.available[0], input.consume(1);
				if (input.available.length == 0 && (eof = !input.fetch(), eof))
				{
					cap[1] = '\x00';
					cap[2] = '\x00';
					doEncode();
					buf[2] = Padding;
					buf[3] = Padding;
					goto End;
				}
				assert(input.available.length > 0);
				
				cap[1] = input.available[0], input.consume(1);
				if (input.available.length == 0 && (eof = !input.fetch(), eof))
				{
					cap[2] = '\x00';
					doEncode();
					buf[3] = Padding;
					goto End;
				}
				assert(input.available.length > 0);
				
				cap[2] = input.available[0], input.consume(1);
				
				doEncode();
			  End:
				view = buf[];
			}
			else
			{
				if (len == 0)
				{
					eof = !input.fetch();
					if (eof) return false;
				}
				immutable num = input.available.length / 3;
				immutable caplen = num * 3;
				immutable buflen = num * 4;
				if (buf.length < buflen)
					buf.length = buflen;	// resize buffer;
				
			/+
				view = StdBase64.encode(input.available[0 .. caplen], buf[]);
			// +/
			//+
				auto p = input.available.ptr, end = p + caplen;
				auto q = buf.ptr;
				do//foreach (unused; 0 .. num)
				{
					immutable val = ((*p++ << 16) | *p++ << 8) | *p++;
					*q++ = EncodeMap[val >> 18       ];
					*q++ = EncodeMap[val >> 12 & 0x3f];
					*q++ = EncodeMap[val >>  6 & 0x3f];
					*q++ = EncodeMap[val       & 0x3f];
				}
				while (p != end)
				view = buf[];
			// +/
				
				input.consume(caplen);
			}
			return true;
		}
	}
}


//debug = Encoder;

/**
fetch方法について改良案
ChunkRange提供
//Pool I/F提供版←必要なら置き換え可能
*/
template Base64_5(ImplKind Impl = ImplKind.CharPool)
{
	enum char Map62th = '+';
	enum char Map63th = '/';
	enum char Padding = '=';
	
	import std.stdio;

	/**
	*/
	Encoder!Input encoder(Input)(Input input, size_t bufferSize = 2048)
	{
		return Encoder!Input(move(input), bufferSize);
	}

	/**
	*/
	struct Encoder(Input) if (isPool!Input)
	{
		import std.base64 : StdBase64 = Base64;
	private:
		Input input;
		bool eof;
		char[] buf, view;
		ubyte[3] cache; size_t cachelen;
		bool isempty;

	public:
		/**
		Ignore bufferSize
		*/
		this(Input i, size_t bufferSize)
		{
			move(i, input);
			char[4] tmpbuf;	// Range I/Fならここでスタックを使えるが…
			buf = tmpbuf;	// 初期バッファ割り当て
			isempty = !fetch();
			if (buf.ptr == tmpbuf.ptr)
				buf = buf.dup;	// tmpbufを指さないようにコピー
		}

		/**
		Interfaces of input range.
		*/
		@property bool empty()
		{
			return isempty;
		}
		/// ditto
		@property char[] front()
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
		}
	
/+		@property const(char)[] available() const
		{
			return view;
		}
		void consume(size_t n)
		in{ assert(n <= view.length); }
		body
		{
			view = view[n .. $];
		}+/
	private:
		bool fetch()
		in { assert(view.length == 0); }
		body
		{
			if (eof) return false;
			
			assert(buf.length >= 4);
			
			debug(Encoder) writefln("");
			
			// input.fetchの繰り返しによってinput.availableが最低2バイト以上たまることを要求する
			if (cachelen)	// eating cache
			{
				debug(Encoder) writefln("usecache 0: cache = [%(%02X %)]", cache[0..cachelen]);
			  Continue:
				if (input.fetch())
				{
					auto ava = input.available;
					debug(Encoder) writefln("usecache 1: ava.length = %s", ava.length);
					if (cachelen + ava.length >= 3)
					{
						if (cachelen & 1)
						{
							cache[1] = ava[0];
							cache[2] = ava[1];
							StdBase64.encode(cache, buf[0..4]);
							input.consume(2);
						}
						else
						{
							cache[2] = ava[0];
							StdBase64.encode(cache, buf[0..4]);
							input.consume(1);
						}
					}
					else
						goto Continue;
				}
				else
				{
					debug(Encoder) writefln("usecache 2: cachelen = %s", cachelen);
					eof = true;
					if (cachelen & 1)
					{
						cache[1] = 0x00;
						cache[2] = 0x00;
						StdBase64.encode(cache, view = buf[0..4]);
						buf[2] = Padding;
						buf[3] = Padding;
					}
					else
					{
						cache[2] = 0x00;
						StdBase64.encode(cache, view = buf[0..4]);
						buf[3] = Padding;
					}
					view = buf[0..4];
					return true;
				}
			}
			else if (!input.fetch())
			{
				eof = true;
				return false;
			}

			auto ava = input.available;
			immutable capnum = ava.length / 3;
			immutable caplen = capnum * 3;
			immutable buflen = capnum * 4;
			debug(Encoder) writefln(
					"capture1: ava.length = %s, capnum = %s, caplen = %s, buflen = %s+%s",
					ava.length, capnum, caplen, buflen, cachelen ? 4 : 0);
			if (caplen)
			{
				// cachelen!=0 -> has encoded from cache
				auto bs = cachelen ? 4 : 0, be = buflen+bs;
				if (buf.length < be)
					buf.length = be;
				StdBase64.encode(ava[0..caplen], buf[bs..be]);
				view = buf[0 .. be];
			}
			if ((cachelen = ava.length - caplen) != 0)
			{
				if (cachelen & 1)
					cache[0] = ava[$-1];
				else
				{
					cache[0] = ava[$-2];
					cache[1] = ava[$-1];
				}
			}
			input.consume(ava.length);
			debug(Encoder)
				writefln(
					"capture2: view.length = %s, cachelen = %s, ava.length = %s",
					view.length, cachelen, ava.length);
			return true;
		}
	}
}
