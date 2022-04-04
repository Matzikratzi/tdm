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
	 ADD R0.b0, R0.b0, 0
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

DELAYx4	.macro Rx
	SUB	R0, Rx, 1
	NOP
	QBEQ	$E?, R0, 0
$M?:	SUB	R0, R0, 1
	NOP
	NOP
	QBNE	$M?, R0, 0
$E?:	NOP
	.endm

BITFILL	.macro Rx, lefts
	AND R30.w0, R30.w0, R12.w2	; !WS and !SCK
	DELAYx4 R14
	NOP ;ADD R30.b0, R30.b0, 0x10 ; ADD if you want to emit test pattern
	MOV  R20.b0, R31.b0	; Sample all four mics simultaneously
	NOP ;ADD R18.b2, R18.b2, 1 ;NOP
	
	OR R30.w0, R30.w0, R12.w0	 ; SCK
	DELAYx4 R14
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

	;; R11 is SCK and WS
	;; R12 is SCK
	;; R13 is copy of output register for positive flanks
	;; R21 to R28 used for eight samples. But only the first 24 bits (of 32)
	;; R21 first used for 262144 initiating SCKs
	;; R18.b0 counts 0, 1 (reset) to keep track of 4 or 8 recorded samples
	;; R18.b1 decreases from n where n is "keep every nth sample"
	;; R18.b2 Not used
	;; R19 sample timing. Increments every new WS
	
	;; R20.b0 used for simultaneous sampling of 4 TDM bits
	;; R20.b1 used for WS and SCK for first bit per sample
	;; R20.b2 used for mic index. WS for index 0
	;; R20.b3 used for counting down blanks interation var
	
	ZERO &R18, 48		;clear R18 to R29
	LDI R20.b1, 0x0f	;SCK and WS first round
	LDI R20.b2, 0		;WS only for mic 0
	LDI R21, 1		;one cannot type 2^18, so LSL 1 18 times
	LSL R21, R21, 20	;var for initial standby of at least 1 ms
	LDI R30, 0x00	        ; Set both SCK as well as both WS to 0
	LDI R18.b1, 1

	LDI R10.w0, 0x0c80	; WS and firstBitInd
	LDI R10.w2, 0x0080	; firstBitInd
	LDI R12.w0, 0x0300	; SCK1 and SCK2
	OR  R11.w0, R10.w0, R12.w0 	; WS1, WS2, SCK1 and SCK2, firstBitInd
	NOT R12.w2, R11.w0	; NOT (SCK1, SCK2, WS1, WS2, firstBitInd). For turning off all
	MOV R13.w0, R11.w0 	; WS1, WS2, SCK1 and SCK2 for first mic

	LDI R30.w0, 0x0100	; flip this once to have something to trig on
	LDI R30, 0x00	        ; Set both SCK as well as both WS to 0

tdmArrayInitialStandby:
	SUB R21, R21, 1		;Decrease from initial 2^20
	QBNE tdmArrayInitialStandby, R21, 0

	;; Done! Now officially in standby
	
	LDI R21, 1		;one cannot type 2^18, so LSL 1 18 times
	LSL R21, R21, 18	;var for start sequence with 262144 SCK at choosen MHz

tdmArraySamplingInitLoop:
	NOP
	MOV R30.w0, R12.w0	;Set both SCK to 1
	DELAYx4 R14
	NOP
	NOP
	NOP

	LDI R30, 0x00	;Set both SCK to 0
	DELAYx4 R14
	SUB R21, R21, 1		;Decrease from initial 262144
	QBNE tdmArraySamplingInitLoop, R21, 0

	;; Done! Now valid samples after first WS

	MOV R30.w0, R10.w0   ; WS and firstBitInd before SCK

	;; First SCK of sample (bit 23, i.e. MSB)
	MOV R30.w0,  R11.w0	; SCK and WS and firstBitInd (WS for first mics on loops)
	DELAYx4 R14
	NOP
	NOP
	NOP

tdmArraySamplingloop:
	
	;; sampling bits 23-16
	BITFILL R25, 28
 	BITFILL R25, 24
	BITFILL R25, 20
	BITFILL R25, 16

	BITFILL R25, 12
	BITFILL R25, 8
	BITFILL R25, 4
	BITFILL R25, 0

	
	;; sampling bits 15-8
	BITFILL R26, 28
	BITFILL R26, 24
	BITFILL R26, 20
	BITFILL R26, 16

	BITFILL R26, 12
	BITFILL R26, 8
	BITFILL R26, 4
	BITFILL R26, 0

	;; sampling bits 7 and providing chainedBranching
	AND R30.w0, R30.w0, R12.w2	; !WS and !SCK LDI R30, 0x00	; !WS and !SCK
	DELAYx4 R14
	NOP ;ADD R30.b0, R30.b0, 0x10 ; ADD if you want to emit test pattern
	MOV  R20.b0, R31.b0	; Sample all four mics simultaneously
	QBA secondHalfBit7

chainedBranching:		;only here to make long qba possible from end of file
	QBA tdmArraySamplingloop
	
secondHalfBit7:
	OR R30.w0, R30.w0, R12.w0	 ; SCK
	DELAYx4 R14
	AND  R20.b0, R20.b0, 0xf
	LSL  R28, R20.b0, 28
	OR   R27, R27, R28

	;; sampling bits 6-0

	BITFILL R27, 24
	BITFILL R27, 20
	BITFILL R27, 16

	BITFILL R27, 12
	BITFILL R27, 8
	BITFILL R27, 4
	BITFILL R27, 0		;with SCK z0

	
	LDI R30, 0x00	; !SCK (z0)
	DELAYx4 R14
	MOV   R28.b2, R20.b2	; mic index
	MOV   R28.b0, R14.b0
	QBEQ moveFirstFour, R18.b0, 0 ; Move samples to lower regs

sendEightSamples:	
	;; Giving data to other PRU
	MOV R30.w0, R12.w0	; SCK (z1)
	DELAYx4 R14
	NOP ;QBNE  dontSend, R18.b1, 1 Todo - this is temporary
	ADD   R29, R29, 32	;byte counter
	XOUT  10, &R21, 36     ; Move data across the broadside

	LDI R30, 0x00	; !SCK (z1)
	DELAYx4 R14
	LDI   R31, PRU1_PRU0_INTERRUPT + 16    ; Jab PRU0
	LDI   R18.b0, 0			       ; next are first four bits
	QBA   tdmArraySamplingBlanks
	
dontSend:
	NOP
	NOP

	LDI R30, 0x00	; !SCK (z1)
	DELAYx4 R14
	NOP
	LDI   R18.b0, 0		; next are first four bits
	QBA   tdmArraySamplingBlanks
	
moveFirstFour:
	;; While giving SCK to empty bit 1
	;; We will send 8 samples (registers) at a time
	MOV R30.w0, R12.w0	; SCK (z1)
	DELAYx4 R14
	MOV   R21, R19
	MOV   R22, R25
	MOV   R23, R26

	LDI R30, 0x00	; !SCK (z1)
	DELAYx4 R14
	MOV   R24, R27
	LDI   R18.b0, 1		;next are last four bits
	NOP
	

tdmArraySamplingBlanks:
	MOV R30.w0, R12.w0	;SCK (z2)
	DELAYx4 R14
	LDI   R20.b3, 4		;Set iteration variable for blanks 
	ADD   R20.b2, R20.b2, 1	;WS only every 16th TODO: hide this in sendEight
	AND   R20.b2, R20.b2, 0xf

	LDI R30, 0x00	;!SCK (z2)
	DELAYx4 R14
	QBEQ  upcommingWS, R20.b2, 0

	MOV   R13.w0, R12.w0	;WS is not set for next sample
	OR    R13.w0, R13.w0, 0x0080 ; But firstBitInd is still set.


	MOV R30.w0, R12.w0	; SCK (z3)
	DELAYx4 R14
	AND R25, R25, 0		; Clear reg for next mics
	AND R26, R26, 0		; Clear reg for next mics
	AND R27, R27, 0		; Clear reg for next mics

	LDI R30, 0x00	; !SCK (z3)
	DELAYx4 R14
	MOV   R13.w2, R10.w2	; firstBitInd
	NOP
	QBA   tdmArraySamplingBlanks2	;keep timing

upcommingWS:
	MOV   R13.w0, R11.w0	;WS and firstBitInd are set for next sample
	MOV   R13.w2, R10.w0	; WS and firstBitInd

	MOV R30.w0, R12.w0	 ; SCK (z3) 
	DELAYx4 R14
	ADD R19, R19, 1
	MOV R21, R19
	NOP

	LDI R30, 0x00	 ; !SCK (z3)
	DELAYx4 R14
	QBEQ resetSampler, R18.b1, 1
	SUB R18.b1, R18.b1, 1
	QBA tdmArraySamplingBlanks2

resetSampler:
	MOV R18.b1, R14
	NOP

tdmArraySamplingBlanks2:
	;; SCK for empty bits 3-7
	MOV R30.w0, R12.w0	;SCK (z4)
	DELAYx4 R14
	NOP
	NOP
	NOP

	LDI R30, 0x00	;!SCK (Z4)
	DELAYx4 R14
	SUB   R20.b3, R20.b3, 1
	QBNE  tdmArraySamplingBlanks3, R20.b3, 0 ;keep timing, more blanks
	MOV R30.w0, R13.w2

	;; First SCK of sample (bit 23, i.e. MSB)
	MOV R30.w0,  R13.w0	; SCK and WS (WS for first mics on loops)
	DELAYx4 R14
	NOP
	;NOP                    This is a to long jump, so must be chained!
	QBA   chainedBranching ;tdmArraySamplingloop 

tdmArraySamplingBlanks3:
	QBA   tdmArraySamplingBlanks2	;keep timing, once more blanks
	
; End-of-firmware
	HALT
