/* 	Microblaze start up code
	Copyright Adrian McMenamin <acm538@york.ac.uk>, 2014
	Licensed under GPL v3
*/


	.global _start
	.section .vectors.reset, "ax"
	.align 2
	.ent _start
	.type _start, @function

_start:
	brai	_actualstart
	.end _start

	.section .vectors.sw_exception, "ax"
	.align 2
_vector_sw_exception:
	brai	_handle_exception

	.section .vectors.interrupt, "ax"
	.align 2
_vector_interrupt:
	brai	_interrupt_handler

	.section .vectors.breakpoint, "ax"
	.align 2
_vector_breakpoint:
	brai _handle_breakpoint

	.section .vectors.hw_exception, "ax"
	.align 2
_vector_hw_exception:
	brai	_handle_hwexception

	.section .text
	.global _actualstart
	.align 4
	.ent _actualstart
	.type _actualstart, @function

_actualstart:
	mts	rmsr, r0
	mts	rslr, r0
	addi	r8, r0, 0xFFFFFFFF
	mts	rshr, r8

	nop
	addik	r3, r0, 0x3F
	mts	rtlbx, r3



_handle_exception:
_interrupt_handler:
_handle_hwexception:
_handle_breakpoint:
	nop
	bri 0 /*endless loop if it ever works */

