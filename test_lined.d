import std.stdio;

import std.perf;
void main(string[] args)
{
	//getPageSize();
	
	if (args.length == 2)
	{
		auto fname = args[1];
		
		// -------------
		perf_std_lined(fname, "char[]  stdio");
		
		// ubyteの列(バッファリング有り)をconst(char)[]のsliceで取る
		perf_file_buffered_lined!(const(char)[])(fname, "const(char)[] device");
		
		// ubyteの列をstringとみなしてLine分割する
		perf_file_buffered_lined!(string)(fname, "string device");
		
		//perf_sinfu_io(fname, "const(char)[]  sinfu");
		// -------------
		
	//	foreach(line;lined!(const(dchar)[])(decoder(device.File(fname))))
	//	{
	//	}
	}

/+	foreach (char c; buffered(File(args[1])))
	{
		if (c != '\r') write(c);
	}	// +/

//	//バイト列をchar列のバイト表現とみなし、decoder!dcharでcharのRangeに変換する
//	foreach (line; lined!string(decoder!char(buffered(File(fname)))))

}

import device;
void perf_file_buffered_lined(String, bool CalcPerf=true)(string fname, string msg)
{
	auto pc = new PerformanceCounter;
	pc.start;
	
	size_t nlines = 0;
	
	foreach (i; 0 .. 1000)
	{
		foreach (line; lined!String(buffered(device.File(fname), 2048)))
		{
			line.dup, ++nlines;
			static if (!CalcPerf) writefln("%s", line);
		}
		static if (!CalcPerf) assert(0);
	}
	pc.stop;
	
	writefln("%24s : %g line/sec", msg, nlines / (1.e-6 * pc.microseconds));
}

import std.stdio;
void perf_std_lined(string fname, string msg)
{
	auto pc = new PerformanceCounter;
	pc.start;
	
	size_t nlines = 0;
	foreach (i; 0 .. 1000)
	{
		auto f = std.stdio.File(fname);
		
		foreach (line; f.byLine)
		{
			line.dup, ++nlines;
		}
		
		f.close();
	}
	pc.stop;
	
	writefln("%24s : %g line/sec", msg, nlines / (1.e-6 * pc.microseconds));
}

/+
import device_sinfuio;
void perf_sinfu_io(string fname, string msg)
{
	auto pc = new PerformanceCounter;

	pc.start;
	size_t nlines = 0;
	foreach (i; 0 .. 1000)
	{
		auto file = device_sinfuio.File!(IODirection.input)(__FILE__);
		auto uport = openUTF8TextInputPort(file);

		foreach (line; uport.byLine)
			line.dup, ++nlines;
	}
	pc.stop;

	writefln("%24s : %g line/sec", msg, nlines / (1.e-6 * pc.microseconds));
}
+/


/*
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

*/

version(Windows)
{
	import core.sys.windows.windows;

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
