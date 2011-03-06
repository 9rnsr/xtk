import device;

void main(string[] args)
{
//	sample_base64decoder();
	sample_replying_cat(args.length==2 ? std.conv.to!int(args[1]) : 1);
}

void sample_base64decoder()
{
	auto base64in = device.Base64.decoder(device.buffered(device.encoded!char(din)));
	device.copy(base64in, dout);
}

void sample_replying_cat(int impl)
{
	final switch (impl)
	{
	case 1:	// doutにバッファリングなし・ubyteで書き込み
		void output(Sink, E)(Sink s, const(E)[] data)
		{
			auto v = cast(const(ubyte)[])data;
			while (v.length > 0)
				s.push(v);
		}
		foreach (line; lined!(const(char)[])(din))
		{
			//writeln("> ", line);
			output(dout, "> ");
			output(dout, line);
			output(dout, "\r\n");
		}
		break;
	
	case 2:	// doutにバッファリングなし・char[]で書き込み
		auto tout = encoded!char(dout);
		foreach (line; lined!(const(char)[])(din))
		{
			auto app = std.array.appender!string();
			std.format.formattedWrite(app, "> %s\r\n", line);
			device.copy(app.data[], tout);
		}
		break;
	
	case 3:	// doutにバッファリングあり・char[]で書き込み
		auto tout = buffered(encoded!char(dout));
		auto textout = ranged(tout);	// add range i/f
		foreach (line; lined!(const(char)[])(din))
		{
			std.format.formattedWrite(textout, "> %s\r\n", line);
		}
		break;
	}
}
