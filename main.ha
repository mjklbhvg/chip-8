// See: http://devernay.free.fr/hacks/chip8/C8TECH10.HTM
use bufio;
use fmt;
use fs;
use getopt;
use io;
use os;
use strconv;

export fn main() void = {
	const cmd = getopt::parse(os::args,
		"assemble and execute chip8 programs",
		('a', "addr", "the address at which the program will be loaded, default 0x200"),
		('e', "don't assemble, just execute the file"),
		('o', "file", "write output file, don't execute"),
		"file",
	);
	defer getopt::finish(&cmd);

	if (len(cmd.args) == 0) {
		fmt::fatal("No input file.");
	};

	const infile = cmd.args[0];
	let base_address: u16 = 0x200;
	let output_file = "";
	let no_asm = false;

	for (let i = 0z; i < len(cmd.opts); i += 1) {
		switch (cmd.opts[i].0) {
		case 'a' =>
		base_address = match (stou_maybe_prefixed(cmd.opts[i].1)) {
			case let i: uint =>
				if (i > 0x1000) {
					fmt::fatalf("address has to be less than 0x1000.");
				};
				yield i: u16;
			case =>
				fmt::fatalf("error parsing number '{}':\n{}");
			};
		case 'o' =>
			output_file = cmd.opts[i].1;
		case 'e' =>
			no_asm = true;
		};
	};

	if (no_asm) {
		let f = match(os::open(infile)) {
			case let f: io::file => yield f;
			case let err: fs::error =>
				fmt::fatalf("An error occured opening '{}':\n{}",
				infile, fs::strerror(err));
		};
		run(f, base_address);
		return;
	};

	const bytecode = match(assemble_file(infile, base_address)) {
		case let b: []u8 => yield b;
		case => return;
	};
	defer free(bytecode);

	if (len(output_file) > 0) {
		let err = os::remove(output_file);

		let out_handle = os::create(output_file, fs::mode::USER_RW | fs::mode::GROUP_R | fs::mode::OTHER_R)!;
		defer io::close(out_handle)!;

		match (io::writeall(out_handle, bytecode)) {
		case let s: size =>
			if (s != len(bytecode)) {
				fmt::fatalf("For some reason '{}' was only written partially.", output_file);
			};
		case let err: io::error =>
			fmt::fatalf("Error writing file '{}':\n{}", output_file, io::strerror(err));
		};
		return;
	};

	run(&bufio::fixed(bytecode, io::mode::READ), base_address);
};
