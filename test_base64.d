import std.stdio;

import std.base64;
import device_base64;


enum bool Print = false;

import std.perf;
void main(string[] args)
{
	//getPageSize();
	
	if (args.length == 2 || args.length == 3)
	{
		auto fname = args[1];
		bool std_print, dev_print;
		if (args.length == 3)
		{
			std_print = args[2][0] == '1';
			dev_print = args[2][0] == '2';
		}
		
		// -------------
		perf_std_base64(fname, "std base64   ", std_print);
		
//		perf_dev_base64_chunk!(device_base64.base64_0)(fname, "dev base64 0 ", dev_print);
		
//		perf_dev_base64!(device_base64.base64_1)(fname, "dev base64 1 ", dev_print);
//		perf_dev_base64!(device_base64.base64_2)(fname, "dev base64 2 ", dev_print);
//		perf_dev_base64!(device_base64.base64_3)(fname, "dev base64 3 ", dev_print);
		/////perf_dev_base64!(device_base64.base64_4)(fname, "dev base64 4 ", dev_print);
		
		perf_dev_base64_pool !(device_base64.base64_4p)(fname, "dev base64 4p", dev_print);
		perf_dev_base64_chunk!(device_base64.base64_4x)(fname, "dev base64 4x", dev_print);
//		perf_dev_base64!(device_base64.base64_4c)(fname, "dev base64 4c", dev_print);
		
		perf_dev_base64_chunk!(device_base64.base64_5)(fname, "dev base64 5 ", dev_print);
		// -------------
/+
Buffered!Fileのサイズを3の倍数にし、境界を合わせた上で
	-release -inlineで比較
	std.base64を基準だと87%程度の性能
	----
	characters = 700796
	            std base64   :   60643475 characters/sec
	characters = 700456
	            dev base64 0 :   53654232 characters/sec
	characters = 700452
	           dev base64 4x :   53384041 characters/sec
	----
	
	-covで比較
	89%程度の性能
	----
	characters = 715824
	            std base64   :   38670196 characters/sec
	characters = 715472
	            dev base64 0 :   34316850 characters/sec
	characters = 715472
	           dev base64 4x :   34562195 characters/sec
	----
	
	std.base64同等以上までは上げられず。
	チャンク境界の処理コストを恣意的に下げてもこれだからなあ…
	しかもRange of charではもっと性能落ちるし。これはRangeの宿命かな。
	-covで比較
	35%！
	----
	characters = 711724
	            std base64   :   35232117 characters/sec
	characters = 711376
	           dev base64 4c :   13591960 characters/sec
	----
+/
	}

}

void perf_std_base64(string fname, string msg, bool p=false)
{
	static if (Print) if (p) writefln("----");
	auto pc = new PerformanceCounter;
	pc.start;
	
	size_t char_count = 0;
	
	foreach (chunk; std.base64.Base64.encoder(std.stdio.File(fname).byChunk(2040)))
	{
		foreach (c; chunk)
		{
			++char_count;
			static if (Print) if (p) write(c);
			static if (Print) if (p) if ((char_count % 80) == 0) write('\n');
		}
	}
	
	pc.stop;
	static if (Print) if (p) writefln("\n----");
	
	writefln("characters = %s", char_count);
	writefln("%24s : %10.0f characters/sec", msg, char_count / (1.e-6 * pc.microseconds));
}


void perf_dev_base64_pool(alias Base64)(string fname, string msg, bool p=false)
{
	static if (Print) if (p) writefln("----");
	auto pc = new PerformanceCounter;
	pc.start;
	
	size_t char_count = 0;
	
	void put(Sink, E)(Sink s, const(E)[] data)
	{
		auto v = cast(const(ubyte)[])data;
		while (v.length > 0)
			s.push(v);
	}
	auto enc = Base64.encoder(Buffered!(device.File)(fname, 2040));
	while (enc.fetch())
	{
		auto chunk = enc.available;
	  version (none)
	  {
		char_count += chunk.length;	//反則
	  }
	  else
	  {
		foreach (c; chunk)
		{
			++char_count;
		}
	  }
	//	put(dout, chunk);
		enc.consume(chunk.length);
	}
	
	pc.stop;
	static if (Print) if (p) writefln("\n----");
	
	writefln("characters = %s", char_count);
	writefln("%24s : %10.0f characters/sec", msg, char_count / (1.e-6 * pc.microseconds));
}
void perf_dev_base64(alias Base64)(string fname, string msg, bool p=false)
{
	static if (Print) if (p) writefln("----");
	auto pc = new PerformanceCounter;
	pc.start;
	
	size_t char_count = 0;
	
//	foreach (c; Base64.encoder(Buffered!(device.File)(fname, 2048)))
	foreach (c; Base64.encoder(Buffered!(device.File)(fname, 2040), 2720))	//境界を合わせる
	{
		++char_count;
		static if (Print) if (p) write(c);
		static if (Print) if (p) if ((char_count % 80) == 0) write('\n');
	}
	
	pc.stop;
	static if (Print) if (p) writefln("\n----");
	
	writefln("characters = %s", char_count);
	writefln("%24s : %10.0f characters/sec", msg, char_count / (1.e-6 * pc.microseconds));
}
void perf_dev_base64_chunk(alias Base64)(string fname, string msg, bool p=false)
{
	static if (Print) if (p) writefln("----");
	auto pc = new PerformanceCounter;
	pc.start;
	
	size_t char_count = 0;
	
//	foreach (chunk; Base64.encoder(Buffered!(device.File)(fname, 2048)))
	foreach (chunk; Base64.encoder(Buffered!(device.File)(fname, 2040), 2720))	//境界を合わせる
	{
		foreach (c; chunk)
		{
			++char_count;
			static if (Print) if (p) write(c);
			static if (Print) if (p) if ((char_count % 80) == 0) write('\n');
		}
	}
	
	pc.stop;
	static if (Print) if (p) writefln("\n----");
	
	writefln("characters = %s", char_count);
	writefln("%24s : %10.0f characters/sec", msg, char_count / (1.e-6 * pc.microseconds));
}
