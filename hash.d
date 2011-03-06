/**
	this module was copied from rt.util.hash.
*/
/**
 * The console module contains a hash implementation.
 *
 * Copyright: Copyright Sean Kelly 2009 - 2009.
 * License:   <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
 * Authors:   Sean Kelly
 */

/*          Copyright Sean Kelly 2009 - 2009.
 * Distributed under the Boost Software License, Version 1.0.
 *    (See accompanying file LICENSE_1_0.txt or copy at
 *          http://www.boost.org/LICENSE_1_0.txt)
 */
module xtk.hash;

import std.traits;

/**
*/
struct Hashable(T) if (is(T == struct))
{
	T t;
	
	alias t this;
	
	this(A...)(A args)
	{
		t = T(args);
	}
	
	bool oEquals(ref const Hashable!T rhs) const
	{
		auto result = true;
		foreach (i, __dummy; t.tupleof)
			result = result && this.t.tupleof[i] == rhs.t.tupleof[i];
		return result;
	}
	int opCmp(ref const Hashable!T rhs) const
	{
		foreach (i, __dummy; t.tupleof)
			if (t.tupleof[i] != rhs.t.tupleof[i])
				return t.tupleof[i] < rhs.t.tupleof[i] ? -1 : 1;
		
		return 0;
	}
	hash_t toHash() const
	{
		hash_t hash = 0;
		foreach (i, __dummy; t.tupleof)
		{
			hash = .getHash(t.tupleof[i], hash);
		}
		return hash;
	}
}

/**
*/
hash_t getHash(T)(ref T t, hash_t seed = 0)
{
	static if (isArray!T)
	{
		auto a = *(cast(void[]*)&t);
		return .hashOf(a.ptr, a.length, seed);
	}
	else
	{
		static assert(0);
	}
}









version( X86 )
    version = AnyX86;
version( X86_64 )
    version = AnyX86;
version( AnyX86 )
    version = HasUnalignedOps;


hash_t hashOf( const (void)* buf, size_t len, hash_t seed = 0 )
{
    /*
     * This is Paul Hsieh's SuperFastHash algorithm, described here:
     *   http://www.azillionmonkeys.com/qed/hash.html
     * It is protected by the following open source license:
     *   http://www.azillionmonkeys.com/qed/weblicense.html
     */
    version( HasUnalignedOps )
    {
        static uint get16bits( const (ubyte)* x )
        {
            return *cast(ushort*) x;
        }
    }
    else
    {
        static uint get16bits( const (ubyte)* x )
        {
            return ((cast(uint) x[1]) << 8) + (cast(uint) x[0]);
        }
    }

    // NOTE: SuperFastHash normally starts with a zero hash value.  The seed
    //       value was incorporated to allow chaining.
    auto data = cast(const (ubyte)*) buf;
    auto hash = seed;
    int  rem;

    if( len <= 0 || data is null )
        return 0;

    rem = len & 3;
    len >>= 2;

    for( ; len > 0; len-- )
    {
        hash += get16bits( data );
        auto tmp = (get16bits( data + 2 ) << 11) ^ hash;
        hash  = (hash << 16) ^ tmp;
        data += 2 * ushort.sizeof;
        hash += hash >> 11;
    }

    switch( rem )
    {
    case 3: hash += get16bits( data );
            hash ^= hash << 16;
            hash ^= data[ushort.sizeof] << 18;
            hash += hash >> 11;
            break;
    case 2: hash += get16bits( data );
            hash ^= hash << 11;
            hash += hash >> 17;
            break;
    case 1: hash += *data;
            hash ^= hash << 10;
            hash += hash >> 1;
            break;
     default:
            break;
    }

    /* Force "avalanching" of final 127 bits */
    hash ^= hash << 3;
    hash += hash >> 5;
    hash ^= hash << 4;
    hash += hash >> 17;
    hash ^= hash << 25;
    hash += hash >> 6;

    return hash;
}
