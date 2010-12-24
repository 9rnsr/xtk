module typecons.tagunion;

version(unittest) import std.stdio;

template TagUnion(Defines...)
{
private:
	import std.metastrings;
	import typecons.meta, typecons.match;

	alias typeof(this) Self;
	
	template ExtractTags(E...)
	{
	  static if (E.length == 0)
		alias TypeTuple!() Result;
	  else static if (is(typeof(E[0])) && isSomeString!(typeof(E[0])))
		alias TypeTuple!(E[0], ExtractTags!(E[1..$]).Result) Result;
	  else
		alias ExtractTags!(E[1..$]).Result Result;
	}
	template ExtractSigs(E...)
	{
		template Begin(size_t n)
		{
			enum Begin = staticIndexOf!(TyconTagList[n], E) + 1;
		}
		template End(size_t n)
		{
		  static if (n == TyconTagList.length-1)
			enum End = E.length;
		  else
			enum End = staticIndexOf!(TyconTagList[n+1], E);
		}
		
		template ExtractSig(size_t n)
		{
			alias Pack!(E[Begin!n .. End!n]) ExtractSig;
		}
		alias staticMap!(
				ExtractSig,
				staticIota!(staticLength!(TyconTagList))
			  ) Result;
	}

	alias ExtractTags!Defines.Result TyconTagList;
	alias ExtractSigs!Defines.Result TyconSigList;
	
	template TyconTag(size_t n)
	{
		alias Identity!(TyconTagList[n]) TyconTag;
	}
	template TyconSig(size_t n)
	{
		alias Identity!(TyconSigList[n]).field TyconSig;
	}

  // tycon tags
	template GenerateTag()
	{
		mixin(mixin(expand!q{
			enum Tag
			{
				${ TyconTag!0 } = 0,
				${ Join!(", ", TyconTagList[1 .. $]) }
			}
		}));
	}

  // tycon types
	template GenerateDataType(size_t n)
	{
		template GenerateDataType(size_t n=n)
		{
			template GenElement(size_t I)
			{
				template GenElement(size_t i=I)
				{
					mixin(mixin(expand!q{
						TyconSig!$n[$i] _$i;
					}));
				}
			}
			mixin(mixin(expand!q{
				static struct ${ TyconTag!n }
				{
				private:
					Tag tag;
					mixin mixinAll!(
						staticMap!(
							GenElement,
							staticIota!(TyconSig!n.length)));
				
				public:
					static auto opCall(Elem...)(Elem elem)
						if (isCovariantParameterWith!(Pack!(Elem), Pack!(TyconSig!n)))
					{
						auto payload = new Self();
						payload.data$n.tupleof = TypeTuple!(Tag.${ TyconTag!n }, elem);
						return payload;
					}
					static auto opSlice()
					{
						return p[];
					}
					static auto opIndex(string file=__FILE__, int line=__LINE__, Elem...)(Elem elem)
					{
						//pragma(msg, "GenerateDataType.opIndex : file/line=", file, "/", line);
						return p[Tag.${ TyconTag!n }, elem];
					}
				}
			}));
		}
	}

  // tycon datas
	template GenerateDataField()
	{
		template GenDataField(size_t n)
		{
			enum GenDataField = mixin(expand!q{
				${ TyconTag!n } data$n;
			});
		}
		enum Result = mixin(expand!q{
			union
			{
				Tag tag;
				${ Join!("\n",
					staticMap!(
						GenDataField, staticIota!(staticLength!TyconTagList))) }
			}
		});
	}

  // opMatch
	template GenerateOpMatch()
	{
		template GenMatchCase(size_t n)
		{
			enum GenMatchCase = mixin(expand!q{
				case Tag.${ TyconTag!n }:
					return m <<= tuple(data$n.tupleof);
			});
		}
		
		bool opMatch(Match)(ref Match m)
		{
			mixin(mixin(expand!q{
				final switch (tag)
				{
				${ Join!("\n",
						staticMap!(
							GenMatchCase,
							staticIota!(staticLength!(TyconTagList)))) }
				}
			}));
		}
	}

private:
	mixin GenerateTag!();
	mixin mixinAll!(
		staticMap!(
			GenerateDataType,
			staticIota!(staticLength!TyconTagList)));
	
	// use string-mixin for correct code of union
	mixin(GenerateDataField!().Result);

public:
	template GenerateTycons(Self)
	{
		template GenerateTycons(Self=Self)
		{
			import std.metastrings;
			import typecons.meta;
			
			template GenAlias(size_t n)
			{
				template GenAlias(size_t n=n)
				{
					mixin(mixin(expand!q{
						alias Self.${ Self.TyconTag!n } ${ Self.TyconTag!n };
					}));
				}
			}
			mixin mixinAll!(
				staticMap!(
					GenAlias,
					staticIota!(staticLength!(Self.TyconTagList))));
		}
	}
  // export type constructors
	alias GenerateTycons!Self tycons;

	mixin GenerateOpMatch!();
}

version(unittest)
{
	class temp
	{
		static class Label
		{
			string name;
			this(string s){ name = s; }
			bool opEquals(Object o)
			{
				if (auto lbl = cast(Label)o)
					return lbl.name == this.name;
				return false;
			}
		}
	}
	enum BinOp:ubyte{ ADD,SUB }
	
	class Exp
	{
		mixin TagUnion!(
			"CONST",long,
			"NAME",	temp.Label,
			"BIN",	BinOp, Exp, Exp
		);
	}
	mixin Exp.tycons;
}
debug(tagunion)
unittest
{
	writefln("unittest @ %s:%s", __FILE__, __LINE__);
	scope(success) writefln("unittest succeeded @ %s:%s", __FILE__, __LINE__);
	
	long n;
	assert(CONST[&n] <<= CONST(10));
	assert(n == 10);

	auto label1 = new temp.Label("name1");
	auto label2 = new temp.Label("name2");
	assert(  NAME[label1] <<= NAME(new temp.Label("name1")) );
	assert(!(NAME[label2] <<= NAME(new temp.Label("name1"))));
	temp.Label label;
	assert(NAME[&label] <<= NAME(label1));
	assert(label is label1);
	
	Exp e;
	auto op = BinOp.ADD;
	assert(BIN[BinOp.ADD, null, null] <<= BIN(op, e, e));
}
