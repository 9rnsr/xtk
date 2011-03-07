module xtk.windows;

version(Windows)
{
	public import core.sys.windows.windows;
	enum : uint { ERROR_BROKEN_PIPE = 109 }
}
