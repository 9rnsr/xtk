module xtk.filesys;

public import std.file;
public import std.path;
public import std.datetime;
import std.process, std.array;
alias std.path.defaultExt	defExt;
alias std.path.addExt		setExt;
alias std.path.join			joinPath;

//debug = 1;
debug(1) import std.stdio;

version (Windows):

string which(string name)
{
	auto path = environment["PATH"];
	debug(1) writefln("%s", path);
	auto pathes = split(path, pathsep);
	
	foreach (ref dir; pathes)
	{
		dir = dir.rel2abs;
		if (dir.getDrive == "")
		{
			assert(dir[0..1] == sep || dir[0..1] == altsep);
			dir = getcwd().getDrive() ~ dir;
		}
	}
	
	return which(name, pathes);
}

string which(string name, string pathes[])
{
	auto exe = defExt(name, "exe");
	assert(exe.basename == exe);
	debug(1) writefln("exe = %s", exe);
	
	version (Windows) pathes = `.\` ~ pathes;
	debug(1) writefln("pathes = %s", pathes);
	
	foreach (path; pathes)
	{
		auto abs_exe = joinPath(path, exe).rel2abs;	// drive nameまで結合されない…
		debug(1) writefln("abs_exe = %s", abs_exe);
		if (abs_exe.exists)
			return abs_exe;
	}
	return null;
}

string chompPath(string path)
{
	return path[0 .. lastSeparator(path)];
}




// from https://github.com/kyllingstad/ltk/blob/master/ltk/path.d

import std.traits;

private int lastSeparator(C)(in C[] path)  if (isSomeChar!C)
{
    int i = path.length - 1;
    while (i >= 0 && !isSeparator(path[i])) --i;
    return i;
}
version(Windows) private bool isSeparator(dchar c)
{
    return isDirSeparator(c) || isDriveSeparator(c);
}
version(Posix) private alias isDirSeparator isSeparator;

bool isDirSeparator(dchar c)
{
    if (c == '/') return true;
    version(Windows) if (c == '\\') return true;
    return false;
}
private bool isDriveSeparator(dchar c)
{
    version(Windows) return c == ':';
    else return false;
}
