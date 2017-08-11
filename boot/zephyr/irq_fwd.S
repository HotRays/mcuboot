/*
 * Copyright (c) 2017 Shenzhen Trylong Intelligence Technology Co., Ltd.
 *
 * Author: Ding Tao <miyatsu@qq.com>	2017-07-28
 */

/**
 * @file fwd_irq.S
 * @brief IRQ forward handler for mcuboot and firmware in slot0
 *
 * When mcuboot runs out, the interrupt handler still in mcuboot control
 * after jump to slot0 while no rewite to the vector table. Once an
 * interrupt occurs when firmware in slot0 is running, the vector table
 * at address 0x00000000 will put PC pointer (aka r15 in arm arch) jump
 * to mcuboot code where the code is no longer valid any more and let
 * the code runs out of flying.
 *
 * A efficient way to solve this kind of bug is to tell the firmware in
 * slot0 to make a offset of vector table where the real vector table is.
 *
 * Unfortunately, ARM Cortex M0 did not define a interrupt vector table
 * offset. And most of vendor did not extended this feature except NXP
 * and ST etc. For portable program, we always assume that no MCU could
 * have the capabilities of setting vector table offset even if it have.
 *
 */

#include <board.h>
#include <toolchain.h>
#include <linker/sections.h>
#include <arch/cpu.h>

_ASM_FILE_PROLOGUE

SECTION_SUBSEC_FUNC(irq_fwd, table, irq_fwd_table)
	/* Address of 0x00000000 */
	.word 0x20001000;	/* MSP */
	.word 0xC1;			/* reset */
	.word 0x101;		/* nmi */
	.word 0x101;		/* hard_fault */
	.word 0x101;
	.word 0x101;
	.word 0x101;
	.word 0x101;
	.word 0x101;
	.word 0x101;
	.word 0x101;
	.word 0x101;		/* svc */
	.word 0x101;
	.word 0x101;
	.word 0x101;		/* pendsv */
	.word 0x101;
	/* From this end, all system exception irq vector is placed. */

	.word 0x101;
	.word 0x101;
	.word 0x101;
	.word 0x101;
	.word 0x101;
	.word 0x101;
	.word 0x101;
	.word 0x101;
	.word 0x101;
	.word 0x101;
	.word 0x101;
	.word 0x101;
	.word 0x101;
	.word 0x101;
	.word 0x101;
	.word 0x101;
	.word 0x101;
	.word 0x101;
	.word 0x101;
	.word 0x101;
	.word 0x101;
	.word 0x101;
	.word 0x101;
	.word 0x101;
	.word 0x101;
	.word 0x101;
	.word 0x101;
	.word 0x101;
	.word 0x101;
	.word 0x101;
	.word 0x101;
	.word 0x101;
	/* This section will be put into flash at 0x00000000 at link stage*/

SECTION_SUBSEC_FUNC(irq_fwd, handler, irq_fwd_handler)
	mrs		r0, ipsr;		/* Load interrupt program status register into r0 */
	lsls	r0, r0, $0x02;	/* IRQ vector relative offset */

	ldr		r1, =$0x20003F40;	/* Vector table offset address */
	adds	r1, r1, r0;			/* Real vector offset address */
	ldr		r1, [r1];			/* Get real vector */

	/* The size of irq vector is 4 bytes, the offset within vector table
	 * is the irq number times 4 (aka r0 << 2). As know as the r1 stored
	 * the offset of real vector table, thus the (r1 = r1 + r0 << 2) will
	 * be the real irq handle vector.
	 */

	bx		r1;		/* Do jump */

	/* This section will be put into flash where address between
	 * ( CONFIG_NUMBER_OF_IRQ * 4 ) and CONFIG_TEXT_SECTION_OFFSET at link
	 * stage control by link script */

SECTION_SUBSEC_FUNC(irq_fwd, reset, irq_fwd_reset)
	movs	r3, $0x0;			/* Counter, 0-47 */
	ldr		r1, =$0x20003F40;	/* Destination */
	ldr		r2, =$0x200;		/* Source */

copy_vector:
	cmp		r3, $0x2F;		/* Dec 47 */
	bgt.n	copy_done;
	ldr		r0, [r2];		/* Get vector from flash */
	str		r0, [r1];		/* Set vector to ram */
	adds	r1, $0x04;		/* Address increase */
	adds	r2, $0x04;
	adds	r3, $0x01;		/* Number of vectors increase */
	b.n		copy_vector;

copy_done:
	ldr		r0, =$0x204;
	ldr		r0, [r0];
	bx		r0;

