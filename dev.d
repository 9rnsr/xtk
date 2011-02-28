import std.getopt;
import core.runtime;

public import device;
public import device_perf;

void main(string[] args)
{
	bool perf = false;
	
	getopt(
		args,
		"perf",	&perf);
	
	if (perf)
		performance_test();
}
