import std.perf;
import core.stdc.stdio;

/+void main()
{
	auto pc = new PerformanceCounter;

	pc.start;
	size_t nlines = 0;
	foreach (i; 0 .. 1000)
	{
		auto file = File!(IODirection.input)(__FILE__);
		auto uport = openUTF8TextInputPort(file);

		foreach (line; uport.byLine)
			line.dup, ++nlines;
	}
	pc.stop;

	printf("%g line/sec\n", nlines / (1.e-6 * pc.microseconds));
}+/


//----------------------------------------------------------------------------//

import std.algorithm;
import std.array;
import std.conv;
import std.range;
import std.string : toStringz;
import std.typetuple, std.utf;

import core.stdc.errno;
import core.stdc.stdio;

version(Posix)
{
	import core.sys.posix.fcntl;
	import core.sys.posix.unistd;
}
version(Windows)
{
	import core.sys.windows.windows;
}


enum IODirection
{
	input,
	output,
	both,
}


//version (Posix)
@system struct File(IODirection direction_)
{
	this(in char[] path)
	{
	  version(Posix)
		static immutable int[IODirection.max + 1] MODE =
			[
				IODirection.input : O_RDONLY,
				IODirection.output: O_WRONLY,
				IODirection.both  : O_RDWR
			];
	  version(Windows)
	  	static immutable int[IODirection.max + 1] MODE =
			[
				IODirection.input : GENERIC_READ,
				IODirection.output: GENERIC_WRITE,
				IODirection.both  : GENERIC_READ | GENERIC_WRITE
			];

		context_		= new Context;
		version (Posix)
		{
			context_.handle = .open(path.toStringz(), MODE[direction_]);
			if (context_.handle < 0)
			{
				switch (errno)
				{
				  default:
					throw new Exception("open");
				}
				assert(0);
			}
		}
		version(Windows)
		{
			alias TypeTuple!(MODE[direction_],
					FILE_SHARE_READ, (SECURITY_ATTRIBUTES*).init, OPEN_EXISTING,
					FILE_ATTRIBUTE_NORMAL | FILE_FLAG_SEQUENTIAL_SCAN,
					HANDLE.init)
				defaults;
			context_.handle = CreateFileW(path.toUTF16z(), defaults);
			if (context_.handle == INVALID_HANDLE_VALUE)
			{
				switch(GetLastError())
				{
					default:
					throw new Exception("open");
				}
				assert(0);
			}
		}
	}

	this(this)
	{
		if (context_)
			++context_.refCount;
	}

	~this()
	{
		if (context_ && --context_.refCount == 0)
			close();
	}


	//----------------------------------------------------------------//
	// Device Handle Primitives
	//----------------------------------------------------------------//

	/*
	 *
	 */
	@property bool isOpen() const nothrow
	{
		version(Posix)
			return context_ && context_.handle >= 0;
		version(Windows)
			return context_ && context_.handle != HANDLE.init;
	}


	/*
	 *
	 */
	void close()
	{
		version(Posix)
		{
			// Lock
			if (context_.handle != -1)
			{
				while (.close(context_.handle) == -1)
				{
					switch (errno)
					{
					  case EINTR:
						continue;

					  default:
						throw new Exception("close");
					}
					assert(0);
				}
				context_.handle = -1;
				context_		= null;
			}
		}
		version(Windows)
		{
			if (context_.handle != INVALID_HANDLE_VALUE)
			{
				if(!CloseHandle(context_.handle))
				{
					switch (GetLastError())
					{
				//	  case ERROR_INVALID_HANDLE:
				//		break;

					  default:
						throw new Exception("close");
					}
					assert(0);
				}
				context_.handle = INVALID_HANDLE_VALUE;
				context_		= null;
			}
		}
	}


	//----------------------------------------------------------------//
	// IO Device Primitives
	//----------------------------------------------------------------//

  static if ( direction_ == IODirection.input ||
			  direction_ == IODirection.both )
	size_t read(ubyte[] buffer)
	{
		version(Posix)
		{
			// Lock
			ssize_t bytesRead;

			while ((bytesRead = .read(context_.handle, buffer.ptr, buffer.length)) == -1)
			{
				switch (errno)
				{
				  case EINTR:
					continue;

				  default:
					throw new Exception("read");
				}
				assert(0);
			}
			return to!size_t(bytesRead);
		}
		version(Windows)
		{
		    DWORD numread = void;
			if (ReadFile(context_.handle, buffer.ptr, buffer.length, &numread, null) != 1)
				throw new Exception("read");
			return to!size_t(numread);
		}
	}

	/*
	 * Writes upto $(D buffer.length) bytes of data from $(D buffer).
	 */
  static if ( direction_ == IODirection.output ||
			  direction_ == IODirection.both )
	size_t write(in ubyte[] buffer)
	{
		version(Posix)
		{
			// Lock
			ssize_t bytesWritten;

			while ((bytesWritten = .write(context_.handle, buffer.ptr, buffer.length)) == -1)
			{
				switch (errno)
				{
				  case EINTR:
					continue;

				  default:
					throw new Exception("write");
				}
				assert(0);
			}
			return to!size_t(bytesWritten);
		}
		version(Windows)
		{
			DWORD numwritten = void;
			if (WriteFile(context_.handle, buffer.ptr, buffer.length, &numwritten, null) != 1 || buffer.length != numwritten)
				throw new Exception("write");
			return to!size_t(numwritten);
		}
	}


	//----------------------------------------------------------------//
	// Seekable Device Primitives
	//----------------------------------------------------------------//

	/*
	 *
	 */
	void seek(long pos, bool relative = false)
	{
		version(Posix)
		{
			immutable whence = (relative ? SEEK_CUR : SEEK_SET);

			if (.lseek(context_.handle, to!fpos_t(pos), SEEK_SET) == -1)
			{
				switch (errno)
				{
				  case EOVERFLOW:
					throw new Exception("seek overflow");

				  default:
					throw new Exception("seek");
				}
				assert(0);
			}
		}
		version(Windows)
		{
			immutable whence = (relative ? FILE_CURRENT : FILE_BEGIN);
			
			int hi = cast(int)(pos >> 32);
			int lo = cast(int)cast(uint)(pos);
			auto ret = SetFilePointer(context_.handle, lo, &hi, whence);
			if (ret == INVALID_SET_FILE_POINTER)
			{
				switch(GetLastError())
				{
				  default:
					throw new Exception("seek");
				}
				assert(0);
			}
		}
	}


	/*
	 *
	 */
	@property ulong position() const
	{
		version(Posix)
		{
			immutable pos = .lseek(context_.handle, 0, SEEK_CUR);
			if (pos == -1)
			{
				switch (errno)
				{
				  default:
					throw new Exception("position");
				}
				assert(0);
			}
			return to!ulong(pos);
		}
		version(Windows)
		{
			return 0;
		}
	}


	/*
	 * Returns the size of the file.
	 */
	@property ulong size() const
	{
		version(Posix)
		{
			immutable orig = .lseek(context_.handle, 0, SEEK_CUR);
			immutable size = .lseek(context_.handle, 0, SEEK_END);
			if (size == -1 || .lseek(context_.handle, orig, SEEK_SET) == -1)
			{
				switch (errno)
				{
				  default:
					throw new Exception("size");
				}
				assert(0);
			}
			return to!ulong(size);
		}
		version(Windows)
		{
			return 0;
		}
	}


	//----------------------------------------------------------------//
private:
	struct Context
	{
		version(Posix)		int handle;
		version(Windows)	HANDLE handle;
		int refCount = 1;
	}
	Context* context_;
}


//----------------------------------------------------------------------------//

/*
 * Mixin to implement lazy input range
 */
template implementLazyInput(E)
{
	@property bool empty()
	{
		if (context_.wantNext)
			popFrontLazy();
		return context_.empty;
	}

	@property ref E front()
	{
		if (context_.wantNext)
			popFrontLazy();
		return context_.front;
	}

	void popFront()
	{
		if (context_.wantNext)
			popFrontLazy();
		context_.wantNext = true;
	}

private:
	void reset()
	{
		context_ = new Context;
	}

	void popFrontLazy()
	{
		context_.wantNext = false;
		context_.empty	  = !readNext(context_.front);
	}

	struct Context
	{
		E	 front;
		bool empty;
		bool wantNext = true;
	}
	Context* context_;
}

unittest
{
	static struct Test
	{
		private int max_;

		this(int max)
		{
			max_ = max;
			reset();
		}

		mixin implementLazyInput!(int);

		private bool readNext(ref int front)
		{
			if (max_ < 0)
				return false;
			front = --max_;
			return true;
		}
	}
	auto r = Test(4);
	assert(r.front == 3); r.popFront;
	assert(r.front == 2); r.popFront;
	assert(r.front == 1); r.popFront;
	assert(r.front == 0); r.popFront;
	assert(r.empty);
}


//----------------------------------------------------------------------------//

BinaryPort!Device openBinaryPort(Device)(Device device, size_t bufferSize = 4096)
{
	return typeof(return)(device, bufferSize);
}

struct BinaryPort(Device)
{
	this(Device device, size_t bufferSize)
	{
		context_		= new Context;
		context_.buffer = new ubyte[](bufferSize);
		swap(device_, device);
	}

	void opAssign(typeof(this) rhs)
	{
		swap(this, rhs);
	}


	//----------------------------------------------------------------//

	@property ByVariableChunk byVariableChunk()
	{
		return ByVariableChunk(this);
	}

	struct ByVariableChunk
	{
		private this(BinaryPort port)
		{
			reset();
			swap(port_, port);
		}

		void opAssign(typeof(this) rhs)
		{
			swap(this, rhs);
		}

		// implement input range primitives
		mixin implementLazyInput!(ubyte[]);

	private:
		bool readNext(ref ubyte[] front)
		{
			with (*port_.context_)
			{
				if (bufferStart == bufferEnd)
				{
					if (!port_.fetch())
						return false;
				}
				front		= buffer[bufferStart .. bufferEnd];
				bufferStart = bufferEnd;
			}
			return true;
		}

		BinaryPort port_;
	}


	//----------------------------------------------------------------//

	void readExact(ubyte[] store)
	{
		with (*context_)
		{
			if (store.length < bufferRem)
			{
				store[] = buffer[bufferStart .. bufferStart + store.length];
				return;
			}

			store[0 .. bufferRem] = buffer[bufferStart .. bufferEnd];
			store				  = store[bufferRem .. $];
			bufferStart = bufferEnd;

			while (store.length > 0)
				store = store[device_.read(store) .. $];
		}
	}

	T readValue(T)()
	{
		T store = void;
		readExact((cast(ubyte*) &store)[0 .. store.sizeof]);
		return store;
	}


	//----------------------------------------------------------------//
private:

	@property size_t bufferRem() const nothrow
	{
		return context_.bufferEnd - context_.bufferStart;
	}

	bool fetch()
	in
	{
		assert(bufferRem == 0);
	}
	body
	{
		with (*context_)
		{
			bufferEnd	= device_.read(buffer);
			bufferStart = 0;
			return bufferEnd > 0;
		}
	}


	//----------------------------------------------------------------//
private:
	static struct Context
	{
		ubyte[] buffer;
		size_t	bufferStart;
		size_t	bufferEnd;
	}
	Device	 device_;
	Context* context_;
}


//----------------------------------------------------------------------------//

UTF8TextInputPort!Device openUTF8TextInputPort(Device)(Device device, size_t bufferSize = 2048)
{
	return typeof(return)(device, bufferSize);
}

@system struct UTF8TextInputPort(Device)
{
	private this(Device device, size_t bufferSize)
	{
		context_		= new Context;
		context_.buffer = new ubyte[](bufferSize);
		swap(device_, device);
	}

	void opAssign(typeof(this) rhs)
	{
		swap(this, rhs);
	}


	//----------------------------------------------------------------//

	@property ByLine byLine(string terminator = "\n")
	{
		return ByLine(this, terminator);
	}

	struct ByLine
	{
		private this(UTF8TextInputPort port, string terminator)
		{
			reset();
			terminator_ = terminator;
			swap(port_, port);
		}

		void opAssign(typeof(this) rhs)
		{
			swap(this, rhs);
		}

		mixin implementLazyInput!(const(char)[]);

	private:
		bool readNext(ref const(char)[] front)
		{
			char[] line  = null;
			size_t match = 0;

			with (*port_.context_) for (size_t cursor = bufferStart; ; ++cursor)
			{
				if (cursor == bufferEnd)
				{
					// The terminator was not found in the current buffer.

					// Concatenate the current buffer content to the result
					// string buffer (line) anyway.
					auto partial = cast(char[]) buffer[bufferStart .. cursor];

					if (line.empty)
						line  = partial.dup;
					else
						line ~= partial;

					if (!port_.fetchNew())
						break; // EOF
					cursor = bufferStart;
				}

				assert(cursor <= bufferEnd);
				assert(match <= terminator_.length);

				if (buffer[cursor] == terminator_[match])
					++match;
				else
					match = 0;

				if (match == terminator_.length)
				{
					auto partial = cast(char[]) buffer[bufferStart .. cursor];

					if (line.empty)
						line  = partial;
					else
						line ~= partial;

					// Chop the line out of the buffer.
					bufferStart = cursor + 1;
					break;
				}
			}
			return (front = line) !is null;
		}

		UTF8TextInputPort port_;
		string			  terminator_;
	}


	//----------------------------------------------------------------//
private:

	@property size_t bufferRem() const nothrow
	{
		return context_.bufferEnd - context_.bufferStart;
	}

	bool fetch()
	in
	{
		assert(bufferRem == 0);
	}
	body
	{
		with (*context_)
		{
			bufferEnd	= device_.read(buffer);
			bufferStart = 0;
			return bufferEnd > 0;
		}
	}

	bool fetchNew()
	{
		with (*context_)
		{
			bufferStart = bufferEnd;
		}
		return fetch();
	}


	//----------------------------------------------------------------//
private:
	static struct Context
	{
		ubyte[] buffer;
		size_t	bufferStart;
		size_t	bufferEnd;
	}
	Device	 device_;
	Context* context_;
}


