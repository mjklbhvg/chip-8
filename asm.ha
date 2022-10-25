use fmt;
use fs;
use hash::fnv;
use io;
use math::random;
use os;
use strconv;
use strings;
use time;

type unknown_label = !str;
type other_error = !void;

type error = (other_error | unknown_label);

fn generate_bytecode(asm: *Assembler, code_offset: uint) ([]u8 | error) = {
	let out: []u8 = alloc([0...], asm.bytes);
	let c = 0z;

	for (let i = 0z; i < len(asm.ir); i += 1) {
		let ir = &asm.ir[i];
		resolve_label(asm, &ir.x, code_offset)?;
		resolve_label(asm, &ir.y, code_offset)?;
		resolve_label(asm, &ir.z, code_offset)?;

		switch (ir.inst) {
		case Instruction::SYS =>
			out[c] = (ir.x as uint >> 8): u8;
			out[c + 1] = (ir.x as uint): u8;
		case Instruction::CLS =>
			out[c + 1] = 0xE0;
		case Instruction::RET =>
			out[c + 1] = 0xEE;
		case Instruction::JP =>
			if (ir.x is GPRegister) {
				out[c] = 0xB0 | (ir.y as uint >> 8): u8;
				out[c + 1] = (ir.y as uint): u8;
			} else {
				out[c] = 0x10 | (ir.x as uint >> 8): u8;
				out[c + 1] = (ir.x as uint): u8;
			};
		case Instruction::CALL =>
			out[c] = 0x20 | (ir.x as uint >> 8): u8;
			out[c + 1] = (ir.x as uint): u8;
		case Instruction::SE =>
			if (ir.y is GPRegister) {
				out[c] = 0x50 | ir.x as GPRegister;
				out[c + 1] = (ir.y as GPRegister) << 4;
			} else {
				out[c] = 0x30 | ir.x as GPRegister;
				out[c + 1] = (ir.y as uint): u8;
			};
		case Instruction::SNE =>
			if (ir.y is GPRegister) {
				out[c] = 0x90 | ir.x as GPRegister;
				out[c + 1] = (ir.y as GPRegister) << 4;
			} else {
				out[c] = 0x40 | ir.x as GPRegister;
				out[c + 1] = (ir.y as uint): u8;
			};
		case Instruction::OR =>
			out[c] = 0x80 | ir.x as GPRegister;
			out[c + 1] = ((ir.y as GPRegister) << 4) | 0x1;
		case Instruction::AND =>
			out[c] = 0x80 | ir.x as GPRegister;
			out[c + 1] = ((ir.y as GPRegister) << 4) | 0x2;
		case Instruction::XOR =>
			out[c] = 0x80 | ir.x as GPRegister;
			out[c + 1] = ((ir.y as GPRegister) << 4) | 0x3;
		case Instruction::SUB =>
			out[c] = 0x80 | ir.x as GPRegister;
			out[c + 1] = ((ir.y as GPRegister) << 4) | 0x5;
		case Instruction::SUBN =>
			out[c] = 0x80 | ir.x as GPRegister;
			out[c + 1] = ((ir.y as GPRegister) << 4) | 0x7;
		case Instruction::SHR =>
			out[c] = 0x80 | ir.x as GPRegister;
			out[c + 1] = ((ir.y as GPRegister) << 4) | 0x6;
		case Instruction::SHL =>
			out[c] = 0x80 | ir.x as GPRegister;
			out[c + 1] = ((ir.y as GPRegister) << 4) | 0xE;
		case Instruction::ADD =>
			if (ir.x is AddressRegister) {
				out[c] = 0xF0 | ir.y as GPRegister;
				out[c + 1] = 0x1E;
			} else if (ir.y is GPRegister) {
				out[c] = 0x80 | ir.x as GPRegister;
				out[c + 1] = ((ir.y as GPRegister) << 4) | 0x4;
			} else {
				out[c] = 0x70 | ir.x as GPRegister;
				out[c + 1] = (ir.y as uint): u8;
			};
		case Instruction::RND =>
			out[c] = 0xC0 | ir.x as GPRegister;
			out[c + 1] = (ir.y as uint): u8;
		case Instruction::SKP =>
			out[c] = 0xE0 | ir.x as GPRegister;
			out[c + 1] = 0x9E;
		case Instruction::SKNP =>
			out[c] = 0xE0 | ir.x as GPRegister;
			out[c + 1] = 0xA1;
		case Instruction::DRW =>
			out[c] = 0xD0 | ir.x as GPRegister;
			out[c + 1] = ((ir.y as GPRegister) << 4) | (ir.z as uint & 0xF): u8;

		case Instruction::LD =>
		if (ir.x is GPRegister) {
			if (ir.y is uint) {
				out[c] = 0x60 | ir.x as GPRegister;
				out[c + 1] = ir.y as uint: u8;
			} else if (ir.y is GPRegister) {
				out[c] = 0x80 | ir.x as GPRegister;
				out[c + 1] = (ir.y as GPRegister) << 4;
			} else if (ir.y is TimerRegister) {
				out[c] = 0xF0 | ir.x as GPRegister;
				out[c + 1] = 0x07;
			} else if (ir.y is WaitForKey) {
				out[c] = 0xF0 | ir.x as GPRegister;
				out[c + 1] = 0x0A;
			} else if (ir.y is AddressRegisterDeref) {
				out[c] = 0xF0 | ir.x as GPRegister;
				out[c + 1] = 0x65;
			};
		} else if (ir.x is TimerRegister) {
			out[c] = 0xF0 | ir.y as GPRegister;
			if (ir.x as TimerRegister == TimerRegister::SOUND) {
				out[c + 1] = 0x18;
			} else { // TimerRegister::DELAY
				out[c + 1] = 0x15;
			};
		} else if (ir.x is Modifier) {
			out[c] = 0xF0 | ir.y as GPRegister;
			if (ir.x as Modifier == Modifier::FONT) {
				out[c + 1] = 0x29;
			} else { // Modifier::BCD
				out[c + 1] = 0x33;
			};
		} else if (ir.x is AddressRegister) {
			out[c] = 0xA0 | (ir.y as uint >> 8): u8;
			out[c + 1] = ir.y as uint: u8;
		} else if (ir.x is AddressRegisterDeref) {
			out[c] = 0xF0 | ir.y as GPRegister;
			out[c + 1] = 0x55;
		} else {
			return other_error;
		};
		case Instruction::DB =>
			out[c] = (ir.x as uint): u8;
			// The cursor will be only incremeted by 1 in total
			c -= 1;
		case Instruction::DW =>
			out[c] = (ir.x as uint >> 8): u8;
			out[c + 1] = (ir.x as uint): u8;
		};
		c += 2;
	};

	return out;
};

fn resolve_label(asm: *Assembler, op: *Operand, code_offset: uint) (void | unknown_label)= {
	if (*op is str) {
		let label = *op as str;
		*op = get_label_reference(label, &asm.label_table)? + code_offset;
	};
};

fn print_token(tok: Token) (void | io::error) = {
	match(tok) {
	case let s: str =>
		fmt::errorf("label reference ({})", s)?;
	case let i: uint =>
		fmt::errorf("integer literal ({})", i)?;
	case EOF =>
		fmt::error("end of file")?;
	case let i: Instruction =>
		fmt::errorf("instruction: {}", KeywordTable[i: size].0)?;
	case let t: TimerRegister =>
		fmt::errorln("timer register ")?;
		if (t == TimerRegister::SOUND) {
			fmt::error("(SOUND)")?;
		} else {
			fmt::error("(DELAY)")?;
		};
	case let gpr: GPRegister =>
		fmt::errorf("gpr V{:X}", gpr: u8)?;
	case let l: Label =>
		fmt::errorf("label ({})\n", l)?;
	case Comma =>
		fmt::error("comma")?;
	case Newline =>
		fmt::error("newline")?;
	case CommentStart =>
		fmt::error("comment start")?;
	case AddressRegister =>
		fmt::error("address register")?;
	case AddressRegisterDeref =>
		fmt::error("address register dereference")?;
	case let m: Modifier =>
		switch (m) {
			case Modifier::FONT =>
				fmt::errorf("font modifier (F)")?;
			case Modifier::BCD =>
				fmt::errorf("bcd modifier (B)")?;
		};
	case =>
		fmt::error("unimplemeted tok2str token :(")?;
	};
};

fn check_bounds(asm: *Assembler, i: uint, max: uint) bool = {
	if (i > max) {
		error_prefix_ln(asm.line_number);
		fmt::errorf("Integer bigger than maximum size 0x{:X} > 0x{:X}\n", i, max)!;
		asm.error_count += 1u;
		return false;
	};
	return true;
};

fn unexpected_token(asm: *Assembler, tok: Token, expected: str) void = {
	error_prefix_ln(asm.line_number);
	fmt::errorf("Expected {}, not ", expected)!;
	print_token(tok)!;
	fmt::errorln("")!;
	asm.error_count += 1u;
};

fn parse_instruction(asm: *Assembler, inst: Instruction) (Token | bool) = {
	let x: Operand = false: NoOperand;
	let y: Operand = false: NoOperand;
	let z: Operand = false: NoOperand;

	switch (inst) {
	case Instruction::SYS =>
		x = match(next_token(asm)) {
		case let s: str => yield s;
		case let i: uint =>
			if (!check_bounds(asm, i, 0xFFF)) {
				return false;
			};
			yield i;
		case let tok: Token =>
			unexpected_token(asm, tok, "address or label reference");
			return tok;
		};
		asm.bytes += 2;

	// same as sys, but for some reason I can't put them in the same case
	case Instruction::CALL =>
		x = match(next_token(asm)) {
		case let s: str => yield s;
		case let i: uint =>
			if (!check_bounds(asm, i, 0xFFF)) {
				return false;
			};
			yield i;
		case let tok: Token =>
			unexpected_token(asm, tok, "address or label reference");
			return tok;
		};
		asm.bytes += 2;
	case Instruction::CLS, Instruction::RET => asm.bytes += 2;
	case Instruction::JP =>
		x = match(next_token(asm)) {
		case let s: str => yield s;
		case let i: uint =>
			if (!check_bounds(asm, i, 0xFFF)) {
				return false;
			};
			yield i;
		case let r: GPRegister =>
			if (r: u8 != 0u) {
				error_prefix_ln(asm.line_number);
				fmt::errorfln("Invalid register for JP destination (V{:X})", r: u8)!;
				asm.error_count += 1;
				suggestion_prefix();
				fmt::errorln("Did you mean 'JP V0, addr'?")!;
				return false;
			};
			yield r;
		case let tok: Token =>
			unexpected_token(asm, tok, "general purpose register, address or label reference");
			return tok;
		};

		if (x is GPRegister) {
			let comma = next_token(asm);
			if (!(comma is Comma)) {
				unexpected_token(asm, comma, "comma");
				return comma;
			};
			y = match(next_token(asm)) {
			case let s: str => yield s;
			case let i: uint =>
				if (!check_bounds(asm, i, 0xFFF)) {
					return false;
				};
				yield i;
			case let tok: Token =>
				unexpected_token(asm, tok, "address or label reference");
				return tok;
			};
		};
		asm.bytes += 2;
	case Instruction::SE, Instruction::SNE =>
		x = match(next_token(asm)) {
		case let r: GPRegister => yield r;
		case let tok: Token =>
			unexpected_token(asm, tok, "general purpose register");
			return tok;
		};

		let comma = next_token(asm);
		if (!(comma is Comma)) {
			unexpected_token(asm, comma, "comma");
			return comma;
		};

		y = match(next_token(asm)) {
		case let r: GPRegister => yield r;
		case let i: uint =>
			if (!check_bounds(asm, i, 0xFF)) {
				return false;
			};
			yield i;
		case let tok: Token =>
			unexpected_token(asm, tok, "general purpose register or byte");
			return tok;
		};
		asm.bytes += 2;
	case Instruction::OR, Instruction::AND, Instruction::XOR,
			Instruction::SUB, Instruction::SUBN,
			Instruction::SHL, Instruction::SHR =>
		x = match(next_token(asm)) {
		case let r: GPRegister => yield r;
		case let tok: Token =>
			unexpected_token(asm, tok, "general purpose register");
			return tok;
		};

		let comma = next_token(asm);
		if (!(comma is Comma)) {
			unexpected_token(asm, comma, "comma");
			return comma;
		};

		y = match(next_token(asm)) {
		case let r: GPRegister => yield r;
		case let tok: Token =>
			unexpected_token(asm, tok, "general purpose register");
			return tok;
		};
		asm.bytes += 2;

	case Instruction::ADD =>
		x = match (next_token(asm)) {
		case let r: GPRegister => yield r;
		case let a: AddressRegister => yield a;
		case let tok: Token =>
			unexpected_token(asm, tok, "general purpose register or address register");
			return tok;
		};

		let comma = next_token(asm);
		if (!(comma is Comma)) {
			unexpected_token(asm, comma, "comma");
			return comma;
		};

		y = match (next_token(asm)) {
		case let r: GPRegister => yield r;
		case let i: uint =>
			if (!check_bounds(asm, i, 0xFF)) {
				return false;
			};
			yield i;
		case let tok: Token =>
			unexpected_token(asm, tok, "general purpose register, or byte ");
			return tok;
		};

		if ((x is AddressRegister) && !(y is GPRegister)) {
			unexpected_token(asm, y: (str | uint), "general purpose register");
			suggestion_prefix();
			fmt::errorln("Did you mean 'ADD I, Vx'?")!;
			return false;
		};
		asm.bytes += 2;
		
	case Instruction::SKP, Instruction::SKNP =>
		x = match (next_token(asm)) {
		case let r: GPRegister => yield r;
		case let tok: Token =>
			unexpected_token(asm, tok, "general purpose register");
			return tok;
		};
		asm.bytes += 2;

	case Instruction::RND =>
		x = match (next_token(asm)) {
		case let r: GPRegister => yield r;
		case let tok: Token =>
			unexpected_token(asm, tok, "general purpose register");
			return tok;
		};

		let comma = next_token(asm);
		if (!(comma is Comma)) {
			unexpected_token(asm, comma, "comma");
			return comma;
		};

		y = match (next_token(asm)) {
		case let i: uint =>
			if (!check_bounds(asm, i, 0xFF)) {
				return false;
			};
			yield i;
		case let tok: Token =>
			unexpected_token(asm, tok, "byte");
			return tok;
		};
		asm.bytes += 2;

	case Instruction::DRW =>
		x = match (next_token(asm)) {
		case let r: GPRegister => yield r;
		case let tok: Token =>
			unexpected_token(asm, tok, "general purpose register");
			return tok;
		};

		let comma = next_token(asm);
		if (!(comma is Comma)) {
			unexpected_token(asm, comma, "comma");
			return comma;
		};

		y = match (next_token(asm)) {
		case let r: GPRegister => yield r;
		case let tok: Token =>
			unexpected_token(asm, tok, "general purpose register");
			return tok;
		};

		let comma = next_token(asm);
		if (!(comma is Comma)) {
			unexpected_token(asm, comma, "comma");
			return comma;
		};

		z = match (next_token(asm)) {
		case let i: uint =>
			if (!check_bounds(asm, i, 0xF)) {
				return false;
			};
			yield i;
		case let tok: Token =>
			unexpected_token(asm, tok, "nibble");
			return tok;
		};

	asm.bytes += 2;
	case Instruction::LD =>
		x = match(next_token(asm)) {
		case let r: GPRegister => yield r;
		case let t: TimerRegister => yield t;
		case let m: Modifier => yield m;
		case let a: AddressRegister => yield a;
		case let a: AddressRegisterDeref => yield a;
		case let tok: Token =>
			unexpected_token(asm, tok, "general purpose register, timer register, modifier or address register with optional dereference");
			return tok;
		};

		let comma = next_token(asm);
		if (!(comma is Comma)) {
			unexpected_token(asm, comma, "comma");
			return comma;
		};
		if (x is GPRegister) {
			y = match (next_token(asm)) {
			case let i: uint =>
				if (!check_bounds(asm, i, 0xFF)) {
					return false;
				};
				yield i;
			case let r: GPRegister => yield r;
			case let t: TimerRegister =>
				if (t == TimerRegister::SOUND) {
					unexpected_token(asm, t, "delay timer (DT)");
					suggestion_prefix();
					fmt::errorfln("Did you mean 'LD V{:X}, DT'?", x: GPRegister: u8)!;
					return false;
				};
				yield t;
			case let k: WaitForKey => yield k;
			case let a: AddressRegisterDeref => yield a;
			case let tok: Token =>
				unexpected_token(asm, tok, "byte, general purpose register, delay timer (DT), key press (K) or dereference of address register");
				return tok;
			};
		} else if ((x is TimerRegister) || (x is Modifier)
				|| (x is AddressRegisterDeref)) {
			y = match (next_token(asm)) {
			case let r: GPRegister => yield r;
			case let tok: Token =>
				unexpected_token(asm, tok, "general purpose register");
				return tok;
			};

		} else if (x is AddressRegister) {
			y = match (next_token(asm)) {
			case let s: str => yield s;
			case let i: uint =>
				if (!check_bounds(asm, i, 0xFFF)) {
					return false;
				};
				yield i;
			case let tok: Token =>
				unexpected_token(asm, tok, "address or label reference");
				return tok;
			};
		};
		asm.bytes += 2;

	case Instruction::DB =>
		x = match (next_token(asm)) {
		case let i: uint =>
			if (!check_bounds(asm, i, 0xFF)) {
				return false;
			};
			yield i;
		case let tok: Token =>
			unexpected_token(asm, tok, "byte");
			return tok;
		};
		asm.bytes += 1;

	case Instruction::DW =>
		x = match (next_token(asm)) {
		case let i: uint =>
			if (!check_bounds(asm, i, 0xFFFF)) {
				return false;
			};
			yield i;
		case let tok: Token =>
			unexpected_token(asm, tok, "word");
			return tok;
		};
		asm.bytes += 2;

	case =>
		fmt::errorfln("unimplemeted instruction: {}", inst: uint)!;
		return false;
	};

	append(asm.ir, AssemblyInstruction {inst = inst, x = x, y = y, z = z});
	return false;
};

fn parse_tokens(asm: *Assembler) void = {
	let comment_active = false;
	let expect_instruction = true;
	let pending_token: (Token | bool) = false;
		
	for (true) {
		let tok = if (pending_token is Token) {
			defer pending_token = false;
			yield pending_token as Token;
		} else {
			yield next_token(asm);
		};

		if (comment_active) {
			if (!((tok is Newline) || (tok is EOF))) {
				continue;
			};
		};
		match (tok) {
			case EOF => break;
			case let i: Instruction =>
				if (expect_instruction) {
					pending_token = parse_instruction(asm, i);
					expect_instruction = false;
				};
			case CommentStart =>
				comment_active = true;
			case Newline =>
				comment_active = false;
				expect_instruction = true;
				asm.line_number += 1;
			case let label: Label =>
				if (add_label(label, asm.bytes: uint, &asm.label_table)) {
					asm.error_count += 1;
				};
			case let tok: Token =>
				unexpected_token(asm, tok, "Instruction, Comment or Newline");
				// comment out the rest of the line
				comment_active = true;
		};
	};
};

fn is_white_space(c: u8) bool = {
	return (c == ' ' || c == '\t' || c == '\r');
};

type EOF = bool;
type CommentStart = bool;
type Newline = bool;
type AddressRegister = bool;
type AddressRegisterDeref = bool;
type Comma = bool;
type WaitForKey = bool;
type GPRegister = u8;
type Label = str;

type Instruction = enum {SYS, CLS, RET, JP, CALL, SE, SNE, OR, AND, XOR, SUB, SUBN, ADD, SHR, SHL, RND, DRW, SKP, SKNP, LD, DB, DW};

type TimerRegister = enum {SOUND, DELAY};

type Modifier = enum {FONT, BCD};

type Token = (uint | str | EOF | Instruction | TimerRegister | GPRegister
	| CommentStart | Newline | Label | Comma | Modifier
	| AddressRegister | AddressRegisterDeref | WaitForKey);

fn next_token(asm: *Assembler) Token = {
	for (asm.cursor < len(asm.source)) {
		if (!is_white_space(asm.source[asm.cursor])) {
			break;
		};
		asm.cursor += 1;
	};

	let token_start = asm.cursor;
	if (token_start >= len(asm.source) - 1) {
		return true: EOF;
	};

	for (asm.cursor < len(asm.source); asm.cursor += 1) {
		let ch = asm.source[asm.cursor];
		if (ch == ';' || ch == '\n' || ch == ','
				|| is_white_space(ch)) {
			if (asm.cursor - token_start == 0) {
				asm.cursor += 1;
			};
			break;
		};
	};
	let token_str = strings::fromutf8(asm.source[token_start..asm.cursor])!;
	if (len(token_str) == 2 && strings::hasprefix(token_str, 'V')) {
		let v = strconv::stou8b(strings::sub(token_str, 1, 2), 16);
		if (v is u8) {
			return v as u8: GPRegister;
		};
	};

	if (len(token_str) > 1 && strings::hassuffix(token_str, ':')) {
		return strings::sub(token_str, 0, len(token_str) - 1): Label;
	};
	
	let v = stou_maybe_prefixed(token_str);
	if (v is uint) {
		return v as uint;
	};

	for (let i = 0z; i < len(KeywordTable); i += 1) {
		if (strings::compare(KeywordTable[i].0, token_str) == 0) {
			return KeywordTable[i].1;
		};
	};

	return token_str;
};

fn stou_maybe_prefixed(s: str) (uint | strconv::overflow | strconv::invalid) = {
	let base: uint = 10;
	if (strings::hasprefix(s, "0x")) {
		base = 16;
		s = strings::sub(s, 2, strings::end);
	};
	return strconv::stoub(s, base);
};

fn error_prefix_ln(line_number: uint) void = {
	fmt::errorf("\x1b[31;1;5mError\x1b[0m @ {}: ", line_number)!;
};

fn error_prefix() void = {
	fmt::errorf("\x1b[31;1;5mError\x1b[0m: ")!;
};

fn suggestion_prefix() void = {
	fmt::error("\t\x1b[32mSuggestion:\x1b[0m ")!;
};

type LabelTable = struct {
	buckets: [64][]HashedLabel,
};

type HashedLabel = struct {
	hash: u32,
	reference: uint,
};

fn get_label_reference(label_reference: str, table: *LabelTable)
		(uint | unknown_label) = {
	let key = hash::fnv::string32(label_reference);
	let index = key % len(table.buckets);

	for (let i = 0z; i < len(table.buckets[index]); i += 1) {
		if (table.buckets[index][i].hash == key) {
			return table.buckets[index][i].reference;
		};
	};

	return label_reference: unknown_label;
};

fn add_label(label: Label, reference: uint, table: *LabelTable) bool = {
	let key = hash::fnv::string32(label);
	let index = key % len(table.buckets);
	
	for (let i = 0z; i < len(table.buckets[index]); i += 1) {
		if (table.buckets[index][i].hash == key) {
			error_prefix();
			fmt::errorfln("Duplicate label '{}'", label)!;
			return true;
		};
	};
	
	append(table.buckets[index], HashedLabel {
		hash = key,
		reference = reference,
	});
	return false;
};

const KeywordTable: [](str, (Instruction | Modifier | TimerRegister
		| Newline | Comma | CommentStart | AddressRegister
		| AddressRegisterDeref | WaitForKey)) = [
	("SYS", Instruction::SYS),
	("CLS", Instruction::CLS),
	("RET", Instruction::RET),
	("JP", Instruction::JP),
	("CALL", Instruction::CALL),
	("SE", Instruction::SE),
	("SNE", Instruction::SNE),
	("OR", Instruction::OR),
	("AND", Instruction::AND),
	("XOR", Instruction::XOR),
	("SUB", Instruction::SUB),
	("SUBN", Instruction::SUBN),
	("ADD", Instruction::ADD),
	("SHR", Instruction::SHR),
	("SHL", Instruction::SHL),
	("RND", Instruction::RND),
	("DRW", Instruction::DRW),
	("SKP", Instruction::SKP),
	("SKNP", Instruction::SKNP),
	("LD", Instruction::LD),
	("DB", Instruction::DB),
	("DW", Instruction::DW),
	("F", Modifier::FONT),
	("B", Modifier::BCD),
	("ST", TimerRegister::SOUND),
	("DT", TimerRegister::DELAY),
	("K", true: WaitForKey),
	("\n", true: Newline),
	(",", true: Comma),
	(";", true: CommentStart),
	("I", true: AddressRegister),
	("[I]", true: AddressRegisterDeref),
];

type Assembler = struct {
	ir: []AssemblyInstruction,
	label_table: LabelTable,
	source: []u8,
	cursor: size,
	bytes: size,
	line_number: uint,
	error_count: uint,
};

type NoOperand = bool;
type Operand = (uint | str | GPRegister | Modifier | AddressRegister | AddressRegisterDeref | TimerRegister | NoOperand | WaitForKey);

type AssemblyInstruction = struct {
	inst: Instruction,
	// Operands
	x: Operand,
	y: Operand,
	z: Operand,
};

fn assemble_file(infile: str, code_offset: uint) ([]u8 | void)= {
	let source_fd = match (os::open(infile)) {
		case let f: io::file => yield f;
		case let err: fs::error =>
			fmt::errorfln("Error opining file '{}':\n{}",
				infile, fs::strerror(err))!;
			return;
	};
	defer io::close(source_fd)!;

	let asm = Assembler {
		ir = [],
		label_table = LabelTable {
			buckets = [[]...],
		},
		source = match (io::drain(source_fd)) {
			case let s: []u8 => yield s;
			case let err: io::error =>
				fmt::errorfln("Error reading file '{}':\n{}",
					infile, io::strerror(err))!;
				return;
		},
		cursor = 0z,
		bytes = 0z,
		line_number = 1u,
		error_count = 0u,
	};
	
	defer {
		delete(asm.ir[0..]);
		free(asm.ir);
		for (let i = 0z; i < len(asm.label_table.buckets); i += 1) {
			delete(asm.label_table.buckets[i][0..]);
			free(asm.label_table.buckets[i]);
		};
		free(asm.source);
	};
	
	parse_tokens(&asm);
	if (asm.error_count > 0) {
		return;
	};
	match (generate_bytecode(&asm, code_offset)) {
		case let err: unknown_label =>
			error_prefix();
			fmt::errorfln("unknown label '{}'", err)!;
			return;
		case let out: []u8 => return out;
		case => return;

	};
};

