.syntax unified
.section .boot2,"ax"
.global boot2
.global _start

#define SRAM_BASE 0x20000000
#define ROM_TABLE_LOOKUP_ADDR 0x00000018
#define ROM_TABLE_CODE(A,B) (B << 8 | A)

.macro lookup_call_fn a, b, regs=""
	.ifnb \regs
		push \regs
	.endif
	movs r4,#0x18 @ Rom table lookup
	ldrh r4,[r4]

	movs r0,#0x14 @ Arg 1: func table
	ldrh r0,[r0]

	ldr r1,=(\b << 8 | \a)
	blx r4 @ Call rom table lookup, r0 has address
	mov r4, r0 @Move returned address into r4
	.ifnb \regs
		pop \regs
	.endif
	blx r4
.endm

#define CALL_MEMSET lookup_call_fn 'M','S',"{r0, r1, r2}"
#define CALL_ENTER_XIP lookup_call_fn 'C','X'
#define CALL_EXIT_XIP lookup_call_fn 'E','X'
#define CALL_MEMCPY lookup_call_fn 'M','C',"{r0, r1, r2}"

boot2:
	CALL_ENTER_XIP

	ldr r0,=SRAM_BASE
	ldr r1,=__text_start
	ldr r2,=__text_size
	CALL_MEMCPY

	ldr r0,=__rodata_start
	ldr r1,=__rodata_flash_start
	ldr r2,=__rodata_size
	CALL_MEMCPY

	CALL_EXIT_XIP

	ldr r0,=_start
	orrs r0, r0, r1
	bx r0
