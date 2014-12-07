/* 	Microblaze start up code
	Copyright Adrian McMenamin <acm538@york.ac.uk>, 2014
	Licensed under GPL v3
*/

	.set PTECNT, 0x80
	.set TLBCNT, 0x40
	.set EX, 0x200
	.set WR, 0x100
	.set VALID, 0x40
	.set PAGE4K, 0x080
	.set PAGE64K, 0x180
	.set PAGE4KMASK, 0xFFFFF000
	.set PAGE64KMASK, 0xFFFF0000
	.set PAGE1M, 0x280
	.set PTE_SIZE, 0x08
	.set PTE_SIZE_HALF, 0x04
	.set SECOND_MAP_PHYS, 0x200000
	.set SECOND_MAP_VIRT, 0x300000
	.set STACK_MAP_PHYS, 0xFFFF0000
	.set STACK_MAP_VIRT, 0xFFFF0000
	.set STACK_BOTTOM, 0xFFFFFFFF
	.set FRAME_BASE, 0x500000
	.set VM_ON, 0x2502
	.set PAGE_SZ, 0x1000
	.set MAXPINNED,	0x03	/* how many pinned TLBs/PTEs */
	.set TLBMAXED,	0x100	/* hi word is tlbpointer, lo is Y or N */
	.set PTEMAXED,	0x104
	.set CLOCK_SWEEP, 0x04

	.macro switchex
	addi	r5, r5, 0x01
	rsub	r6, r5, r4
	.endm	

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
	brai	_exception_handler

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
	brai	_hw_exception_handler

	.org 0x100
	.section .text
	.global _actualstart
	.align 4
	.ent _actualstart
	.type _actualstart, @function

_actualstart:
	addik	r3, r0, TLBCNT - 1
	ori	r4, r0, MAXPINNED
	swi	r4, r0, PTEMAXED	/* write out start point */
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
	/* 1 <-> mapping for 1MB page at 0x00 */
	ori	r11, r0, 0x0000
	mts	rtlbx, r11
	ori	r4, r0, EX|WR
	mts	rtlblo, r4
	ori	r4, r0, VALID|PAGE1M 
	mts	rtlbhi, r4

	/* setup TLB1 - page table space */
	/* maps SECOND_MAP_PHYS <-> SECOND_MAP_VERT for 4k */
	ori	r11, r0, 0x01
	mts	rtlbx, r11
	ori	r4, r0, SECOND_MAP_PHYS|EX|WR
	mts	rtlblo, r4
	ori	r4, r0, SECOND_MAP_VIRT|VALID|PAGE4K
	mts	rtlbhi, r4

	/* setup TLB2 - 64K stack */
	ori	r11, r0, 0x02
	mts	rtlbx, r11
	ori	r4, r0, STACK_MAP_PHYS
	andi	r4, r4, PAGE64KMASK
	ori	r4, r4, WR
	mts	rtlblo, r4

	ori	r4, r0, STACK_MAP_VIRT
	andi	r4, r4, PAGE64KMASK
	ori	r4, r4, VALID|PAGE64K
	mts	rtlbhi, r4

	/* set stack pointer registers */
	ori	r4, r0, STACK_MAP_VIRT
	mts	rslr, r4
	ori	r4, r0, STACK_BOTTOM 
	mts	rshr, r4
	/* set r1 as stack pointer */
	ori	r1, r0, STACK_BOTTOM - 3 

turn_on_vm:
	mfs	r4, rmsr
	nop
	ori	r4, r0, VM_ON 
	mts	rmsr, r4
	nop

	/* Populate page table */
	/* Zero the memory first of all */
	ori	r11, r0, PTECNT
	ori	r12, r0, SECOND_MAP_VIRT
	ori	r19, r0, PTE_SIZE 
	ori	r20, r0, 0x00
	
outer_zero_loop:
	addik	r11, r11, -1
	beqid	r11, finished_zero_loop
	nop

inner_zero_loop:
	sw	r0, r12, r20
	addik	r20, r20, PTE_SIZE_HALF 
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

prep_ptes:
	ori	r11, r0, PTECNT
	ori	r12, r0, SECOND_MAP_VIRT 
	ori	r19, r0, PTE_SIZE
	ori	r20, r0, 0x00

/* We work on the basis we have (PTECNT - MAXPINNED) 4k frames */
/* In physical addresses from 0x500000 onwards */
/* MAXPINNED entries first */
	ori	r22, r0, MAXPINNED
copy_pinned_tlbs:
	mts	rtlbx, r20
	mfs	r21, rtlblo
	sw	r21, r12, r0
	mfs	r21, rtlbhi
	swi	r21, r12, PTE_SIZE_HALF
	add	r12, r12, r19
	addik	r22, r22, -1
	bneid	r22, copy_pinned_tlbs
	addik	r20, r20, 0x01

	addik	r11, r11, -MAXPINNED
	ori	r21, r0, FRAME_BASE|WR|EX

pte_loop:
	addik	r11, r11, -1
	beqid	r11, finished_pte_loop
	sw	r21, r12, r0
	addik	r21, r21, PAGE_SZ 
	braid	pte_loop
	add	r12, r12, r19

finished_pte_loop:
	nop

go_user_mode:
	bralid	r15, generated_traffic
	nop
	bri 0

_interrupt_handler:
	ori	r20, r0, 0x01
	bri	0


_hw_exception_handler:
	mfs	r3, resr
	andi	r4, r3, 0x1F
	or	r5, r0, r0
	rsub	r6, r5, r4
	beqi	r6, handle_stream_exception
	switchex
	beqi	r6, handle_unaligned_data_exception
	switchex
	beqi	r6, handle_illegal_opcode
	switchex
	beqi	r6, handle_ibus_error
	switchex
	beqi	r6, handle_dbus_error
	switchex
	beqi	r6, handle_divide_error
	switchex
	beqi	r6, handle_fp_error
	switchex
	beqi	r6, handle_priv_or_stack_error
	addi	r5, r5, 0x09
	rsub	r6, r5, r4	
	beqid	r6, handle_datastore_error
	switchex
	beqid	r6, handle_inststore_error
	switchex
	beqid	r6, handle_datatlb_miss
	switchex
	beqid	r6, handle_insttlb_miss
	nop
	/* should never get here */
	bri 0

handle_stream_exception:
handle_unaligned_data_exception:
handle_illegal_opcode:
handle_ibus_error:
handle_dbus_error:
handle_divide_error:
handle_fp_error:
handle_priv_or_stack_error:

	bri 0

handle_datastore_error:
handle_inststore_error:
	bri 0

handle_datatlb_miss:
	nop
.global exit
exit:
	ori	r19, r0, clock_sweep_pte
	brald	r15, r19
	/* ignoring pinned PTEs */
	ori	r20, r0, MAXPINNED
	/* real mode into page table TAG */
	muli	r21, r20, PTE_SIZE
	addik	r21, r21, SECOND_MAP_PHYS + PTE_SIZE_HALF

	or	r26, r0, r0	/* will store first invalid PTE index */
	mfs	r24, rear
	andi	r24, r24, PAGE4KMASK	/* always 4k pages */

load_PTE:
	lw	r22, r21, r0		/* load page tag */
	andi	r23, r22, PAGE4KMASK
	rsub	r27, r23, r24
	beqid	r27, validate_PTE
	andi	r25, r22, VALID
	addk	r25, r25, r26
	bnei	r25, next_PTE
	or	r26, r0, r20

next_PTE:
	addi	r20, r20, 0x01
	rsubi	r27, r20, PTECNT + 1
	beqi	r27, no_PTE_match
	braid	load_PTE
	addi	r21, r21, PTE_SIZE

	/* similar code to load_PTE except now we are looking for 	*/
	/* an invalid entry we can fill in				*/

no_PTE_match:
	or	r20, r26, r26
	muli	r21, r20, PTE_SIZE
	addik	r21, r21, SECOND_MAP_PHYS + PTE_SIZE_HALF

found_invalid_PTE:
	/* insert the mapping in the PTE */
	/* r21 has the address we want to write to */
	/* make the mapping valid and correct size*/
	or	r23, r24, r0
	ori	r19, r23, VALID|PAGE4K
	sw	r19, r21, r0
	
	brai	load_TLB

validate_PTE:
	bnei	r25, load_TLB	/* r25 tested for VALID in delay slot */
	ori	r22, r22, VALID|PAGE4K
	sw	r22, r21, r0
	brai	load_TLB

handle_insttlb_miss:
	bri 0 

_handle_breakpoint:
	ori	r20, r0, 0x10
	nop
	bri 0 /*endless loop if it ever works */

_exception_handler:
	/* We are now back in real mode */
	ori	r20, r0, 0x03
	bri	0

/* Get here with r23 holding page address and r20 index to PTE */
/* While r21 points to high mapping */
/* We know there is no valid TLB entry that matches */
/* We are not writing OS code so no need to get fancy */
load_TLB:
	/* Look through the TLB entries for an invalid entry */
	addik	r3, r0, MAXPINNED
scantlb:
	mts	rtlbx, r3
	mfs	r24, rtlbhi
	andi	r25, r24, VALID
	beqi	r25, found_invalid_tlb
	addik	r3, r3, 1
	rsubi	r25, r3, TLBCNT
	beqi	r25, no_invalid_tlb
	brai	scantlb

found_invalid_tlb:
	/* set up tlblo first */
	muli	r24, r20, PTE_SIZE
	addi	r24, r24, SECOND_MAP_PHYS
	lw	r25, r0, r24
	andi	r25, r25, PAGE4KMASK
	ori	r25, r25, EX|WR
	mts	rtlblo, r25
	andi	r23, r23, PAGE4KMASK
	ori	r23, r23, VALID|PAGE4K
	mts	rtlbhi, r23
	rted	r17, 0x0
	nop

no_invalid_tlb:
	/* Keep on umapping pages till we hit one in the TLB */
	ori	r19, r0, clock_sweep_pte
	brald	r15, r19
	nop
	brai	load_TLB

/* implement CLOCK for PTEs */
clock_sweep_pte:
	lwi	r25, r0, PTEMAXED 
	ori	r26, r0, CLOCK_SWEEP
	muli	r29, r25, PTE_SIZE
	addik	r29, r29, SECOND_MAP_PHYS
	ori	r19, r0, clear_from_tlb
	addik	r1, r1, -4
	sw	r15, r1, r0

invalidate_pte:
	lwi	r27, r29, PTE_SIZE_HALF
	andi	r28, r27, VALID
	beqi	r28, invalidate_next
	brald	r15, r19 
	andi	r27, r27, ~VALID

invalidate_next:
	swi	r27, r29, PTE_SIZE_HALF
	addik	r25, r25, 0x01
	addik	r29, r29, PTE_SIZE
	rsubi	r28, r25, PTECNT
	bnei	r28, count_down_ptes
	ori	r25, r0, MAXPINNED
	muli	r29, r25, PTE_SIZE
	addik	r29, r29, SECOND_MAP_PHYS

count_down_ptes:
	addik	r26, r26, -1
	bnei	r26, invalidate_pte
	lw	r15, r1, r0
	swi	r25, r0, PTEMAXED
	rtsd	r15, 0x08
	addik	r1, r1, 0x04

/* if the page is mapped in the TLB we have to dump it */

clear_from_tlb:
	addik	r1, r1, -4
	sw	r25, r1, r0
	ori	r20, r0, MAXPINNED
	ori	r21, r0, TLBCNT
clearing_tlb:
	mts	rtlbx, r20
	mfs	r22, rtlbhi
	andi	r23, r27, PAGE4KMASK
	andi	r25, r22, PAGE4KMASK
	rsub	r24, r25, r23
	bnei	r24, move_to_next_tlb
	andi	r22, r22, ~VALID
	lw	r25, r1, r0
	addik	r1, r1, 0x04
	rtsd	r15, 0x08
	mts	rtlbhi, r22

move_to_next_tlb:
	addik	r20, r20, 0x01
	rsub	r22, r20, r21
	bnei	r22, clearing_tlb
	lw	r25, r1, r0	
	rtsd	r15, 0x08
	addik	r1, r1, 0x04	
