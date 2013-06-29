/*
 *
 * Read the raw events from a /dev/input/eventXX device
 *
 */
import std.stdio;

struct InputEvent {
    ulong time_secs;
    ulong time_usecs;
    ushort type;
    ushort code;
    int value;
}

string type_string(int event_code) {
	switch(event_code) {
		case 0x00: return "SYN";
		case 0x01: return "KEY";
		case 0x02: return "REL";
		case 0x03: return "ABS";
		case 0x04: return "MSC";
		case 0x05: return "SW ";
		case 0x11: return "LED";
		case 0x12: return "SND";
		case 0x14: return "REP";
		case 0x15: return "FF ";
		case 0x17: return "FFStat";
		default: return "???";
	}
}

int main(string[] args) {
	if(args.length < 2) {
		writeln("Syntax: ", args[0], " /dev/input/eventXX");
		return 1;
	}
	auto f = File(args[1]);
    auto events = new InputEvent[1];
    auto event = &events[0];

    while(true) {
        f.rawRead(events);
        writefln("%u.%-07u %s %3d %d", event.time_secs, event.time_usecs, type_string(event.type), event.code, event.value);
        if(event.type == 0) {
	    writeln("");
        }
        stdout.flush();
    }
}
