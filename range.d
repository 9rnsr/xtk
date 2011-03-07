module xtk.range;

public import std.range;
import std.traits;

/**
	Infinite iota range that is 0-origin and 1-step.
*/
@property auto iota() { return sequence!("n")(); }


unittest
{
	string msg = "hello world";
	foreach (i, c; zip(iota, msg))
		assert(msg[i] == c);
}


import std.conv, std.exception, std.typecons, std.typetuple;


/**
Iterate several ranges in lockstep. The element type is a proxy tuple
that allows accessing the current element in the $(D n)th range by
using $(D e[n]).

Example:
----
int[] a = [ 1, 2, 3 ];
string[] b = [ "a", "b", "c" ];
// prints 1:a 2:b 3:c
foreach (e; zip(a, b))
{
    write(e[0], ':', e[1], ' ');
}
----

$(D Zip) offers the lowest range facilities of all components, e.g. it
offers random access iff all ranges offer random access, and also
offers mutation and swapping if all ranges offer it. Due to this, $(D
Zip) is extremely powerful because it allows manipulating several
ranges in lockstep. For example, the following code sorts two arrays
in parallel:

----
int[] a = [ 1, 2, 3 ];
string[] b = [ "a", "b", "c" ];
sort!("a[0] > b[0]")(zip(a, b));
assert(a == [ 3, 2, 1 ]);
assert(b == [ "c", "b", "a" ]);
----
 */
struct Zip(Ranges...)
	if(Ranges.length && allSatisfy!(isInputRange, staticMap!(Unqual, Ranges)))
{
    alias staticMap!(Unqual, Ranges) R;
    Tuple!R ranges;
    alias Tuple!(staticMap!(.ElementType, R)) ElementType;
    StoppingPolicy stoppingPolicy = StoppingPolicy.shortest;

/**
   Builds an object. Usually this is invoked indirectly by using the
   $(XREF range,zip) function.
*/
    this(R rs, StoppingPolicy s = StoppingPolicy.shortest)
    {
        stoppingPolicy = s;
        foreach (i, Unused; R)
        {
            ranges[i] = rs[i];
        }
    }

/**
Returns $(D true) if the range is at end. The test depends on the
stopping policy.
 */
    static if(allSatisfy!(isInfinite, R))
    {
        // BUG:  Doesn't propagate infiniteness if only some ranges are infinite
        //       and s == StoppingPolicy.longest.  This isn't fixable in the
        //       current design since StoppingPolicy is known only at runtime.
        enum bool empty = false;
    }
    else
    {
        bool empty()
        {
            final switch (stoppingPolicy)
            {
                case StoppingPolicy.shortest:
                    foreach (i, Unused; R)
                    {
                        if (ranges[i].empty) return true;
                    }
                    break;
                case StoppingPolicy.longest:
                    foreach (i, Unused; R)
                    {
                        if (!ranges[i].empty) return false;
                    }
                    return true;
                case StoppingPolicy.requireSameLength:
                    foreach (i, Unused; R[1 .. $])
                    {
                        enforce(ranges[0].empty ==
                                ranges.field[i + 1].empty,
                                "Inequal-length ranges passed to Zip");
                    }
                    break;
            }
            return false;
        }
    }

    static if (allSatisfy!(isForwardRange, R))
        @property Zip save()
        {
            Zip result;
            result.stoppingPolicy = stoppingPolicy;
            foreach (i, Unused; R)
            {
                result.ranges[i] = ranges[i].save;
            }
            return result;
        }

/**
   Returns the current iterated element.
*/
    @property ElementType front()
    {
        ElementType result = void;
        foreach (i, Unused; R)
        {
            if (!ranges[i].empty)
            {
                emplace(&result[i], ranges[i].front);
            }
            else
            {
                emplace(&result[i]);
            }
        }
        return result;
    }

    static if (allSatisfy!(hasAssignableElements, R))
    {
/**
   Sets the front of all iterated ranges.
*/
        @property void front(ElementType v)
        {
            foreach (i, Unused; R)
            {
                if (!ranges[i].empty)
                {
                    ranges[i].front = v[i];
                }
            }
        }
    }

/**
   Moves out the front.
*/
    static if(allSatisfy!(hasMobileElements, R))
    {
        ElementType moveFront()
        {
            ElementType result = void;
            foreach (i, Unused; R)
            {
                if (!ranges[i].empty)
                {
                    emplace(&result[i], .moveFront(ranges[i]));
                }
                else
                {
                    emplace(&result[i]);
                }
            }
            return result;
        }
    }

/**
   Returns the rightmost element.
*/
    static if(allSatisfy!(isBidirectionalRange, R))
    {
        @property ElementType back()
        {
            ElementType result = void;
            foreach (i, Unused; R)
            {
                if (!ranges[i].empty)
                {
                    emplace(&result[i], ranges[i].back);
                }
                else
                {
                    emplace(&result[i]);
                }
            }
            return result;
        }

/**
   Moves out the back.
*/
        static if (allSatisfy!(hasMobileElements, R))
        {
            @property ElementType moveBack()
            {
                ElementType result = void;
                foreach (i, Unused; R)
                {
                    if (!ranges[i].empty)
                    {
                        emplace(&result[i], .moveBack(ranges[i]));
                    }
                    else
                    {
                        emplace(&result[i]);
                    }
                }
                return result;
            }
        }

/**
   Returns the current iterated element.
*/
        static if(allSatisfy!(hasAssignableElements, R))
        {
            @property void back(ElementType v)
            {
                foreach (i, Unused; R)
                {
                    if (!ranges[i].empty)
                    {
                        ranges[i].back = v[i];
                    }
                }
            }
        }
    }

/**
   Advances to the popFront element in all controlled ranges.
*/
    void popFront()
    {
        final switch (stoppingPolicy)
        {
            case StoppingPolicy.shortest:
                foreach (i, Unused; R)
                {
                    assert(!ranges[i].empty);
                    ranges[i].popFront();
                }
                break;
            case StoppingPolicy.longest:
                foreach (i, Unused; R)
                {
                    if (!ranges[i].empty) ranges[i].popFront();
                }
                break;
            case StoppingPolicy.requireSameLength:
                foreach (i, Unused; R)
                {
                    enforce(!ranges[i].empty, "Invalid Zip object");
                    ranges[i].popFront();
                }
                break;
        }
    }

    static if(allSatisfy!(isBidirectionalRange, R))
/**
   Calls $(D popBack) for all controlled ranges.
*/
        void popBack()
        {
            final switch (stoppingPolicy)
            {
                case StoppingPolicy.shortest:
                    foreach (i, Unused; R)
                    {
                        assert(!ranges[i].empty);
                        ranges[i].popBack();
                    }
                    break;
                case StoppingPolicy.longest:
                    foreach (i, Unused; R)
                    {
                        if (!ranges[i].empty) ranges[i].popBack();
                    }
                    break;
                case StoppingPolicy.requireSameLength:
                    foreach (i, Unused; R)
                    {
                        enforce(!ranges[0].empty, "Invalid Zip object");
                        ranges[i].popBack();
                    }
                    break;
            }
        }

/**
   Returns the length of this range. Defined only if all ranges define
   $(D length).
*/
    static if (allSatisfy!(hasLength, R))
        @property size_t length()
        {
            auto result = ranges[0].length;
            if (stoppingPolicy == StoppingPolicy.requireSameLength)
                return result;
            foreach (i, Unused; R[1 .. $])
            {
                if (stoppingPolicy == StoppingPolicy.shortest)
                {
                    result = min(ranges.field[i + 1].length, result);
                }
                else
                {
                    assert(stoppingPolicy == StoppingPolicy.longest);
                    result = max(ranges.field[i + 1].length, result);
                }
            }
            return result;
        }

/**
   Returns a slice of the range. Defined only if all range define
   slicing.
*/
    static if (allSatisfy!(hasSlicing, R))
        Zip opSlice(size_t from, size_t to)
        {
            Zip result = void;
            emplace(&result.stoppingPolicy, stoppingPolicy);
            foreach (i, Unused; R)
            {
                emplace(&result.ranges[i], ranges[i][from .. to]);
            }
            return result;
        }

    static if (allSatisfy!(isRandomAccessRange, R))
    {
/**
   Returns the $(D n)th element in the composite range. Defined if all
   ranges offer random access.
*/
        ElementType opIndex(size_t n)
        {
            ElementType result = void;
            foreach (i, Range; R)
            {
                emplace(&result[i], ranges[i][n]);
            }
            return result;
        }

        static if (allSatisfy!(hasAssignableElements, R))
        {
/**
   Assigns to the $(D n)th element in the composite range. Defined if
   all ranges offer random access.
 */
            void opIndexAssign(ElementType v, size_t n)
            {
                foreach (i, Range; R)
                {
                    ranges[i][n] = v[i];
                }
            }
        }

/**
   Destructively reads the $(D n)th element in the composite
   range. Defined if all ranges offer random access.
 */
        static if(allSatisfy!(hasMobileElements, R))
        {
            ElementType moveAt(size_t n)
            {
                ElementType result = void;
                foreach (i, Range; R)
                {
                    emplace(&result[i], .moveAt(ranges[i], n));
                }
                return result;
            }
        }
    }
    
/**
   Iterate zip elements with directry named heads of ranges.
   BUG: foreach(ref val, ...; zipped) { val = ...; } does not work correctly.
 */
    int opApply(int delegate(ref ElementType.Types) dg)
    {
		auto zip = this;
		for (; !zip.empty; zip.popFront())
		{
			auto e = zip.front;
			if (auto result = dg(e.field))
				return result;
		}
		return 0;
	}
}

/// Ditto
Zip!(R) zip(R...)(R ranges)
if (allSatisfy!(isInputRange, staticMap!(Unqual, R)))
{
    return Zip!(R)(ranges);
}

/// Ditto
Zip!(R) zip(R...)(StoppingPolicy sp, R ranges)
if(allSatisfy!(isInputRange, staticMap!(Unqual, R)))
{
    return Zip!(R)(ranges, sp);
}
