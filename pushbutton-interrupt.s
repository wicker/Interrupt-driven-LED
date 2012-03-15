@ Program to show hooking of interrupt vector, chaining of interrupt procedures, 
@ and servicing an interrupt produced by a pushbutton that turns on and off an 
@ LED. Active low pushbutton on GPIO13. LED control on GPIO 91 (button). 
@ Extensively used the framework from Dr. Douglas Hall's ECE371 textbook.
@ Jen Hanni, Winter 2011 

.text 
.global _start 
_start: 

@ INITIALIZE EVERYONE AND THEIR GRANDMOTHER 

.EQU GPDR0, 0x40E0000C
.EQU GPSR0, 0x40E00018
.EQU GPCR0, 0x40E00024
.EQU GPDR2, 0x40E00014
.EQU GPSR2, 0x40E00020
.EQU GPCR2, 0x40E0002C
.EQU GRER2, 0x40E000 
.EQU GEDR2, 0x40E000 
.EQU CLR27, 0xF7FFFFFF
.EQU SET27, 0x08000000

@ INITIALIZE GPIO 13 AS HIGH OUTPUT 

LDR R0,GPDR0	@ Load pointer of GPDR0 into R0. 
LDR R1,GPSR0 	@ Load pointer of GPSR0 into R1; writing the R3 word here turns LED on 
LDR R2,GPCR0	@ Load pointer of GPCR0 into R2; writing the R3 word here turns LED off 
LDR R3,0x2000	@ This calculated word contains a 1 in bit 13 
STR R3,[R2]	@ Write to GPCR0 to turn the LED off to start 
LDR R4,[R0]	@ Read the value from GPDR0 
ORR R4,R4,R3	@ Modify - set the bits of R4 to write bit 13 as an output 
STR R4,[R0]	@ Write the word back to GPDR0 

@ INITIALIZE GPIO91 FOR INPUT AND RISING EDGE DETECT 

LDR R0,GPDR2	@ Load pointer of GPDR2 into R0. 
LDR R4,[R0]	@ Read GPDR2 register
ORR R4,R4,CLR27	@ Modify - clear bit 27 in GPDR2 to make GPIO 91 an input for sure 
STR R4,[R0]	@ Write word back to GPDR2 
LDR R4,GRER2	@ Load address of GRER2 register 
LDR R0,[R4]	@ Read GRER2 register
MOV R2,SET27	@ Load mask to set bit 27 -- calculated word 0x08000000
ORR R0,R0,R2	@ Set bit 27 
STR R0,[R4]	@ Write word back to GRER2 register 
@ 
@ INITIALIZE INTERRUPT CONTROLLER 
@ NOTE: DEFAULT VALUE OF IRQ FOR ICLR BIT 10 IS DESIRED VALUE, SO SEND NO WORD 
@ NOTE: DEFAULT VALUE OF DIM BIT IN ICCR IS DESIRED VALUE, SO NO WORD SENT 
@ 
	LDR R0,=0x40D00004	@ Load address of mask (ICMR) register 
	LDR R1,[R0]		@ Read current value of register 
	MOV R2,#0x400		@ Load value to unmask bit 10 for GPIO82:2 
	ORR R1,R1,R2		@ Set bit 10 to unmask IM10 
	STR R1,[R0]		@ Write word back to ICMR register 
@ 
@ HOOK IRQ PROCEDURE ADDRESS AND INSTALL OUR INT_HANDLER ADDRESS 
@ 
	MOV R1,#0x18	 	 @ Load IRQ interrupt vector address 0x18 
	LDR R2,[R1]		 @ Read instr from interrupt vector table at 0x18 
	LDR R3,=0xFFF	 	 @ Construct mask 
	AND R2,R2,R3		 @ Mask all but offset part of instruction 
	ADD R2,R2,#0x20		 @ Build absolute address of IRQ procedure in literal 
				 @ pool 
	LDR R3,[R2]		 @ Read BTLDR IRQ address from literal pool 
	STR R3,BTLDR_IRQ_ADDRESS @ Save BTLDR IRQ address for use in IRQ_DIRECTOR 
	LDR R0,=INT_DIRECTOR	 @ Load absolute address of our interrupt director 
	STR R0,[R2]		 @ Store this address literal pool 
@ 
@ MAKE SURE IRQ INTERRUPT ON PROCESSOR ENABLED BY CLEARING BIT 7 IN CPSR 
@ 
	MRS R3,CPSR		@ Copy CPSR to R3 
	BIC R3,R3,#0x80		@ Clear bit 7 (IRQ Enable bit) 
	MSR CPSR_c, R3		@ Write new counter value back in memory 
				@ to lowest 8 bits of CPSR 

@ 
@ WAIT HERE NOW FOR THE INTERRUPT SIGNAL BY DOING PROGRAM THINGS 
@ THIS IS THE MAINLINE 
@ 
LOOP:	NOP			@ Wait for interrupt here (simulate mainline 
	B LOOP			@ program execution) 
@ 
@ HOUSTON WE HAVE AN INTERRUPT -- IS IT BUTTON OR SOMETHING ELSE? 
@ 
INT_DIRECTOR:			@ Chains button interrupt procedure 
	STMFD SP!,{R0-R3,LR}	@ Save registers to be used in procedure on stack 
				@ Assume only GPIO 119:2 possible for this program. 
				@ System will take care of others. 
	LDR R0,=0x40D00000	@ Point at IRQ pending register (ICIP) 
	LDR R1,[R0]		@ Read ICIP register 
	TST R1,#0x400		@ Check if GPIO 119:2 IRQ interrupt on IS<10> asserted 
	BEQ PASSON		@ No, must be other IRQ, pass on to system program 
	LDR R0,=0x40E00050	@ Yes, load GEDR2 register address to check if GPIO91 
	LDR R1,[R0]		@ Read GPIO Edge Detect Register (GEDR2) value 
	TST R1,#0x800		@ Check if bit 27 = 1 (GPIO91 edge detected) 
	BNE BUTTON_SVC		@ Yes, must be button press. 
				@ Go service - return to wait loop from SVC 
@ 
@ IT'S NOT THE BUTTON, IT'S NOT THE BUTTON 
@ 
PASSON: LDMFD SP!{R0-R3,LR}	 @ No, must be other GP 80:2 IRQ, restore registers 
	LDR PC,BTLDR_IRQ_ADDRESS @ Go to bootloader IRQ service procedure 
				 @ Bootloader will use restored LR to return to 
				 @ mainline loop when done. 
@ 
@ IT'S THE BUTTON, IT'S THE BUTTON 
@ SERVICE THE BUTTON PRESS 
@ 
BUTTON_SVC: 
	MOV R1,#0x800		@ Value to clear bit 13 in GEDR0 register. 
			 	@ This will also reset bit 10 in ICPR and ICIP 
				@ if no other GPIO 80-2 interrupts. 
	STR R1,[R0]		@ Write back to GPIO GEDR2 register 
	LDR R0,=ONOROFF		@ Point to ONOROFF variable in memory 
				@ Test for 0xA 
	LDR R1,[R0]		@ If yes, then ON, set OFF by writing 0xB 
				@ 	Load pointer to GPCR0 in R6 
				@ 	Then write LED word to GPCR0 to turn off 
				@ Else, it's OFF, set ON by writing 0xA 
				@	Load pointer to GPSR0 in R6 
				@ 	Then write LED word to GPSR0 to turn on 
	LDMFD SP!,{R0-R3,LR}	@ Restore registers, including return address 
	SUBS PC,LR,#4		@ Return from interrupt (to wait loop) 

BTLDR_IRQ_ADDRESS: 

	 .word 0x0		@ Space to store bootloader IRQ address 

.data 
DELAYCOUNT: 	.word 0x0A305660	@ This hex contains 170,940,170 clock cycles 
ONOROFF: 	.word 0x0		@ 0xA means on, 0xB is off 
.end
