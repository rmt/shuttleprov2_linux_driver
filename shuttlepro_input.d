/*
 * Synopsys:
 *   Read the input of a ShuttlePRO v2 USB device and output
 *   it to stdout or call a command for each event.
 *
 * Usage:
 *   shuttlepro_input [-v|--verbose] [-c|--command COMMAND]
 *
 * Terminology:
 *   I call the outer ring which only partially turns
 *   the jog dial, and the inner ring which you can keep turning
 *   infinitely the shuttle ring.. maybe that's wrong, but you
 *   should probably know that before looking at this code. :-)
 *
 * Copyright:
 *   2013 by Robert Thomson
 *
 * License:
 *   LGPL v3, as found here: http://www.gnu.org/licenses/lgpl-3.0.html
 *
 */
import std.conv;
import std.math;
import std.stdio;
import std.getopt;
import std.process;
import std.datetime;
import std.concurrency;
import core.time;

/*
 * /dev/input/eventXX format, as defined in /usr/include/linux/input.h
 */
struct InputEvent {
    ulong time_secs;
    ulong time_usecs;
    ushort type;
    ushort code;
    int value;
}

/*
 * ShuttlePRO v2 will re-send the state of the jog & shuttle state
 * with _any_ event, if they're not set to 0.  We combine each
 * set of events into one class.  Each set ends with a 0 event type.
 */
struct CombinedEvent {
    ulong time_secs;
    ulong time_usecs;
    int jog_state;
    int shuttle_state;
    int key_code;
    int key_value;
}

bool optVerbose = false;
string optCommand = "";

/*
 * TODO: check if this always holds true.. or is it a udev special?
 */
string find_shuttle_input_device() {
  return "/dev/input/by-id/usb-Contour_Design_ShuttlePRO_v2-event-if00";
}

/*
 *  Either print the event, or call a command with it as an argument.
 */
void send_event(string ev) {
  if(optCommand == "") {
    stdout.writeln(ev);
    stdout.flush();
  } else {
    if(optVerbose) {
        writeln("Calling '", optCommand, " ", ev, "'");
    }
    auto result = executeShell(optCommand ~ " " ~ ev);
    if(result.status != 0) {
      stderr.writeln("Error: ", optCommand, " exited with ", result.status);
      stderr.writeln(result.output);
    } else if(optVerbose) {
      write(result.output);
    }
  }
}

/*
 * Jog events should be triggered based on elapsed time since
 * the previous jog event was triggered.
 *
 * This implementation chooses to treat the jog dial as a
 * recurring event with an alternating interval.
 */
void trigger_jog_event(int jog_state) {
  // we treat -1 & 1 as 0 due to the device not generating a usb
  // event for 0.  It's not noticable when using it.
  static SysTime last_jog_event;
  static first_call = true; // hacky - can we check for null with last_jog_event ?

  if(jog_state >= -1 && jog_state <= 1)
    return;

  auto current_time = Clock.currTime();
  auto waittime = dur!("msecs")(575) / abs(jog_state); // how long between events
  Duration tdiff;
  if(first_call) {
    tdiff = dur!("seconds")(1);
    first_call = false;
  } else {
    tdiff = current_time - last_jog_event;
  }
  if(tdiff > waittime) {
    if(jog_state < 0)
      send_event("jog_backward");
    else
      send_event("jog_forward");
    last_jog_event = current_time;
  }
}

/*
 *  This runs in another thread and waits for events..
 *  If the jog dial is activated, it will timeout fast
 *  and call trigger_jog_event frequently.  But if it's
 *  off, it'll only timeout every 60 seconds so as to be
 *  mostly idle.  This could've been implemented as a
 *  select timeout, but I wanted to play with D's
 *  concurrency library.
 */
void receiveLoop(Tid tid, bool verbose, string command) {
  optVerbose = verbose; // work around thread-local globals
  optCommand = command;

  int jog_state = 0;
  int shuttle_state = -1;
  auto delay = dur!("seconds")(60);

  while(true) {
    auto received = receiveTimeout(delay,
      (CombinedEvent ev) {
        // process event
        if(ev.key_code != 0) {
          // keyboard event
          if(ev.key_value == 1)
            send_event("key_down_" ~ to!string(ev.key_code));
          else 
            send_event("key_up_" ~ to!string(ev.key_code));
        } else if(ev.jog_state != jog_state) {
          // jog state changed
          if(ev.jog_state >= -1 && ev.jog_state <= 1) {
            delay = dur!("seconds")(60);
          } else {
            delay = dur!("msecs")(25);
          }
        } else if(ev.shuttle_state != shuttle_state && shuttle_state != -1) {
          // shuttle state changed
          // RANT: shuttle state can be 0-255, and will increase or decrease
          // depending on the direction you're turning it.. unfortunately
          // the buggy hardware doesn't generate an event for 0...
          // It means every ~25 full rotations, you miss a single click..
          if(shuttle_state == 1 && ev.shuttle_state == 255) {
            send_event("shuttle_backward");
          } else if((shuttle_state == 255 && ev.shuttle_state == 1) || ev.shuttle_state > shuttle_state) {
            send_event("shuttle_forward");
          } else if(ev.shuttle_state < shuttle_state) {
            send_event("shuttle_backward");
          }
        }
        jog_state = ev.jog_state;
        shuttle_state = ev.shuttle_state;
        trigger_jog_event(jog_state);
      }
    );
    if(!received) {
      // timeout!
      if(jog_state < -1 || jog_state > 1) {
        trigger_jog_event(jog_state);
      }
    }
  }
}

int main(string[] args) {
    bool optHelp = false;
    getopt(args,
      std.getopt.config.bundling,
      "command|c", &optCommand,
      "verbose|v", &optVerbose,
      "help|h", &optHelp
    );
    if(optHelp) {
        writeln("Usage: ", args[0], " [-v|--verbose] [-c|--command COMMAND] [-h|--help]");
        return 0;
    }
    string input_device_file = find_shuttle_input_device();
    if(input_device_file == null) {
        stderr.writeln("Couldn't find ShuttlePro V2 device");
        return 1;
    }
    auto f = File(input_device_file);
    auto events = new InputEvent[1];
    auto event = &events[0];

    auto jog_state = 0;
    auto shuttle_state = -1;
    auto got_shuttle_state = false;
    auto got_jog_state = false;
    ushort keycode = 0;
    int keyvalue = 0;

    auto tid = spawn(&receiveLoop, thisTid, optVerbose, optCommand);
    CombinedEvent combined;

    while(true) {
        f.rawRead(events);
        if(event.type == 4) continue; // ignore scancodes
        else if(event.type == 2 && event.code == 7) { // shuttle
            // NOTE: shuttle goes from 0-255, but doesn't generate
            // an event on 0.
            shuttle_state = event.value;
            got_shuttle_state = true;
        }
        else if(event.type == 2 && event.code == 8) { // jog
            jog_state = event.value;
            got_jog_state = true;
        }
        else if(event.type == 1) {
            keycode = event.code;
            keyvalue = event.value;
        }
        else if(event.type == 0) {
            // end of a sequence of events, print something..
            if(!got_jog_state)
                jog_state = 0;
            if(!got_shuttle_state)
                shuttle_state = 0;
            combined.time_secs = event.time_secs;
            combined.time_usecs = event.time_usecs;
            combined.shuttle_state = shuttle_state;
            combined.jog_state = jog_state;
            combined.key_code = keycode;
            combined.key_value = keyvalue;
            send(tid, combined);
            keycode = 0;
            keyvalue = 0;
            got_jog_state = false;
            got_shuttle_state = false;
        } else {
            // unknown event..
            stderr.writeln(event.time_secs, ".", event.time_usecs, " -> ", event.type, ",", event.code, ",", event.value);
            stderr.flush();
        }
    }
    return 0;
}
