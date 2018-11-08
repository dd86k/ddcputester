module m_latency;

import core.stdc.stdio :
	puts, printf, FILE, fopen, fseek, ftell, fread, SEEK_SET, SEEK_END;
import ddcput;
import os_utils;
import memmgr;
import misc;

// NOTE: *_TEST.size code arrays returns _pointer_ size
version (X86) {
version (Windows) {
	immutable ubyte* PRE_TEST = [
		// test -- Sets [ecx+4], 1234 and returns
		//0x8B, 0x4C, 0x24, 0x04, 0xC7, 0x01, 0xD2, 0x04, 0x00, 0x00, 0xC3

		// pre-x86-windows.asm
		0x8B, 0x4C, 0x24, 0x04, 0x89, 0x79, 0x14, 0x89, 0x71, 0x18, 0x89, 0xCE,
		0x8B, 0x7E, 0x10, 0x0F, 0x31, 0x89, 0x06, 0x89, 0x56, 0x04
	];
	enum PRE_TEST_SIZE = 22;

	immutable ubyte* POST_TEST = [
		// post-x86-windows.asm
		0x4F, 0x0F, 0x85, 0xF9, 0xFF, 0xFF, 0xFF, 0x0F, 0x31, 0x89, 0x46, 0x08,
		0x89, 0x56, 0x0C, 0x89, 0xF1, 0x8B, 0x79, 0x14, 0x8B, 0x71, 0x18, 0xC3
	];
	enum POST_TEST_SIZE = 24;
	enum POST_TEST_JMP = 3;	/// Jump patch offset, 0-based, aims at lowest byte
	enum POST_TEST_OFFSET_JMP = 7;	// DEC+JMP+IMM32
} // version Windows

version (linux) {
	static assert(0, "x86-linux PRE_TEST code needed");
	static assert(0, "x86-linux POST_TEST code needed");
} // version linux
} else version (X86_64) {
version (Windows) {
	immutable ubyte* PRE_TEST = [
		// pre-amd64-windows.asm
		0x48, 0x89, 0x79, 0x14, 0x48, 0x89, 0x71, 0x1C, 0x48, 0x89, 0xCE, 0x48,
		0x31, 0xFF, 0x8B, 0x7E, 0x10, 0x0F, 0x31, 0x89, 0x06, 0x89, 0x56, 0x04
	];
	enum PRE_TEST_SIZE = 24;

	immutable ubyte* POST_TEST = [
		// post-amd64-windows.asm
		0x48, 0xFF, 0xCF, 0x0F, 0x85, 0x00, 0x00, 0x00, 0x00, 0x0F, 0x31, 0x89,
		0x46, 0x08, 0x89, 0x56, 0x0C, 0x48, 0x89, 0xF1, 0x48, 0x8B, 0x79, 0x14,
		0x48, 0x8B, 0x71, 0x18, 0xC3
	];
	enum POST_TEST_SIZE = 29;
	enum POST_TEST_JMP = 5;	/// Jump patch offset, 0-based, aims at lowest byte
	enum POST_TEST_OFFSET_JMP = 9;	// DEC+JMP+IMM32
}

version (linux) {
	static assert(0, "amd64-linux PRE_TEST code needed");
	static assert(0, "amd64-linux POST_TEST code needed");
}
}

debug pragma(msg, "sizeof(__TEST_SETTINGS): ", __TEST_SETTINGS.sizeof);

struct __TEST_SETTINGS { align(1):
	union {
		ulong t1;
		struct {
			uint t1_l;	// [0]
			uint t1_h;	// [4]
		}
	}
	union {
		ulong t2;
		struct {
			uint t2_l;	// [8]
			uint t2_h;	// [12]
		}
	}
	uint runs;	// [16]
	version (X86) {
		uint R0;	// [20]
		uint R1;	// [24]
	}
	version (X86_64) {
		ulong R0;	// [20]
		ulong R1;	// [28]
	}
}

pragma(msg, "__TEST_SETTINGS.t1_l@", __TEST_SETTINGS.t1_l.offsetof);
pragma(msg, "__TEST_SETTINGS.t1_h@", __TEST_SETTINGS.t1_h.offsetof);
pragma(msg, "__TEST_SETTINGS.t2_l@", __TEST_SETTINGS.t2_l.offsetof);
pragma(msg, "__TEST_SETTINGS.t2_h@", __TEST_SETTINGS.t2_h.offsetof);
pragma(msg, "__TEST_SETTINGS.runs@", __TEST_SETTINGS.runs.offsetof);

int start_latency() {
	if (core_check == 0) {
		puts("ABORT: RDTSC instruction not available");
		return 1;
	}

	debug printf("file: %s\n", Settings.filepath);

	core_init;	// init ddcputester
	debug printf("delta penalty: %d\n", Settings.delta);

	switch (core_load_file(Settings.filepath)) {
	case 0: break;
	case 1:
		puts("ABORT: File could not be opened");
		return 4;
	default:
		puts("ABORT: Unknown error on file load");
		return 0xfe;
	}

	__TEST_SETTINGS s = void;
	s.runs = DEFAULT_RUNS;
	const float result = core_test(&s);
	printf("Result: ~%f cycles\n", result);

	return 0;
}

/// (x86) Check if RDTSC is present
/// Returns: Non-zero if RDTSC is supported
extern (C)
uint core_check() {
	/*version (GNU) asm {
		"mov $1, %%eax\n"~
		"cpuid\n"~
		"and $16, %%edx\n"~
		"mov %%edx, %%eax\n"~
		"ret"
	} else */asm { naked;
		mov EAX, 1;
		cpuid;
		and EDX, 16;	// EDX[4] -- RDTSC
		mov EAX, EDX;
		ret;
	}
}

/// Initiates essential stuff and calculate delta penalty for measuring
extern (C)
void core_init() {
	debug puts("[debug] rdtsc+mov penalty");
	__TEST_SETTINGS s;
	s.runs = DEFAULT_RUNS;
	version (X86) asm {
		lea ESI, s;
		mov EDI, [ESI + 16];
		rdtsc;
		mov [ESI], EAX;
		mov [ESI + 4], EDX;
_TEST:
		dec EDI;
		jnz _TEST;
		rdtsc;
		mov [ESI + 8], EAX;
		mov [ESI + 12], EDX;
	}
	version (X86_64) asm {
		lea RSI, s;
		xor RDI, RDI;
		mov EDI, [RSI + 16];
		rdtsc;
		mov [RSI], EAX;
		mov [RSI + 4], EDX;
_TEST:
		dec RDI;
		jnz _TEST;
		rdtsc;
		mov [RSI + 8], EAX;
		mov [RSI + 12], EDX;
	}
	Settings.delta = cast(uint)((cast(float)s.t2_l - s.t1_l) / DEFAULT_RUNS);
	debug {
		printf("[debug] %u %u\n", s.t1_h, s.t1_l);
		printf("[debug] %u %u\n", s.t2_h, s.t2_l);
	}

	debug puts("[debug] __mem_create");
	mainbuf = __mem_create;
	if (cast(size_t)mainbuf == 0) {
		puts("Could not initialize mainbuf");
	}
	mainbuf.code[0] = 0;	// test write
}

/**
 * Load user code into memory including pre-test and post-test code.
 * Params:
 *   path = File path (binary data)
 * Returns:
 *   0 on success
 *   1 on file could not be open
 *   2 on file could not be loaded into memory
 */
extern (C)
int core_load_file(immutable(char)* path) {
	import core.stdc.string : memmove;
	import os_utils : os_pexist;

	ubyte* buf = cast(ubyte*)mainbuf;

	// pre-test code
	debug puts("[debug] pre-test memmove");
	memmove(buf, PRE_TEST, PRE_TEST_SIZE);
	buf += PRE_TEST_SIZE;

	// user code
	debug puts("[debug] open user code");
	FILE* f = fopen(path, "rb");
	if (cast(uint)f == 0) return 1;

	debug puts("[debug] fseek end");
	fseek(f, 0, SEEK_END);

	debug puts("[debug] ftell");
	const uint fl = ftell(f);	/// File size (length)

	debug printf("[debug] fseek set (from %u Bytes)\n", fl);
	fseek(f, 0, SEEK_SET);

	debug puts("[debug] fread");
	fread(buf, fl, 1, f);
	buf += fl;

	// post-test code + patch
	debug puts("[debug] post-test memmove");
	memmove(buf, POST_TEST, POST_TEST_SIZE);

	int jmp = -(fl + POST_TEST_OFFSET_JMP); // + DEC + JNE + OP
	debug printf("[debug] post-test jmp patch (jmp:");
	*cast(int*)(buf + POST_TEST_JMP) = jmp;

	debug {
		printf("%d -- %X)\n", jmp, jmp);
		ubyte* p = cast(ubyte*)mainbuf;

		uint m = PRE_TEST_SIZE;
		printf("[debug] PRE [%3d] -- ", m);
		do printf("%02X ", *p++); while (--m);
		putchar('\n');

		m = fl;
		printf("[debug] TEST[%3d] -- ", m);
		do printf("%02X ", *p++); while (--m);
		putchar('\n');

		m = POST_TEST_SIZE;
		printf("[debug] POST[%3d] -- ", m);
		do printf("%02X ", *p++); while (--m);
		putchar('\n');
	}

	debug puts("[debug] __mem_protect");
	__mem_protect(mainbuf);

	return 0;
}

/*version (X86_ANY) extern (C)
float core_test(__TEST_SETTINGS* s) {
	version (X86) asm { mov EDI, s; }
	version (X86_64) asm { mov RDI, s; }
	asm {
		mov ESI, DEFAULT_RUNS;
		rdtsc;
		mov [EDI], EAX;
		mov [EDI + 4], EDX;
_TEST:
		mov EAX, 0;
		cpuid;

		dec ESI;
		jnz _TEST;
		rdtsc;
		mov [EDI + 8], EAX;
		mov [EDI + 12], EDX;
	}
	debug {
		printf("%u %u\n", s.t1_h, s.t1_l);
		printf("%u %u\n", s.t2_h, s.t2_l);
	}
	return (cast(float)s.t2_l - s.t1_l - delta) / DEFAULT_RUNS;
}*/

float core_test(__TEST_SETTINGS* s) {
	debug puts("[debug] get __test");
	extern (C) void function(__TEST_SETTINGS*)
		__test = cast(void function(__TEST_SETTINGS*))mainbuf;

	debug puts("[debug] call __test");
	__test(s);

	debug {
		printf("[debug] %u %u\n", s.t1_h, s.t1_l);
		printf("[debug] %u %u\n", s.t2_h, s.t2_l);
	}

	return (cast(float)s.t2_l - s.t1_l - Settings.delta) / DEFAULT_RUNS;
}