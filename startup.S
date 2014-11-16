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

	.org 0x100
	.section .text
	.global _actualstart
	.align 4
	.ent _actualstart
	.type _actualstart, @function

_actualstart:
	addik	r3, r0, 0x3F	/* Microblaze TLB has 64 entries */
_zeroouttlb:
	mts	rtlbx, r3
	mts	rtlbhi, r0
	mts	rtlblo, r0
	bgtid	r3, _zeroouttlb	/* Uses delay slot */
	addik	r3, r3, -1

_setkernelpid:
	mts	rpid, r0
	nop
	bri	4		/* sync required */

	/* setup TLB0 */
	ori	r11, r0, 0x0000
	mts	rtlbx, r11
	ori	r4, r0, 0x00
	ori	r4, r4, 0x0300
	mts	rtlblo, r4

	ori	r4, r0, 0x00
	ori	r4, r0, 0x02C0
	mts	rtlbhi, r4

	/* setup TLB1 - page table space */
	ori	r11, r0, 0x01
	mts	rtlbx, r11
	ori	r4, r0, 0x200000
	ori	r4, r4,	0x0300
	mts	rtlblo, r4

	ori	r4, r0, 0x300000
	ori	r4, r4, 0x02C0
	mts	rtlbhi, r4

	/* Turn on VM */
	mfs	r4, rmsr
	nop
	ori	r4, r0, 0x2000
	mts	rmsr, r4
	nop

	/* Populate page table */
	/* Zero the memory first of all */
	ori	r11, r0, 0x80
	ori	r12, r0, 0x300000
	ori	r19, r0, 0x08
	ori	r20, r0, 0x00
	
outer_zero_loop:
	addik	r11, r11, -1
	beqid	r11, finished_zero_loop
	nop

inner_zero_loop:
	sw	r0, r12, r20
	addik	r20, r20, 0x04
	rsub	r21, r20, r19
	bltid	r21, end_inner_zero_loop
	nop
	braid	inner_zero_loop
	nop

end_inner_zero_loop:
	add	r12, r12, r19
	braid	outer_zero_loop
	ori	r20, r0, 0x00	

finished_zero_loop:
	nop		

/* Copy TLB entries */

	ori	r11, r0, 0x40
	ori	r12, r0, 0x300000
	ori	r19, r0, 0x08
	ori	r20, r0, 0x00

tlb_loop:
	addik	r11, r11, -1
	beqid	r11, finished_tlb_loop
	mts	rtlbx, r20
	mfs	r21, rtlbhi
	sw	r21, r12, r0
	mfs	r21, rtlblo
	swi	r21, r12, 0x04
	addik	r20, r20, 0x01
	braid	tlb_loop
	add	r12, r12, r19

finished_tlb_loop:
	nop
/* cheeky switch back to real mode */
	mfs	r4, rmsr
	nop
	andni	r4, r4, 0x2000
	mts	rmsr, r4
	nop	

_handle_exception:
_interrupt_handler:
_handle_hwexception:
_handle_breakpoint:
	nop
	bri 0 /*endless loop if it ever works */

