; Compile with: NASM -fbin cpuid_0.asm

BITS 64	; Avoids nasm putting the OPCODE prefix (66h)

mov eax, 0
cpuid