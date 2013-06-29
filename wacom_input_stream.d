/*
 * Read the input of a Wacom Tablet
 * (tested with an Intuos 5)
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
    
    int posx = 0; // ABS, 0
    int posy = 0; // ABS, 1
    int pressure = 0; // 24
    int anglex = 0; // 25
    int angley = 0; // 26
    int anglez = 0; // ? 27

    while(true) {
        f.rawRead(events);
        if(event.type == 0x03) { // ABS
            switch(event.code) {
				case 0: posx = event.value; break;
				case 1: posy = event.value; break;
				case 24: pressure = event.value; break;
				case 25: anglex = event.value; break;
				case 26: angley = event.value; break;
				case 27: anglez = event.value; break;
				default: writefln("?? %u.%-07u %s %3d %d", event.time_secs, event.time_usecs, type_string(event.type), event.code, event.value);
            }
	    }
        else if(event.type == 0) {
			writefln("wc %8d %8d %8d %8d %8d %8d", posx, posy, pressure, anglex, angley, anglez);
            stdout.flush();
        }
    }
}
