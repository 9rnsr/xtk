module xtk.workaround;


deprecated string format(Char, A...)(in Char[] fmt, A args)
{
	return "";
}


import std.traits : hasElaborateDestructor, hasElaborateCopyConstructor;
import std.c.string : memcpy;
import std.exception : pointsTo;
void issue5661fix_move(T)(ref T source, ref T target)
{
    if (&source == &target) return;
    assert(!pointsTo(source, source));
    static if (is(T == struct))
    {
        // Most complicated case. Destroy whatever target had in it
        // and bitblast source over it
//      static if (is(typeof(target.__dtor()))) target.__dtor();
		static if (hasElaborateDestructor!T) typeid(T).destroy(&target);
        memcpy(&target, &source, T.sizeof);
        // If the source defines a destructor or a postblit hook, we must obliterate the
        // object in order to avoid double freeing and undue aliasing
//      static if (is(typeof(source.__dtor())) || is(typeof(source.__postblit())))
		static if (hasElaborateDestructor!T || hasElaborateCopyConstructor!T)
        {
            static T empty;
            memcpy(&source, &empty, T.sizeof);
        }
    }
    else
    {
        // Primitive data (including pointers and arrays) or class -
        // assignment works great
        target = source;
        // static if (is(typeof(source = null)))
        // {
        //     // Nullify the source to help the garbage collector
        //     source = null;
        // }
    }
}
T issue5661fix_move(T)(ref T src)
{
    T result;
    issue5661fix_move(src, result);
    return result;
}


import core.memory;
import std.algorithm, std.conv, std.ctype, std.encoding, std.exception,
    std.intrinsic, std.range, std.string, std.traits, std.typecons, std.utf;
import std.c.string : memcpy;
struct issue5663fix_Appender(A : T[], T)
{
    private struct Data
    {
        size_t capacity;
        Unqual!T[] arr;
    }

    private Data* _data;

/**
Construct an appender with a given array.  Note that this does not copy the
data.  If the array has a larger capacity as determined by arr.capacity,
it will be used by the appender.  After initializing an appender on an array,
appending to the original array will reallocate.
*/
    this(T[] arr)
    {
        // initialize to a given array.
        _data = new Data;
        _data.arr = cast(Unqual!T[])arr;

        // We want to use up as much of the block the array is in as possible.
        // if we consume all the block that we can, then array appending is
        // safe WRT built-in append, and we can use the entire block.
        auto cap = arr.capacity;
        if(cap > arr.length)
            arr.length = cap;
        // we assume no reallocation occurred
        assert(arr.ptr is _data.arr.ptr);
        _data.capacity = arr.length;
    }

/**
Reserve at least newCapacity elements for appending.  Note that more elements
may be reserved than requested.  If newCapacity < capacity, then nothing is
done.
*/
    void reserve(size_t newCapacity)
    {
        if(!_data)
            _data = new Data;
        if(_data.capacity < newCapacity)
        {
            // need to increase capacity
            immutable len = _data.arr.length;
            immutable growsize = (newCapacity - len) * T.sizeof;
            auto u = GC.extend(_data.arr.ptr, growsize, growsize);
            if(u)
            {
                // extend worked, update the capacity
                _data.capacity = u / T.sizeof;
            }
            else
            {
                // didn't work, must reallocate
                auto bi = GC.qalloc(newCapacity * T.sizeof,
                        (typeid(T[]).next.flags & 1) ? 0 : GC.BlkAttr.NO_SCAN);
                _data.capacity = bi.size / T.sizeof;
                if(len)
                    memcpy(bi.base, _data.arr.ptr, len * T.sizeof);
                _data.arr = (cast(Unqual!T*)bi.base)[0..len];
                // leave the old data, for safety reasons
            }
        }
    }

/**
Returns the capacity of the array (the maximum number of elements the
managed array can accommodate before triggering a reallocation).  If any
appending will reallocate, capacity returns 0.
 */
    @property size_t capacity()
    {
        return _data ? _data.capacity : 0;
    }

/**
Returns the managed array.
 */
    @property T[] data()
    {
        return cast(typeof(return))(_data ? _data.arr : null);
    }

    // ensure we can add nelems elements, resizing as necessary
    private void ensureAddable(size_t nelems)
    {
        if(!_data)
            _data = new Data;
        immutable len = _data.arr.length;
        immutable reqlen = len + nelems;
        if (reqlen > _data.capacity)
        {
            // Time to reallocate.
            // We need to almost duplicate what's in druntime, except we
            // have better access to the capacity field.
            auto newlen = newCapacity(reqlen);
            // first, try extending the current block
            auto u = GC.extend(_data.arr.ptr, nelems * T.sizeof, (newlen - len) * T.sizeof);
            if(u)
            {
                // extend worked, update the capacity
                _data.capacity = u / T.sizeof;
            }
            else
            {
                // didn't work, must reallocate
                auto bi = GC.qalloc(newlen * T.sizeof,
                        (typeid(T[]).next.flags & 1) ? 0 : GC.BlkAttr.NO_SCAN);
                _data.capacity = bi.size / T.sizeof;
                if(len)
                    memcpy(bi.base, _data.arr.ptr, len * T.sizeof);
                _data.arr = (cast(Unqual!T*)bi.base)[0..len];
                // leave the old data, for safety reasons
            }
        }
    }

    private static size_t newCapacity(size_t newlength)
    {
        long mult = 100 + (1000L) / (bsr(newlength * T.sizeof) + 1);
        // limit to doubling the length, we don't want to grow too much
        if(mult > 200)
            mult = 200;
        auto newext = cast(size_t)((newlength * mult + 99) / 100);
        return newext > newlength ? newext : newlength;
    }

/**
Appends one item to the managed array.
 */
    void put(U)(U item) if (isImplicitlyConvertible!(U, T) ||
            isSomeChar!T && isSomeChar!U)
    {
        static if (isSomeChar!T && isSomeChar!U && T.sizeof < U.sizeof)
        {
            // must do some transcoding around here
            Unqual!T[T.sizeof == 1 ? 4 : 2] encoded;
            auto len = std.utf.encode(encoded, item);
            put(encoded[0 .. len]);
        }
        else
        {
            ensureAddable(1);
            immutable len = _data.arr.length;
            _data.arr.ptr[len] = cast(Unqual!T)item;
            _data.arr = _data.arr.ptr[0 .. len + 1];
        }
    }

    // Const fixing hack.
    void put(Range)(Range items)
    if(isInputRange!(Unqual!Range) && !isInputRange!Range) {
        alias put!(Unqual!Range) p;
        p(items);
    }

/**
Appends an entire range to the managed array.
 */
    void put(Range)(Range items) if (isInputRange!Range
            && is(typeof(typeof(this).init.put(items.front))))
    {
        // note, we disable this branch for appending one type of char to
        // another because we can't trust the length portion.
        static if (!(isSomeChar!T && isSomeChar!(ElementType!Range) &&
                     !is(Range == Unqual!T[]) &&
                     !is(Range == const(T)[]) &&		// fix
                     !is(Range == immutable(T)[])) &&	// fix
                   is(typeof(items.length) == size_t))
        {
            // optimization -- if this type is something other than a string,
            // and we are adding exactly one element, call the version for one
            // element.
            static if(!isSomeChar!T)
            {
                if(items.length == 1)
                {
                    put(items.front);
                    return;
                }
            }

            // make sure we have enough space, then add the items
            ensureAddable(items.length);
            immutable len = _data.arr.length;
            immutable newlen = len + items.length;
            _data.arr = _data.arr.ptr[0..newlen];
            static if(is(typeof(_data.arr[] = items)))
            {
                _data.arr.ptr[len..newlen] = items;
            }
            else
            {
                for(size_t i = len; !items.empty; items.popFront(), ++i)
                    _data.arr.ptr[i] = cast(Unqual!T)items.front;
            }
        }
        else
        {
            //pragma(msg, Range.stringof);
            // Generic input range
            for (; !items.empty; items.popFront())
            {
                put(items.front);
            }
        }
    }

    // only allow overwriting data on non-immutable and non-const data
    static if(!is(T == immutable) && !is(T == const))
    {
/**
Clears the managed array.
*/
        void clear()
        {
            if (_data)
            {
                _data.arr = _data.arr.ptr[0..0];
            }
        }

/**
Shrinks the managed array to the given length.  Passing in a length that's
greater than the current array length throws an enforce exception.
*/
        void shrinkTo(size_t newlength)
        {
            if(_data)
            {
                enforce(newlength <= _data.arr.length);
                _data.arr = _data.arr.ptr[0..newlength];
            }
            else
                enforce(newlength == 0);
        }
    }
}


/+
import std.exception, std.conv : ConvException;

// emplace
/**
Given a raw memory area $(D chunk), constructs an object of non-$(D
class) type $(D T) at that address. The constructor is passed the
arguments $(D Args). The $(D chunk) must be as least as large as $(D
T) needs and should have an alignment multiple of $(D T)'s alignment.

This function can be $(D @trusted) if the corresponding constructor of
$(D T) is $(D @safe).

Returns: A pointer to the newly constructed object.
 */
T* emplace(T, Args...)(void[] chunk, Args args) if (!is(T == class))
{
    enforce(chunk.length >= T.sizeof,
            new ConvException("emplace: target size too small"));
    auto a = cast(size_t) chunk.ptr;
    version (OSX)       // for some reason, breaks on other platforms
        enforce(a % T.alignof == 0, new ConvException("misalignment"));
    auto result = cast(typeof(return)) chunk.ptr;

    void initialize()
    {
		auto init = cast(ubyte[])typeid(T).init;
		if (init.ptr)
			(cast(ubyte[])chunk)[] = init[];
		else
			(cast(ubyte[])chunk)[] = 0;
    //  static T i;
    //  memcpy(chunk.ptr, &i, T.sizeof);
    }

    static if (Args.length == 0)
    {
        // Just initialize the thing
        initialize();
    }
    else static if (is(T == struct))
    {
        static if (is(typeof(result.__ctor(args))))
        {
            // T defines a genuine constructor accepting args
            // Go the classic route: write .init first, then call ctor
            initialize();
            result.__ctor(args);
        }
        else static if (is(typeof(T(args))))
        {
            // Struct without constructor that has one matching field for
            // each argument
            initialize();
            *result = T(args);
        }
        else static if (Args.length == 1 && is(Args[0] : T))
        {
            initialize();
            *result = args[0];
        }
    }
    else static if (Args.length == 1 && is(Args[0] : T))
    {
        // Primitive type. Assignment is fine for initialization.
        *result = args[0];
    }
    else
    {
        static assert(false, "Don't know how to initialize an object of type "
                ~ T.stringof ~ " with arguments " ~ Args.stringof);
    }
    return result;
}
+/
