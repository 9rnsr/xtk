module xtk.format;

import xtk.device;
import std.array : appender;
import std.format : formattedWrite;
import std.range;
import std.traits;

/**
This may improvement of std.string.format.
*/
string format(Char, A...)(in Char[] fmt, A args)
{
    auto writer = appender!string();
    formattedWrite(writer, fmt, args);
	return writer.data;
}
unittest
{
	scope(failure) std.stdio.writefln("unittest@%s:%s failed", __FILE__, __LINE__);
	
	auto s = format("%(%02X %)", [1,2,3]);
	assert(s == "01 02 03");
}


AppenderLn!Sink appenderLn(Sink)(Sink sink)
{
	return AppenderLn!Sink(sink);
}

template AppenderLn(Sink)
	if (isOutputRange!(Sink, ubyte) ||
		isOutputRange!(Sink, char) ||
		isOutputRange!(Sink, wchar) ||
		isOutputRange!(Sink, dchar))
{
	version (Posix)
	{
		alias Sink AppenderLn;
	}
	else
	{
		struct AppenderLn
		{
			Sink sink;
			bool cr;
			
			this(Sink s)
			{
				move(s, sink);
			}
			
			void put(E)(E e) if (is(Unqual!E == char))//if (is(E : const(dchar)))
			{
				if (e == '\n')
				{
					version (Windows)
					{
						sink.put(cast(ubyte)'\r');
						sink.put(cast(ubyte)'\n');
					}
					else version (OSX)
					{
						sink.put(cast(ubyte)'\r');
					}
				}
				else
				{
					sink.put(cast(ubyte)e);
				}
			}
			void put(E)(E[] data) if (is(Unqual!E == char))//if (is(E : const(dchar)))
			{
				foreach (e; data)
					put(e);
			}
		}
	}
}

void writef(Sink, A...)(ref Sink sink, string fmt, A args)
{
  static if (isOutputRange!(Sink, dchar))
	auto r = appenderLn(sink);
  else static if (isSink!(Sink, dchar))
	auto r = appenderLn(ranged(sink));
  else static if (isSink!(Sink, ubyte))
	auto r = appenderLn(ranged(sink));
  else
	static assert(0);
	
	formattedWrite(r, fmt, args);
}

void writefln(Sink, A...)(ref Sink sink, string fmt, A args)
{
	writef(sink, fmt, args);
	writef(sink, "\n");
}
