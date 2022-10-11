use bufio;
use fmt;
use fs;
use io;
use math::random;
use os;
use time;
use unix::poll;
use unix::tty;

const SLEEP_BETWEEN_INSTRUCTIONS: time::duration = 1000000000 / 2000; // ns

// This is also the repaint period
const TIMER_PERIOD: time::duration    = 1000000000 / 60; // ns

const WIDTH: size = 8z; // bytes
const HEIGHT: size = 32z; // rows

type ProgramState = struct {
	V: [16]u8, // general purpose registers
	I: u16, // address register
	DT: u8, // delay timer register
	ST: u8, // sound timer register
	PC: u16, // instruction pointer
	SP: u8, // stack pointer
	stack: [16]u16, // stack supports 16 levels of nested calls

	// 4Kib Memory, Addresses 0x0 - 0x1FF are reserved
	memory: *[4096]u8,

	// 64x32 "pixels", stored as bits
	frame_buffer: *[256]u8,
	// remember when the frame buffer was just cleared.
	// repainting very soon after a clear can lead to unwanted flickering -
	// this can help avoid it in some cases
	frame_buffer_cleared: bool,

	// stores which of the 16 keys are "pressed"
	keys: [16]bool,

	running: bool,

	rng: math::random::random,
};

fn run(bytecode: io::handle, program_start: u16) void = {
	let emu  = ProgramState {
		V = [0...]: [16]u8,
		I = 0,
		DT = 0,
		ST = 0,
		PC = program_start,
		SP = 0,
		stack = [0...]: [16]u16,

		memory = init_memory(),
		frame_buffer = alloc([0...]: [256]u8),
		frame_buffer_cleared = true,

		keys = [false...],
		running = true,

		rng = math::random::init(
			time::unix(time::now(time::clock::BOOT)): u64
		),
	};
	defer {
		free(emu.frame_buffer);
		free(emu.memory);
	};

	match (io::read(bytecode, emu.memory[program_start..])) {
		case let err: io::error =>
			fmt::fatalf("An error occured reading bytecode:\n{}",
			io::strerror(err));
		case =>
			yield null;
	};

	// initialize the terminal
	// move the cursor to the top left and hide it
	fmt::print("\x1b[2J\x1b[1;1H\x1b[?25l")!;

	// reenable the cursor later
	defer fmt::print("\x1b[?25h")!;

	// enable raw mode if connected to a tty
	//
	let term: nullable *unix::tty::termios = match(unix::tty::termios_query(os::stdin_file)) {
		case let t: unix::tty::termios =>
			yield &t;
		case =>
			yield null;
	};

	if (!(term is null)) {
		unix::tty::makeraw(term as *unix::tty::termios)!;
	};
	defer {
		if (!(term is null)) {
			unix::tty::termios_restore(term as *unix::tty::termios);
		};
	};
	// flush the buffer on 'u', which is
	// the last thing written each repaint
	// Im not sure if this works at all
	bufio::setflush(os::stdout, ['u']);

	// step the execution in a loop
	let last_timer_update = time::now(time::clock::MONOTONIC);
 	for (emu.running) {
 		if (emu.PC < program_start || emu.PC >= len(emu.memory)) {
 			fmt::errorfln("Invalid instruction pointer: {}.", emu.PC)!;
 			return;
 		};
		if (emu.SP > len(emu.stack)) {
 			fmt::errorfln("invalid stack pointer: {}.", emu.SP)!;
 			return;
 		};

		keyboard_update(&emu);
 		if (!step(&emu)) {
 			fmt::errorf("Execution failure: {:02x}{:02x}",
 				emu.memory[emu.PC], emu.memory[emu.PC + 1])!;
 				return;
 		};

 		let current_time = time::now(time::clock::MONOTONIC);
 		if (time::diff(last_timer_update, current_time)
 				>= TIMER_PERIOD) {
 			last_timer_update = current_time;
			timer_update(&emu);
 		};

		// attempt to reduce cpu usage
 		time::sleep(SLEEP_BETWEEN_INSTRUCTIONS);
	};
};

fn init_memory() *[4096]u8 = {
	// Sprites for the hex characters 0-F are allocated in the reserved
	// region of memory
	return alloc([
		0xF0, 0x90, 0x90, 0x90, 0xF0,
	 	0x20 ,0x60 ,0x20 ,0x20 ,0x70,
	 	0xF0, 0x10, 0xF0, 0x80, 0xF0,
		0xF0, 0x10, 0xF0, 0x10, 0xF0,
		0x90, 0x90, 0xF0, 0x10, 0x10,
		0xF0, 0x80, 0xF0, 0x10, 0xF0,
		0xF0, 0x80, 0xF0, 0x90, 0xF0,
		0xF0, 0x10, 0x20, 0x40, 0x40,
		0xF0, 0x90, 0xF0, 0x90, 0xF0,
		0xF0, 0x90, 0xF0, 0x10, 0xF0,
		0xF0, 0x90, 0xF0, 0x90, 0x90,
		0xE0, 0x90, 0xE0, 0x90, 0xE0,
		0xF0, 0x80, 0x80, 0x80, 0xF0,
		0xE0, 0x90, 0x90, 0x90, 0xE0,
		0xF0, 0x80, 0xF0, 0x80, 0xF0,
		0xF0, 0x80, 0xF0, 0x80, 0x80,
		0...]: [4096]u8);
};

fn timer_update(emu: *ProgramState) void = {
	// if the frame buffer was just cleared,
	// don't repaint yet to give the program
	// a frame more time to do DRWs
	if (!emu.frame_buffer_cleared) {
		repaint(emu.frame_buffer, WIDTH);
	} else {
		emu.frame_buffer_cleared = false;
	};

	if (emu.DT > 0) {
		emu.DT -= 1;
	};
	if (emu.ST > 0) {
		// use the terminal bell as a sound
		fmt::print("\a")!;
		emu.ST -= 1;
	};
};

// Each update only one byte is read from stdin:
// This makes it even more impossible to input multiple keys
// in one frame than the tty already makes it,
// but it enables replaying of inputs using a file and a redirection
fn keyboard_update(emu: *ProgramState) void = {
	let inpoll = unix::poll::pollfd {
		fd = os::stdin_file,
		events = unix::poll::event::POLLIN,
		revents = 0,
	};
	
	let event = unix::poll::poll([inpoll], unix::poll::NONBLOCK);
	if (event == 0) {
		return;
	};

	let pressed_key = map_key(
		match (bufio::scanrune(os::stdin)) {
		case let r: rune => yield r;
		case => return; // ignore input errors
		}
	);

	switch (pressed_key) {
	case Input::QUIT => emu.running = false;
	case Input::NONE => return;
	case =>
		emu.keys[pressed_key] = true;
	};
};

fn step(emu: *ProgramState) bool = {
	let b0 = emu.memory[emu.PC];
	let b1 = emu.memory[emu.PC + 1];
	let n0 = b0 >> 4;
	let n1 = b0 & 0xF;
	let n2 = b1 >> 4;
	let n3 = b1 & 0xF;

	emu.PC += 2;
	switch (n0) {
	case 0x0 =>
		// SYS instruction is ignored
		switch (b1) {
		case 0x0 =>
			// This is probably the end of the program
			emu.running = false;
		case 0xE0 =>
			// Clear frame buffer
			for (let i = 0z; i < len(emu.frame_buffer); i += 1) {
				emu.frame_buffer[i] = 0;
			};
			emu.frame_buffer_cleared = true;
		case 0xEE =>
			// return
			emu.SP -= 1;
			emu.PC = emu.stack[emu.SP];
		case => return false;
		};
	case 0x1 =>
		// jump
		emu.PC = ((n1: u16) << 8) | b1;
	case 0x2 =>
		// call
		if (emu.SP >= len(emu.stack)) {
			fmt::errorf("stack overflow")!;
			emu.running = false;
			return true;
		};
		emu.stack[emu.SP] = emu.PC;
		emu.SP += 1;
		emu.PC = ((n1: u16) << 8) | b1;
	case 0x3 =>
		// skip next if equal
		if (emu.V[n1] == b1) {
			emu.PC += 2;
		};
	case 0x4 =>
		// skip next if not equal
		if (emu.V[n1] != b1) {
			emu.PC += 2;
		};
	case 0x5 =>
		// skip next if equal (register)
		if (emu.V[n1] == emu.V[n2]) {
			emu.PC += 2;
		};
	case 0x6 =>
		// load byte into register
		emu.V[n1] = b1;
	case 0x7 =>
		// add
		emu.V[n1] = emu.V[n1] + b1;
	case 0x8 =>
		switch (n3) {
		case 0x0 =>
			// load reg y into reg x
			emu.V[n1] = emu.V[n2];
		case 0x1 =>
			// bitwise or
			emu.V[n1] = emu.V[n1] | emu.V[n2];
		case 0x2 =>
			// bitwise and
			emu.V[n1] = emu.V[n1] & emu.V[n2];
		case 0x3 =>
			// bitwise xor
			emu.V[n1] = emu.V[n1] ^ emu.V[n2];
		case 0x4 =>
			// add
			let result = (emu.V[n1] + emu.V[n2]): u16;
			emu.V[n1] = result: u8;
			emu.V[0xF] = if (result >> 8 == 0) {
				yield 0;
			} else {
				yield 1;
			};
		case 0x5 =>
			// subtract y from x
			emu.V[n1] = emu.V[n1] - emu.V[n2];
			emu.V[0xF] = if (emu.V[n1] < emu.V[n2]) {
				yield 0;
			} else {
				yield 1;
			};
		case 0x6 =>
			// shift right
			emu.V[0xF] = emu.V[n1] & 1;
			emu.V[n1] = emu.V[n1] >> 1;
		case 0x7 =>
			// subtract x from y
			emu.V[n1] = emu.V[n2] - emu.V[n1];
			emu.V[0xF] = if (emu.V[n2] < emu.V[n1]) {
				yield 0;
			} else {
				yield 1;
			};
		case 0xE =>
			// shift left
			emu.V[0xF] = emu.V[n1] & 0b10000000;
			emu.V[n1] = emu.V[n1] << 1;
		case => return false;
		};
	case 0x9 =>
		// skip next if not equal (register)
		if (emu.V[n1] != emu.V[n2]) {
			emu.PC += 2;
		};
	case 0xA =>
		// load address
		emu.I = ((n1: u16) << 8) | b1;
	case 0xB =>
		// jump
		emu.PC = emu.V[0] + (((n1: u16) << 8) | b1);
	case 0xC =>
		// get random byte
		emu.V[n1] = (math::random::u32n(&emu.rng, 0x100): u8) & b1;
	case 0xD =>
	// draw sprite
	for (let i = 0z; i < n3; i += 1) {
		// the first byte alinged cell in the display buffer
		// that will be modified by this sprite
		let row = (emu.V[n2] + i) % HEIGHT;
		let prev0: size = row * WIDTH + ((emu.V[n1] % (WIDTH * 8)) / 8);

		// wrap the second cell around the screen if necessary
		let prev1 = if ((prev0 + 1) % WIDTH == 0) {
			yield prev0 - WIDTH + 1;
		} else {
			yield prev0 + 1;
		};

		// the sub cell offset of this sprite
		let x_offset = emu.V[n1] % 8;

		let new0 = (emu.memory[emu.I + i] >> x_offset);
		let new1 = (emu.memory[emu.I + i] << (8 - x_offset));

		emu.V[0xF] = if ((emu.frame_buffer[prev0] & new0) != 0) {
			yield 1;
		} else {
			yield 0;
		};
		emu.frame_buffer[prev0] = new0 ^ emu.frame_buffer[prev0];

		// if the sprite overlaps with a second byte alinged column,
		// draw that as well
		if (emu.V[n1] % 8 != 0) {
			emu.V[0xF] |= if ((emu.frame_buffer[prev1] & new1) != 0) {
				yield 1;
			} else {
				yield 0;
			};
			emu.frame_buffer[prev1] = new1 ^ emu.frame_buffer[prev1];
		};
	};
	case 0xE =>
		switch (b1) {
		case 0x9E =>
			// skip next if key is pressed
			if (emu.keys[emu.V[n1]: size]) {
				emu.PC += 2;
			};
			emu.keys[emu.V[n1]: size] = false;
		case 0xA1 =>
			// skip next if key is not pressed
			if (!emu.keys[emu.V[n1]: size]) {
				emu.PC += 2;
			};
			emu.keys[emu.V[n1]: size] = false;
		case => return false;
		};
	case 0xF =>
		switch (b1) {
		case 0x07 =>
			// get delay timer
			emu.V[n1] = emu.DT;
		case 0x0A =>
			// wait for key press
			emu.V[n1] = wait_for_key();
			if (emu.V[n1] == Input::QUIT) {
				emu.running = false;
			};
		case 0x15 =>
			// set delay timer
			emu.DT = emu.V[n1];
		case 0x18 =>
			// set sound timer
			emu.ST = emu.V[n1];
		case 0x1E =>
			// add to address register
			emu.I = emu.I + emu.V[n1];
		case 0x29 =>
			// load digit sprite
			emu.I = 5 * emu.V[n1];
		case 0x33 =>
			// get bcd
			emu.memory[emu.I] = emu.V[n1] / 100;
			emu.memory[emu.I + 1] = (emu.V[n1] / 10) % 10;
			emu.memory[emu.I + 2] = emu.V[n1] % 10;
		case 0x55 =>
			// store registers
			for (let i = 0z; i < n1; i += 1) {
				emu.memory[emu.I + i] = emu.V[i];
			};
		case 0x65 =>
			// restore registers
			for (let i = 0z; i < n1; i += 1) {
				emu.V[i] = emu.memory[emu.I + i];
			};
		case => return false;
		};
	};
	return true;
};

type Input = enum u8 {
	KEY_0 = 0x0,
	KEY_1 = 0x1,
	KEY_2 = 0x2,
	KEY_3 = 0x3,
	KEY_4 = 0x4,
	KEY_5 = 0x5,
	KEY_6 = 0x6,
	KEY_7 = 0x7,
	KEY_8 = 0x8,
	KEY_9 = 0x9,
	KEY_A = 0xA,
	KEY_B = 0xB,
	KEY_C = 0xC,
	KEY_D = 0xD,
	KEY_E = 0xE,
	KEY_F = 0xF,
	QUIT,
	NONE,
};

fn map_key(r: rune) Input = {
	switch (r) {
	// change that to your favorite keyboard layout :D
	case 'q' => return Input::QUIT;
	case 'ö' => return Input::KEY_0;
	case '1' => return Input::KEY_1;
	case '2' => return Input::KEY_2;
	case '3' => return Input::KEY_3;
	case 'x' => return Input::KEY_4;
	case 'v' => return Input::KEY_5;
	case 'l' => return Input::KEY_6;
	case 'u' => return Input::KEY_7;
	case 'i' => return Input::KEY_8;
	case 'a' => return Input::KEY_9;
	case 'ü' => return Input::KEY_A;
	case 'ä' => return Input::KEY_B;
	case '4' => return Input::KEY_C;
	case 'c' => return Input::KEY_D;
	case 'e' => return Input::KEY_E;
	case 'p' => return Input::KEY_F;
	case => return Input::NONE;
	};
};

fn wait_for_key() Input = {
	let inpoll = unix::poll::pollfd {
		fd = os::stdin_file,
		events = unix::poll::event::POLLIN,
		revents = 0,
	};
	for (true) {
		unix::poll::poll([inpoll], unix::poll::INDEF)!;
		let key = map_key(match (bufio::scanrune(os::stdin)!) {
			case let k: rune => yield k;
			case => return Input::QUIT;
		});
		if (key != Input::NONE) {
			return key;
		};
	};
	return Input::QUIT;
};

fn repaint(display_buffer: []u8, width: size) void = {
	// save cursor position
	fmt::print("\x1b[s\x1b[m")!;

	let last = false;
	for (let i = 0z; i < len(display_buffer); i += 1) {
		if (i != 0 && i % width == 0) {
			fmt::print("\r\n")!;
		};
		let byte = display_buffer[i];
		
		// msb first
		let mask: u8 = (1 << 7);
		for (mask > 0; mask = mask >> 1) {
			let current = byte & mask != 0;
			if (current != last) {
				last = current;
				if (current) {
					// reversed colors
					fmt::print("\x1b[7m")!;
				} else {
					// normal colors
					fmt::print("\x1b[m")!;
				};
			};
			fmt::print("  ")!;
		};
	};
	
	// restore cursor position
	fmt::print("\x1b[u")!;
};

