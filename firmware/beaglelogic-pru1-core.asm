;* PRU1 Firmware for BeagleLogic
;*
;* Copyright (C) 2014 Kumar Abhishek <abhishek@theembeddedkitchen.net>
;*
;* This file is a part of the BeagleLogic project
;*
;* This program is free software; you can redistribute it and/or modify
;* it under the terms of the GNU General Public License version 2 as
;* published by the Free Software Foundation.

	.include "beaglelogic-pru-defs.inc"

NOP	.macro
	 ADD R0.b0, R0.b0, R0.b0
	.endm

; Generic delay loop macro
; Also includes a post-finish op
DELAY	.macro Rx, op
	SUB	R0, Rx, 2
	QBEQ	$E?, R0, 0
$M?:	SUB	R0, R0, 1
	QBNE	$M?, R0, 0
$E?:	op
	.endm

BITFILL	.macro Rx, lefts
	LDI R30.b1, 0x00	; !WS and !SCK
	MOV  R20.b0, R31.b0	; Sample all four mics simultaneously
	NOP
	NOP
	
	LDI R30.b1, 0x03	 ; SCK
	AND  R20.b0, R20.b0, 0xf
	LSL  R28, R20.b0, lefts
	OR   Rx, Rx, R28
	.endm
	
	.sect ".text:main"
	.global asm_main
asm_main:
	; Set C28 in this PRU's bank =0x24000
	LDI32  R0, CTPPR_0+0x2000               ; Add 0x2000
	LDI    R1, 0x00000240                   ; C28 = 00_0240_00h = PRU1 CFG Registers
	SBBO   &R1, R0, 0, 4

	; Configure R2 = 0x0000 - ptr to PRU1 RAM
	LDI    R2, 0

	; Enable the cycle counter
	LBCO   &R0, C28, 0, 4
	SET    R0, R0, 3
	SBCO   &R0, C28, 0, 4

	; Load Cycle count reading to registers [LBCO=4 cycles, SBCO=2 cycles]
	LBCO   &R0, C28, 0x0C, 4
	SBCO   &R0, C24, 0, 4

	; Load magic bytes into R2
	LDI32  R0, 0xBEA61E10

	; Wait for PRU0 to load configuration into R14[samplerate] and R15[unit]
	; This will occur from an downcall issued to us by PRU0
	HALT

	; Jump to the appropriate sample loop
	; TODO

	LDI    R31, PRU0_ARM_INTERRUPT_B + 16   ; Signal SYSEV_PRU0_TO_ARM_B to kernel driver
	HALT

	; Sample starts here
	; Maintain global bytes transferred counter (8 byte bursts)
	LDI    R29, 0

tdmArraySamplingInit:
	;; Taking samples from ICS-52000 in for daisy chains.
	;; Must send SCK evenly at 25 MHz.
	;; Each sample is 24 bits.
	;; Each daisy chain consists of 16 mics.
	;; WS is sent first iteration and then every 16th mic, i.e. the first mic.
	
	;; R21 to R28 used for eight samples. But only the first 24 bits (of 32)
	;; R21 first used for 262144 initiating SCKs
	;; R18 counts 0, 1 (reset) to keep track of 4 or 8 recorded samples
	;; R19 sample timing. Increments every new WS
	
	;; R20.b0 used for simultaneous sampling of 4 TDM bits
	;; R20.b1 used for WS and SCK for first bit per sample
	;; R20.b2 used for WS counting down interation var
	;; R20.b3 used for counting down blanks interation var
	
	ZERO &R18, 48		;clear R18 to R29
	LDI R20.b1, 0x0f	;SCK and WS first round
	LDI R20.b2, 16		;WS only once every 16th iteration
	LDI R21, 1		;one cannot type 2^18, so LSL 1 18 times
	LSL R21, R21, 9		;var for start sequence with 262144 SCK at 25 MHz
	LDI R30.b1, 0x00	; Set both SCK as well as both WS to 0

tdmArraySamplingInitLoop:
	LDI R30.b1, 0x03	;Set both SCK to 1
	NOP
	NOP
	NOP

	LDI R30.b1, 0x00	;Set both SCK to 0
	SUB R21, R21, 1		;Decrease from initial 262144
	NOP
	QBNE tdmArraySamplingInitLoop, R21, 0

	;; Done! Now valid samples after first WS
	
tdmArraySamplingCycleStart:
	;; First SCK of sample (bit 23, i.e. MSB)
	MOV R30.b1,  R20.b1	; SCK and WS (WS for first mics on loops)
	NOP
	NOP
	NOP
	
	;; SCK for bits 22-16
	BITFILL R25, 28
 	BITFILL R25, 24
	BITFILL R25, 20
	BITFILL R25, 16
	BITFILL R25, 12
	BITFILL R25, 8
	BITFILL R25, 4
	BITFILL R25, 0

	;; SCK for bits 15-8
	BITFILL R26, 28
	BITFILL R26, 24
	BITFILL R26, 20
	BITFILL R26, 16
	BITFILL R26, 12
	BITFILL R26, 8
	BITFILL R26, 4
	BITFILL R26, 0

	;; SCK for bits 7-0
	BITFILL R27, 28
	BITFILL R27, 24
	BITFILL R27, 20
	BITFILL R27, 16
	BITFILL R27, 12
	BITFILL R27, 8
	BITFILL R27, 4
	BITFILL R27, 0

	LDI R30.b1, 0x00	; !SCK
	LDI R28.w0, 0x1234
	LDI R28.w2, 0x5678
	QBEQ moveFirstFour, R18, 0 ; Move samples to lower regs

sendEightSamples:	
	;; While giving SCK to empty bit 1
	;; Giving data to other PRU
	LDI R30.b1, 0x03	; SCK
	ADD R29, R29, 32	;byte counter
	XOUT  10, &R21, 36     ; Move data across the broadside
	LDI   R31, PRU1_PRU0_INTERRUPT + 16    ; Jab PRU0

	LDI R30.b1, 0x00	; !SCK
	LDI   R18, 0
	NOP
	QBA tdmArraySamplingBlanks
	
moveFirstFour:
	;; While giving SCK to empty bit 1
	;; We will send 8 samples (registers) at a time
	LDI R30.b1, 0x03	; SCK
	MOV R21, R19
	MOV R22, R25
	MOV R23, R26

	LDI R30.b1, 0x00	; !SCK
	MOV R24, R27
	LDI R18, 1
	NOP
	

tdmArraySamplingBlanks:
	;; giving SCK to empty bit 1 (and 2)
	LDI R30.b1, 0x03	;Set both SCK to 1
	LDI   R20.b3, 4		;Set iteration variable for blanks 
	SUB   R20.b2, R20.b2, 1	;WS only every 16th
	NOP

	LDI R30.b1, 0x00	;Set both SCK to 0
	QBEQ  upcommingWS, R20.b2, 0

	LDI   R20.b1, 0x03	;WS is set not set for next sample
	NOP

	;; SCK for empty bit 2
	LDI R30.b1, 0x03		;Set both SCK to 1
	NOP
	NOP
	NOP

	LDI R30.b1, 0x00		;Set both SCK to 0
	NOP
	NOP
	QBA   tdmArraySamplingBlanks2	;keep timing

upcommingWS:
	LDI   R20.b1, 0x0f	;WS is set for next sample
	LDI   R20.b2, 16	;Set iteration variable for WS only every 16th

	;; alternative for empty bit 2
	LDI R30.b1, 0x03		;Set both SCK to 1
	ADD R19, R19, 1
	MOV R21, R19
	NOP

	LDI R30.b1, 0x00		;Set both SCK to 0
	NOP
	NOP
	NOP
	

tdmArraySamplingBlanks2:
	;; SCK for empty bits 3-7
	LDI R30.b1, 0x03	;Set both SCK to 1
	NOP
	NOP
	NOP

	LDI R30.b1, 0x00	;Set both SCK to 0
	SUB   R20.b3, R20.b3, 1
	QBNE  tdmArraySamplingBlanks3, R20.b3, 0 ;keep timing, once more blanks
	QBA   tdmArraySamplingCycleStart

tdmArraySamplingBlanks3:
	QBA   tdmArraySamplingBlanks2	;keep timing, once more blanks
	
; End-of-firmware
	HALT
