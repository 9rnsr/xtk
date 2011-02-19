module device_base64;

public import device;
import std.array, std.algorithm, std.range, std.traits;
alias device.move move;

alias Base64_0!() base64_0;
alias Base64_1!() base64_1;
alias Base64_2!() base64_2;
alias Base64_3!() base64_3;
alias Base64_4!() base64_4;
alias Base64_4x!() base64_4x;
alias Base64_4c!() base64_4c;

/**
encode each chunk (same as std.base64)
*/
template Base64_0(char Map62th = '+', char Map63th = '/', char Padding = '=')
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
		if (isInputPool!Input)
	{
		import std.base64;
	private:
		Input input;
		bool eof;
		char[] buffer;
		char[] view;

		private immutable EncodeMap = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789" ~ Map62th ~ Map63th;

	public:
		/**
		Ignore bufferSize
		*/
		this(Input i, size_t bufferSize)
		{
			move(i, input);
			debug(Encoder) writefln("Bse64_4.Encoder.this, input.available.length = %s", input.available.length);
			fetch();
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
		@property char[] front()
		{
			debug(Encoder) writefln("base64.Encoder.front, view.length = %s", view.length);
			debug(Encoder) writefln("base64.Encoder.front, front = %s", view[0]);
			return view;//[0];
		}
		
		/// ditto
		void popFront()
		{
		//	view = view[1 .. $];
		//	if (view.length > 0)
		//		return;
			
			fetch();
		}
	
	private:
		void fetch()
		{
			if (input.fetch())
			{
				auto data = input.available;
				auto size = encodeLength(data.length);
				//writefln("data.length = %s, size = %s", data.length, size);
				if (size > buffer.length)
					buffer.length = size;
				
				view = encode(data, buffer);
				//assert(view.length > 0);
				input.consume(data.length);
			}
			else
				eof = true;
		}

	    enum NoPadding = '\0';  /// represents no-padding encoding

	    /**
	     * Calculates the minimum length for encoding.
	     *
	     * Params:
	     *  sourceLength = the length of source array.
	     *
	     * Returns:
	     *  the calculated length using $(D_PARAM sourceLength).
	     */
	    @safe
	    pure nothrow size_t encodeLength(in size_t sourceLength)
	    {
	        static if (Padding == NoPadding)
	            return (sourceLength / 3) * 4 + (sourceLength % 3 == 0 ? 0 : sourceLength % 3 == 1 ? 2 : 3);
	        else
	            return (sourceLength / 3 + (sourceLength % 3 ? 1 : 0)) * 4;
	    }

	    /**
	     * Encodes $(D_PARAM source) into $(D_PARAM buffer).
	     *
	     * Params:
	     *  source = an $(D InputRange) to encode.
	     *  range  = a buffer to store encoded result.
	     *
	     * Returns:
	     *  the encoded string that slices buffer.
	     */
	    @trusted
	    pure char[] encode(R1, R2)(in R1 source, R2 buffer) if (isArray!R1 && is(ElementType!R1 : ubyte) &&
	                                                            is(R2 == char[]))
	    in
	    {
	        assert(buffer.length >= encodeLength(source.length), "Insufficient buffer for encoding");
	    }
	    out(result)
	    {
	        assert(result.length == encodeLength(source.length), "The length of result is different from Base64");
	    }
	    body
	    {
	        immutable srcLen = source.length;
	        if (srcLen == 0)
	            return [];

	        immutable blocks = srcLen / 3;
	        immutable remain = srcLen % 3;
	        auto      bufptr = buffer.ptr;
	        auto      srcptr = source.ptr;

	        foreach (Unused; 0..blocks) {
	            immutable val = srcptr[0] << 16 | srcptr[1] << 8 | srcptr[2];
	            *bufptr++ = EncodeMap[val >> 18       ];
	            *bufptr++ = EncodeMap[val >> 12 & 0x3f];
	            *bufptr++ = EncodeMap[val >>  6 & 0x3f];
	            *bufptr++ = EncodeMap[val       & 0x3f];
	            srcptr += 3;
	        }

	        if (remain) {
	            immutable val = srcptr[0] << 16 | (remain == 2 ? srcptr[1] << 8 : 0);
	            *bufptr++ = EncodeMap[val >> 18       ];
	            *bufptr++ = EncodeMap[val >> 12 & 0x3f];

	            final switch (remain) {
	            case 2:
	                *bufptr++ = EncodeMap[val >> 6 & 0x3f];
	                static if (Padding != NoPadding)
	                    *bufptr++ = Padding;
	                break;
	            case 1:
	                static if (Padding != NoPadding) {
	                    *bufptr++ = Padding;
	                    *bufptr++ = Padding;
	                }
	                break;
	            }
	        }

	        // encode method can't assume buffer length. So, slice needed.
	        return buffer[0..bufptr - buffer.ptr];
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
		if (isInputPool!Input)
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
			debug(Encoder) writefln("base64.Encoder.front, pos = %s", pos);
			debug(Encoder) writefln("base64.Encoder.front, front = %s", encoded[pos]);
			return encoded[pos];
		}
		
		/// ditto
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
		if (isInputPool!Input)
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

/**
encode pre-fetch
buffer-size is expanded automatically
*/
template Base64_4(char Map62th = '+', char Map63th = '/', char Padding = '=')
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
		if (isInputPool!Input)
	{
		import std.base64;
	private:
		Input input;
		bool eof;
		char[] buf;
		char[] view;

		private immutable EncodeMap = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789" ~ Map62th ~ Map63th;

	public:
		/**
		Ignore bufferSize
		*/
		this(Input i, size_t bufferSize)
		{
			move(i, input);
			debug(Encoder) writefln("Bse64_4.Encoder.this, input.available.length = %s", input.available.length);
			fetch();
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
			
			fetch();
		}
	
	private:
		void fetch()
		{
			auto len = input.available.length;
			if (len < 3 && len > 0)
			{
				debug(Encoder) writefln("fetch() a, input.available.length = %s, len = %s", input.available.length, len);
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
				debug(Encoder) writefln("fetch() b, input.available.length = %s, len = %s", input.available.length, len);
				if (input.available.length == 0 && (eof = !input.fetch(), eof))
				{
					debug(Encoder) writefln("fetch() b1, input.available.length = %s, len = %s", input.available.length, len);
					cap[1] = '\x00';
					cap[2] = '\x00';
					doEncode();
					buf[2] = Padding;
					buf[3] = Padding;
					goto End;
				}
				assert(input.available.length > 0);
				
				cap[1] = input.available[0], input.consume(1);
				debug(Encoder) writefln("fetch() c, input.available.length = %s, len = %s", input.available.length, len);
				if (input.available.length == 0 && (eof = !input.fetch(), eof))
				{
					debug(Encoder) writefln("fetch() c1, input.available.length = %s, len = %s", input.available.length, len);
					cap[2] = '\x00';
					doEncode();
					buf[3] = Padding;
					goto End;
				}
				assert(input.available.length > 0);
				
				cap[2] = input.available[0], input.consume(1);
				debug(Encoder) writefln("fetch() d, input.available.length = %s, len = %s", input.available.length, len);
				
				doEncode();
			  End:
				;
			}
			else
			{
				size_t num = void;
				debug(Encoder) writefln("fetch() 1, input.available.length = %s, len = %s", input.available.length, len);
				if (len == 0)
				{
					eof = !input.fetch();
					if (eof) return;
				}
				buf.length = (num = input.available.length / 3) * 4;	// resize buffer;
				len = num * 3;
				debug(Encoder) writefln("fetch() 2, input.available.length = %s, len = %s", input.available.length, len);
				
			/+
				encode(input.available[0 .. len], buf[]);
			// +/
			/+
				std.base64.Base64.encode(input.available[0 .. len], buf[]);
			// +/
			//+
				auto p = input.available.ptr, end = p + len;
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
			// +/
				
				input.consume(len);
				debug(Encoder) writefln("fetch() 3, input.available.length = %s, len = %s", input.available.length, len);
			}
			view = buf[];
		}

	    enum NoPadding = '\0';  /// represents no-padding encoding

	    /**
	     * Calculates the minimum length for encoding.
	     *
	     * Params:
	     *  sourceLength = the length of source array.
	     *
	     * Returns:
	     *  the calculated length using $(D_PARAM sourceLength).
	     */
	    @safe
	    pure nothrow size_t encodeLength(in size_t sourceLength)
	    {
	        static if (Padding == NoPadding)
	            return (sourceLength / 3) * 4 + (sourceLength % 3 == 0 ? 0 : sourceLength % 3 == 1 ? 2 : 3);
	        else
	            return (sourceLength / 3 + (sourceLength % 3 ? 1 : 0)) * 4;
	    }

	    /**
	     * Encodes $(D_PARAM source) into $(D_PARAM buffer).
	     *
	     * Params:
	     *  source = an $(D InputRange) to encode.
	     *  range  = a buffer to store encoded result.
	     *
	     * Returns:
	     *  the encoded string that slices buffer.
	     */
	    @trusted
	    pure char[] encode(R1, R2)(in R1 source, R2 buffer) if (isArray!R1 && is(ElementType!R1 : ubyte) &&
	                                                            is(R2 == char[]))
	    in
	    {
	        assert(buffer.length >= encodeLength(source.length), "Insufficient buffer for encoding");
	    }
	    out(result)
	    {
	        assert(result.length == encodeLength(source.length), "The length of result is different from Base64");
	    }
	    body
	    {
	        immutable srcLen = source.length;
	        if (srcLen == 0)
	            return [];

	        immutable blocks = srcLen / 3;
	        immutable remain = srcLen % 3;
	        auto      bufptr = buffer.ptr;
	        auto      srcptr = source.ptr;

	        foreach (Unused; 0..blocks) {
	            immutable val = srcptr[0] << 16 | srcptr[1] << 8 | srcptr[2];
	            *bufptr++ = EncodeMap[val >> 18       ];
	            *bufptr++ = EncodeMap[val >> 12 & 0x3f];
	            *bufptr++ = EncodeMap[val >>  6 & 0x3f];
	            *bufptr++ = EncodeMap[val       & 0x3f];
	            srcptr += 3;
	        }

	        if (remain) {
	            immutable val = srcptr[0] << 16 | (remain == 2 ? srcptr[1] << 8 : 0);
	            *bufptr++ = EncodeMap[val >> 18       ];
	            *bufptr++ = EncodeMap[val >> 12 & 0x3f];

	            final switch (remain) {
	            case 2:
	                *bufptr++ = EncodeMap[val >> 6 & 0x3f];
	                static if (Padding != NoPadding)
	                    *bufptr++ = Padding;
	                break;
	            case 1:
	                static if (Padding != NoPadding) {
	                    *bufptr++ = Padding;
	                    *bufptr++ = Padding;
	                }
	                break;
	            }
	        }

	        // encode method can't assume buffer length. So, slice needed.
	        return buffer[0..bufptr - buffer.ptr];
	    }
	}
}

/**
encode pre-fetch + chunked range
buffer-size is expanded automatically
*/
template Base64_4x(char Map62th = '+', char Map63th = '/', char Padding = '=')
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
		if (isInputPool!Input)
	{
		import std.base64;
	private:
		Input input;
		bool eof;
		char[] buf;
		char[] view;

		private immutable EncodeMap = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789" ~ Map62th ~ Map63th;

	public:
		/**
		Ignore bufferSize
		*/
		this(Input i, size_t bufferSize)
		{
			move(i, input);
			debug(Encoder) writefln("Bse64_4.Encoder.this, input.available.length = %s", input.available.length);
			fetch();
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
		@property char[] front()
		{
			debug(Encoder) writefln("base64.Encoder.front, view.length = %s", view.length);
			debug(Encoder) writefln("base64.Encoder.front, front = %s", view[0]);
			return view;//[0];
		}
		
		/// ditto
		void popFront()
		{
		//	view = view[1 .. $];
		//	if (view.length > 0)
		//		return;
			
			fetch();
		}
	
	private:
		void fetch()
		{
			immutable len = input.available.length;
			if (len < 3 && len > 0)
			{
				debug(Encoder) writefln("fetch() a, input.available.length = %s, len = %s", input.available.length, len);
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
				debug(Encoder) writefln("fetch() b, input.available.length = %s, len = %s", input.available.length, len);
				if (input.available.length == 0 && (eof = !input.fetch(), eof))
				{
					debug(Encoder) writefln("fetch() b1, input.available.length = %s, len = %s", input.available.length, len);
					cap[1] = '\x00';
					cap[2] = '\x00';
					doEncode();
					buf[2] = Padding;
					buf[3] = Padding;
					goto End;
				}
				assert(input.available.length > 0);
				
				cap[1] = input.available[0], input.consume(1);
				debug(Encoder) writefln("fetch() c, input.available.length = %s, len = %s", input.available.length, len);
				if (input.available.length == 0 && (eof = !input.fetch(), eof))
				{
					debug(Encoder) writefln("fetch() c1, input.available.length = %s, len = %s", input.available.length, len);
					cap[2] = '\x00';
					doEncode();
					buf[3] = Padding;
					goto End;
				}
				assert(input.available.length > 0);
				
				cap[2] = input.available[0], input.consume(1);
				debug(Encoder) writefln("fetch() d, input.available.length = %s, len = %s", input.available.length, len);
				
				doEncode();
			  End:
				view = buf[];
			}
			else
			{
				debug(Encoder) writefln("fetch() 1, input.available.length = %s, len = %s", input.available.length, len);
				if (len == 0)
				{
					eof = !input.fetch();
					if (eof) return;
				}
				immutable num = input.available.length / 3;
				immutable caplen = num * 3;
				immutable buflen = num * 4;
				if (buf.length < buflen)
					buf.length = buflen;	// resize buffer;
				debug(Encoder) writefln("fetch() 2, input.available.length = %s, len = %s", input.available.length, buflen);
				
			//+
				view = encode(input.available[0 .. caplen], buf[]);
			// +/
			/+
				view = std.base64.Base64.encode(input.available[0 .. len], buf[]);
			// +/
			/+
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
				debug(Encoder) writefln("fetch() 3, input.available.length = %s, caplen = %s", input.available.length, caplen);
			}
		}

	    enum NoPadding = '\0';  /// represents no-padding encoding

	    /**
	     * Calculates the minimum length for encoding.
	     *
	     * Params:
	     *  sourceLength = the length of source array.
	     *
	     * Returns:
	     *  the calculated length using $(D_PARAM sourceLength).
	     */
	    @safe
	    pure nothrow size_t encodeLength(in size_t sourceLength)
	    {
	        static if (Padding == NoPadding)
	            return (sourceLength / 3) * 4 + (sourceLength % 3 == 0 ? 0 : sourceLength % 3 == 1 ? 2 : 3);
	        else
	            return (sourceLength / 3 + (sourceLength % 3 ? 1 : 0)) * 4;
	    }

	    /**
	     * Encodes $(D_PARAM source) into $(D_PARAM buffer).
	     *
	     * Params:
	     *  source = an $(D InputRange) to encode.
	     *  range  = a buffer to store encoded result.
	     *
	     * Returns:
	     *  the encoded string that slices buffer.
	     */
	    @trusted
	    pure char[] encode(R1, R2)(in R1 source, R2 buffer) if (isArray!R1 && is(ElementType!R1 : ubyte) &&
	                                                            is(R2 == char[]))
	    in
	    {
	        assert(buffer.length >= encodeLength(source.length), "Insufficient buffer for encoding");
	    }
	    out(result)
	    {
	        assert(result.length == encodeLength(source.length), "The length of result is different from Base64");
	    }
	    body
	    {
	        immutable srcLen = source.length;
	        if (srcLen == 0)
	            return [];

	        immutable blocks = srcLen / 3;
	        immutable remain = srcLen % 3;
	        auto      bufptr = buffer.ptr;
	        auto      srcptr = source.ptr;

	        foreach (Unused; 0..blocks) {
	            immutable val = srcptr[0] << 16 | srcptr[1] << 8 | srcptr[2];
	            *bufptr++ = EncodeMap[val >> 18       ];
	            *bufptr++ = EncodeMap[val >> 12 & 0x3f];
	            *bufptr++ = EncodeMap[val >>  6 & 0x3f];
	            *bufptr++ = EncodeMap[val       & 0x3f];
	            srcptr += 3;
	        }

	        if (remain) {
	            immutable val = srcptr[0] << 16 | (remain == 2 ? srcptr[1] << 8 : 0);
	            *bufptr++ = EncodeMap[val >> 18       ];
	            *bufptr++ = EncodeMap[val >> 12 & 0x3f];

	            final switch (remain) {
	            case 2:
	                *bufptr++ = EncodeMap[val >> 6 & 0x3f];
	                static if (Padding != NoPadding)
	                    *bufptr++ = Padding;
	                break;
	            case 1:
	                static if (Padding != NoPadding) {
	                    *bufptr++ = Padding;
	                    *bufptr++ = Padding;
	                }
	                break;
	            }
	        }

	        // encode method can't assume buffer length. So, slice needed.
	        return buffer[0..bufptr - buffer.ptr];
	    }
	}
}

/**
encode pre-fetch + chunked range
buffer-size is expanded automatically
*/
template Base64_4c(char Map62th = '+', char Map63th = '/', char Padding = '=')
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
		if (isInputPool!Input)
	{
		import std.base64;
	private:
		Input input;
		bool eof;
		char[] buf;
		char[] view;

		private immutable EncodeMap = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789" ~ Map62th ~ Map63th;

	public:
		/**
		Ignore bufferSize
		*/
		this(Input i, size_t bufferSize)
		{
			move(i, input);
			debug(Encoder) writefln("Bse64_4.Encoder.this, input.available.length = %s", input.available.length);
			fetch();
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
			
			fetch();
		}
	
	private:
		void fetch()
		{
			immutable len = input.available.length;
			if (len < 3 && len > 0)
			{
				debug(Encoder) writefln("fetch() a, input.available.length = %s, len = %s", input.available.length, len);
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
				debug(Encoder) writefln("fetch() b, input.available.length = %s, len = %s", input.available.length, len);
				if (input.available.length == 0 && (eof = !input.fetch(), eof))
				{
					debug(Encoder) writefln("fetch() b1, input.available.length = %s, len = %s", input.available.length, len);
					cap[1] = '\x00';
					cap[2] = '\x00';
					doEncode();
					buf[2] = Padding;
					buf[3] = Padding;
					goto End;
				}
				assert(input.available.length > 0);
				
				cap[1] = input.available[0], input.consume(1);
				debug(Encoder) writefln("fetch() c, input.available.length = %s, len = %s", input.available.length, len);
				if (input.available.length == 0 && (eof = !input.fetch(), eof))
				{
					debug(Encoder) writefln("fetch() c1, input.available.length = %s, len = %s", input.available.length, len);
					cap[2] = '\x00';
					doEncode();
					buf[3] = Padding;
					goto End;
				}
				assert(input.available.length > 0);
				
				cap[2] = input.available[0], input.consume(1);
				debug(Encoder) writefln("fetch() d, input.available.length = %s, len = %s", input.available.length, len);
				
				doEncode();
			  End:
				view = buf[];
			}
			else
			{
				debug(Encoder) writefln("fetch() 1, input.available.length = %s, len = %s", input.available.length, len);
				if (len == 0)
				{
					eof = !input.fetch();
					if (eof) return;
				}
				immutable num = input.available.length / 3;
				immutable caplen = num * 3;
				immutable buflen = num * 4;
				if (buf.length < buflen)
					buf.length = buflen;	// resize buffer;
				debug(Encoder) writefln("fetch() 2, input.available.length = %s, len = %s", input.available.length, buflen);
				
			//+
				view = encode(input.available[0 .. caplen], buf[]);
			// +/
			/+
				view = std.base64.Base64.encode(input.available[0 .. len], buf[]);
			// +/
			/+
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
				debug(Encoder) writefln("fetch() 3, input.available.length = %s, caplen = %s", input.available.length, caplen);
			}
		}

	    enum NoPadding = '\0';  /// represents no-padding encoding

	    /**
	     * Calculates the minimum length for encoding.
	     *
	     * Params:
	     *  sourceLength = the length of source array.
	     *
	     * Returns:
	     *  the calculated length using $(D_PARAM sourceLength).
	     */
	    @safe
	    pure nothrow size_t encodeLength(in size_t sourceLength)
	    {
	        static if (Padding == NoPadding)
	            return (sourceLength / 3) * 4 + (sourceLength % 3 == 0 ? 0 : sourceLength % 3 == 1 ? 2 : 3);
	        else
	            return (sourceLength / 3 + (sourceLength % 3 ? 1 : 0)) * 4;
	    }

	    /**
	     * Encodes $(D_PARAM source) into $(D_PARAM buffer).
	     *
	     * Params:
	     *  source = an $(D InputRange) to encode.
	     *  range  = a buffer to store encoded result.
	     *
	     * Returns:
	     *  the encoded string that slices buffer.
	     */
	    @trusted
	    pure char[] encode(R1, R2)(in R1 source, R2 buffer) if (isArray!R1 && is(ElementType!R1 : ubyte) &&
	                                                            is(R2 == char[]))
	    in
	    {
	        assert(buffer.length >= encodeLength(source.length), "Insufficient buffer for encoding");
	    }
	    out(result)
	    {
	        assert(result.length == encodeLength(source.length), "The length of result is different from Base64");
	    }
	    body
	    {
	        immutable srcLen = source.length;
	        if (srcLen == 0)
	            return [];

	        immutable blocks = srcLen / 3;
	        immutable remain = srcLen % 3;
	        auto      bufptr = buffer.ptr;
	        auto      srcptr = source.ptr;

	        foreach (Unused; 0..blocks) {
	            immutable val = srcptr[0] << 16 | srcptr[1] << 8 | srcptr[2];
	            *bufptr++ = EncodeMap[val >> 18       ];
	            *bufptr++ = EncodeMap[val >> 12 & 0x3f];
	            *bufptr++ = EncodeMap[val >>  6 & 0x3f];
	            *bufptr++ = EncodeMap[val       & 0x3f];
	            srcptr += 3;
	        }

	        if (remain) {
	            immutable val = srcptr[0] << 16 | (remain == 2 ? srcptr[1] << 8 : 0);
	            *bufptr++ = EncodeMap[val >> 18       ];
	            *bufptr++ = EncodeMap[val >> 12 & 0x3f];

	            final switch (remain) {
	            case 2:
	                *bufptr++ = EncodeMap[val >> 6 & 0x3f];
	                static if (Padding != NoPadding)
	                    *bufptr++ = Padding;
	                break;
	            case 1:
	                static if (Padding != NoPadding) {
	                    *bufptr++ = Padding;
	                    *bufptr++ = Padding;
	                }
	                break;
	            }
	        }

	        // encode method can't assume buffer length. So, slice needed.
	        return buffer[0..bufptr - buffer.ptr];
	    }
	}
}


