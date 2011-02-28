import std.perf, std.file, std.stdio;

public import device;

void performance_test()
{
	doMeasPerf_LinedIn();
	doMeasPerf_BufferedOut();
}

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
