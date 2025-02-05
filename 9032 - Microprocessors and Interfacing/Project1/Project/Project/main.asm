.include "m2560def.inc"
.include "map.inc"
;.include	"display.inc"

.equ LCD_CTRL_PORT = PORTA
.equ LCD_CTRL_DDR = DDRA
.equ LCD_RS = 7
.equ LCD_E = 6
.equ LCD_RW = 5
.equ LCD_BE = 4	
.equ NUMBER_COL=65
.equ NUMBER_COL_dec_2=63		; fix adiw out of range issue

.equ LCD_DATA_PORT = PORTF	; use portF as input in LCD
.equ LCD_DATA_DDR = DDRF
.equ LCD_DATA_PIN = PINF

.equ PORTLDIR =0xF0			; use PortD for input/output from keypad: PF7-4, output, PF3-0, input
.equ INITCOLMASK = 0xEF		; scan from the leftmost column, the value to mask output
.equ INITROWMASK = 0x01		; scan from the bottom row
.equ ROWMASK  =0x0F			; low four bits are output from the keypad. This value mask the high 4 bits.

.def row = r16			; current row number
.def col = r17			; current column number
.def rmask = r18		; mask for current row
.def cmask = r19		; mask for current column
.def temp1 = r20		; temporary register 1
.def temp2 = r21		; temporary register 2
.def data  = r22		

.def X_target = r5		; X cursor of target
.def Y_target = r6		; Y cursor of target
.def height = r7		; current position height
.def X_cursor = r8		; current X cursor of drone 
.def Y_cursor = r9		; current Y cursor of drone 
.def Z_cursor = r10		; current Z cursor of drone 
.def reader	= r11		; read from progarm memory 
.def counter = r12		; number of positions drone have searched 
.def direction = r13	; indicate the direction 

.macro STORE
	.if @0 > 63
		sts @0, @1
	.else
		out @0, @1
	.endif
.endmacro

.macro LOAD
	.if @1 > 63
		lds @0, @1
	.else
		in @0, @1
	.endif
.endmacro

 .macro DO_LCD_COMMAND
	ldi r16, @0
	rcall lcd_command
	rcall lcd_wait
.endmacro

.macro DO_LCD_DATA
	mov r16, @0
	rcall lcd_data
	rcall lcd_wait
.endmacro

.macro LDC_SET
	sbi LCD_CTRL_PORT, @0
.endmacro

.macro LDC_CLR
	cbi LCD_CTRL_PORT, @0
.endmacro

.macro	SET_MOTOR_SPEED
	; set motor speed by @0
	clr	temp1
	sts	OCR3BH,Temp1
	ldi	temp1,@0
	sts	OCR3BL,temp1
	ldi	temp1,(1<<cs30)
	sts	TCCR3B,temp1
	ldi	temp1,(1<<WGM30)|(1<<COM3B1)
	sts	TCCR3A,temp1
.endmacro

.macro	FLASH
	; flash LED 1 time
	ser	temp1
	out	PORTC,temp1
	rcall	sleep_300ms
	rcall	sleep_300ms
	clr	temp1
	out	PORTC,temp1
	rcall	sleep_300ms
	rcall	sleep_300ms
.endmacro

.macro	DECIMAL_SHIFT		
	;@0*10+@1	with	decimal	shift
	subi	@1,'0'
	ldi		temp2,10
	mul		@0,temp2
	mov		@0,r0
	add		@0,@1
	subi	@1,-'0'
.endmacro

.macro INIT_TIME1
; To generate 1s timer 1
; Timer1 is 16 bits timer, 2^16 = 65536; 65536 * 1/16M s * Clock_Selection = 1s
; Clock_Selection = 256
; Therefore: TCCR1B = 0b00000100  
          
	ldi TEMP1, 0b00000000            
	sts TCCR1A, TEMP1         ; Normal mode            
	ldi TEMP1, 0b00000100            
	sts TCCR1B, TEMP1         ; Clock selection = 256            
	ldi TEMP1, (1<<TOIE1)            
	sts TIMSK1,TEMP1          ; Overflow enabled
.endmacro

.macro STOP_TIME1          
	ldi TEMP1,0b00000000            
	sts TCCR1A,TEMP1         ; Normal mode            
	ldi TEMP1,0b00000000            
	sts TCCR1B,TEMP1         ; Clock selection = 256            
	ldi TEMP1,(1<<TOIE1)            
	sts TIMSK1,TEMP1         ; Overflow enabled
.endmacro

.cseg
.org 0x0		;start	address	from	0x0
	jmp RESET

.org OVF1addr				;Set	triggle	Timer1
	jmp Timer1OverFlow

RESET:
	ldi r16, low(RAMEND)
	out SPL, r16
	ldi r16, high(RAMEND)
	out SPH, r16

	ser r16
	STORE LCD_DATA_DDR, r16
	STORE LCD_CTRL_DDR, r16
	clr r16
	STORE LCD_DATA_PORT, r16
	STORE LCD_CTRL_PORT, r16

	DO_LCD_COMMAND 0b00111000 ; 2x5x7
	rcall sleep_5ms
	DO_LCD_COMMAND 0b00111000 ; 2x5x7
	rcall sleep_1ms
	DO_LCD_COMMAND 0b00111000 ; 2x5x7
	DO_LCD_COMMAND 0b00111000 ; 2x5x7
	DO_LCD_COMMAND 0b00001000 ; display off
	DO_LCD_COMMAND 0b00000001 ; clear display
	DO_LCD_COMMAND 0b00000110 ; increment, no display shift
	DO_LCD_COMMAND 0b00001110 ; Cursor on, bar, no blink

	ldi temp1, PORTLDIR	 	  ; columns are outputs, rows are inputs
	sts	DDRL, temp1
	ser temp1				  ; PORTC is outputs
	out DDRC, temp1				
	out PORTC, temp1

	ser temp1				  ; PORTE is intputs
	out DDRE, temp1				
	out PORTE, temp1

	clr	X_target			  ; init registers
	clr	Y_target
	clr	height
	clr	direction
	clr	counter
	clr	X_cursor
	Clr	Y_cursor

	ldi	temp1,1
	mov	Y_cursor,temp1			; set Y cursor to 1


	SET_MOTOR_SPEED	0x00		; stop motor

	rcall	display_welcome		; show welcome words

	FLASH		; flash	LED	2 times
	FLASH

	DO_LCD_COMMAND 0b00000001	; clear LED

	rcall	display_input_x
	
	ldi zl, low(matrix<<1)		; set Z register to program memory matrix
	ldi zh, high(matrix<<1)
	subi	ZL,1				; Z = Z - 1
	sbci	ZH,0

main:
	ldi cmask, INITCOLMASK		; initial column mask
	clr	col						; initial column
colloop:
	cpi col, 4
	breq main
	sts	PORTL, cmask			; set column to mask value (one column off)
	ldi temp1, 0xFF
delay:
	dec temp1
	brne delay

	lds	temp1, PINL				; read PORTD
	andi temp1, ROWMASK
	cpi temp1, 0xF				; check if any rows are on
	breq nextcol
								; if yes, find which row is on
	ldi rmask, INITROWMASK		; initialise row check
	clr	row						; initial row
rowloop:
	cpi row, 4
	breq nextcol
	mov temp2, temp1
	and temp2, rmask			; check masked bit
	breq convert 				; if bit is clear, convert the bitcode
	inc row						; else move to the next row
	lsl rmask					; shift the mask to the next bit
	jmp rowloop

nextcol:
	lsl cmask					; else get new mask by shifting and 
	inc col						; increment column value
	jmp colloop					; and check the next column

convert:
	cpi col, 3					; if column is 3 we have a letter
	breq letters				
	cpi row, 3					; if row is 3 we have a symbol or 0

	breq symbols
	mov temp1, row				; otherwise we have a number in 1-9
	lsl temp1
	add temp1, row				; temp1 = row * 3
	add temp1, col				; add the column address to get the value
	subi temp1, -'1'			; add the value of character '0'
	
	rcall sleep_300ms			; verify input
	DECIMAL_SHIFT Y_target,temp1; Y_target = Y_target*10+temp1
	jmp convert_end				

letters:
	ldi temp1, 'A'
	add temp1, row				; increment the character 'A' by the row value
	jmp convert_end

symbols:
	cpi col, 0					; check if we have a star
	breq star
	cpi col, 1					; or if we have zero
	breq zero					
	ldi temp1, '#'				; if not we have hash
	jmp convert_end
star:
	ldi temp1, '*'				; set to star
	rcall	sleep_300ms
	mov	X_target,Y_target
	clr	Y_target

	DO_LCD_COMMAND 0b00000001

	out PORTC, X_target
	rcall	display_input_y
	jmp main
zero:
	ldi temp1, '0'				; set to zero
	rcall	sleep_300ms			; verify input
	DECIMAL_SHIFT	Y_target,temp1 ; Y_target = Y_target*10

convert_end:
	cpi	temp1,'#'				; check input is '#'
	breq end_input
	DO_LCD_DATA temp1
	subi temp1,'0'
	out PORTC, temp1			; write value to PORTC
	rcall sleep_300ms			; verify input
	rjmp main					

end_input:
	DO_LCD_COMMAND 0b00000001
	rcall  display_start
	out PORTC, Y_target
	check_botton:
		sbis PIND,0					; if	button	is	unpressed	skip	next	line
		rjmp start					; button is pressed, drone start searching
	rjmp check_botton

start:
	rcall sleep_300ms				; verify input
	;DO_LCD_COMMAND 0b00000001
	sbis PIND,0						; check button press again or not
	rjmp abort						; abort searching
	SET_MOTOR_SPEED	0xff			; high speed motor 
	INIT_TIME1						; start timer 1
	rjmp start

abort:
	STOP_TIME1						; stop timer 1
	SET_MOTOR_SPEED	0x00			; stop motor
	rcall	display_abort			; display info to LCD
	
halt:
	rjmp	halt

Timer1OverFlow:						; call every 1 s by timer 1 
	inc	counter						; increase counter 
	cp X_cursor,X_target			; check X cursor
	breq check_Y
	brne move
	check_Y:						; check Y cursor
		cp	Y_cursor,Y_target
		breq found					; both equal go found
		brne move					

	move:
		ldi	 temp1,NUMBER_COL		; check should change line or not
		cp counter,temp1
		brge next_line
		ldi	 temp1,0
		cp direction,temp1			; check direction
		breq forward				; move forward
		brne back					; move back

	forward:
		inc	X_cursor				; increase X cursor
		adiw ZH:ZL,1
		rjmp search_position		; update position

	back:							; decrease X cursor
		dec	X_cursor
		subi ZL,1
		sbci ZH,0		
		rjmp search_position		; update position

next_line:
	clr	temp1						; change direction
	cp direction,temp1				; 0 --> forward
	breq set_direction_1			; 1 --> back
 	brne set_direction_0

	set_direction_1:
		ldi	temp1,1
		mov	direction,temp1
		rjmp change_line

	set_direction_0:
		ldi	temp1,0
		mov	direction,temp1
		rjmp change_line

	change_line:					; move Z register to next line
		clr	counter
		ldi	temp1,1
		mov	counter,temp1
		inc	Y_cursor
		adiw ZH:ZL,NUMBER_COL_dec_2	; fix adiw out of range problem
		adiw ZH:ZL,1
		adiw ZH:ZL,1
		rcall search_position

search_position:					; show current position
	lpm		reader, Z
	mov		Z_cursor,reader
	rcall	display_position
	reti

found:								; show found result
	ser	temp1	
	out	PortC,temp1					; set all LED light on
	SET_MOTOR_SPEED	0x40			; half speed motor
	rcall display_found				
	STOP_TIME1						; stop timer 1
	jmp	end

end:
	;FLASH
	rjmp	end

/////////////////////////////////////////////////
//											   //
//				LCD Display Functions		   //
//											   //
/////////////////////////////////////////////////

lcd_command:
	STORE LCD_DATA_PORT, r16
	rcall sleep_1ms
	LDC_SET LCD_E
	rcall sleep_1ms
	LDC_CLR LCD_E
	rcall sleep_1ms
	ret

lcd_data:
	STORE LCD_DATA_PORT, r16	
	LDC_SET LCD_RS			;RS	->	1	
	rcall sleep_1ms
	LDC_SET LCD_E			;Enable	input
	rcall sleep_1ms
	LDC_CLR LCD_E			;Disable	input
	rcall sleep_1ms
	LDC_CLR LCD_RS			;RS	->	0
	ret

lcd_wait:
	push r16
	clr r16
	STORE LCD_DATA_DDR, r16
	STORE LCD_DATA_PORT, r16
	LDC_SET LCD_RW
lcd_wait_loop:
	rcall sleep_1ms
	LDC_SET LCD_E
	rcall sleep_1ms
	LOAD r16, LCD_DATA_PIN
	LDC_CLR LCD_E
	sbrc r16, 7
	rjmp lcd_wait_loop
	LDC_CLR LCD_RW
	ser r16
	STORE LCD_DATA_DDR, r16
	pop r16
	ret


LCD_DISPLAY_NUMBER:
	;Converts the total into separate digits for printing.
	push r16;
	push r17;
	push r18;
	push r19;
	push temp2;

	mov r16,reader ;Temporary total
	clr r17; Hundreds
	clr r18; Tens
	clr r19; Ones

	;Extract Hundreds
	extract_100s:
		cpi r16, 100			;number	<-->100
		brlo extract_10s		;go	10
		inc r17;				;hundred+1
		subi r16, 100			;x-100
		jmp extract_100s

	;Ectract Tens
	extract_10s:
		cpi r16, 10
		brlo extract_1s
		inc r18
		subi r16, 10
		rjmp extract_10s

	;Extract Ones
	extract_1s:
		cpi r16, 1
		brlo display_digits
		inc r19
		subi r16, 1
		rjmp extract_1s

	display_digits:
		mov temp2, r17
		cpi temp2, 0
		breq display_digits_two
		subi temp2, -'0'
		;data contains the value in ascii to be written
		;rcall lcd_wait_busy
		DO_LCD_DATA	temp2	; write the character to the screen

		display_digits_two:

			cpi r18, 0
			brne display_digits_two_continue
			cpi r17, 0
			breq display_digits_one

			display_digits_two_continue:
			mov temp2, r18
    		subi temp2, -'0'
    		;data contains the value in ascii to be written
    		;rcall lcd_wait_busy
    		DO_LCD_DATA	temp2	; write the character to the screen

		display_digits_one:
			mov temp2, r19
    		subi temp2, -'0'
    		;data contains the value in ascii to be written
    		;rcall lcd_wait_busy
    		DO_LCD_DATA	temp2	; write the character to the screen

	pop temp2
	pop r23
	pop r22
	pop r21
	pop r20
	ret

/////////////////////////////////////////////////
//											   //
//					Sleep					   //
//											   //
/////////////////////////////////////////////////


.equ F_CPU = 16000000
.equ DELAY_1MS = F_CPU / 4 / 1000 - 4
; 4 cycles per iteration - setup/call-return overhead

sleep_1ms:			;delay
	push r24
	push r25
	ldi r25, high(DELAY_1MS)
	ldi r24, low(DELAY_1MS)
delayloop_1ms:
	sbiw r25:r24, 1
	brne delayloop_1ms
	pop r25
	pop r24
	ret

sleep_5ms:
	rcall sleep_1ms
	rcall sleep_1ms
	rcall sleep_1ms
	rcall sleep_1ms
	rcall sleep_1ms
	ret

sleep_50ms:
	rcall sleep_5ms
	rcall sleep_5ms
	rcall sleep_5ms
	rcall sleep_5ms
	rcall sleep_5ms
	rcall sleep_5ms
	rcall sleep_5ms
	rcall sleep_5ms
	rcall sleep_5ms
	rcall sleep_5ms
	ret

sleep_300ms:
	rcall sleep_50ms
	rcall sleep_50ms
	rcall sleep_50ms
	rcall sleep_50ms
	rcall sleep_50ms
	rcall sleep_50ms
	ret

/////////////////////////////////////////////////
//											   //
//				LCD Words					   //
//											   //
/////////////////////////////////////////////////

display_welcome:
	ldi	temp1,'W'
	DO_LCD_DATA temp1

	ldi	temp1,'e'
	DO_LCD_DATA temp1

	ldi	temp1,'l'
	DO_LCD_DATA temp1

	ldi	temp1,'c'
	DO_LCD_DATA temp1
	
	ldi	temp1,'o'
	DO_LCD_DATA temp1

	ldi	temp1,'m'
	DO_LCD_DATA temp1

	ldi	temp1,'e'
	DO_LCD_DATA temp1

	ldi	temp1,'!'
	DO_LCD_DATA temp1

	DO_LCD_COMMAND 0b11000000

	ldi	temp1,'E'
	DO_LCD_DATA temp1

	ldi	temp1,'n'
	DO_LCD_DATA temp1

	ldi	temp1,'t'
	DO_LCD_DATA temp1

	ldi	temp1,'e'
	DO_LCD_DATA temp1
	
	ldi	temp1,'r'
	DO_LCD_DATA temp1

	ldi	temp1,':'
	DO_LCD_DATA temp1

	ldi	temp1,'X'
	DO_LCD_DATA temp1

	ldi	temp1,'&'
	DO_LCD_DATA temp1

	ldi	temp1,'Y'
	DO_LCD_DATA temp1
	ret

display_input_x:
	ldi	temp1,'E'
	DO_LCD_DATA temp1

	ldi	temp1,'n'
	DO_LCD_DATA temp1

	ldi	temp1,'t'
	DO_LCD_DATA temp1

	ldi	temp1,'e'
	DO_LCD_DATA temp1
	
	ldi	temp1,'r'
	DO_LCD_DATA temp1

	ldi	temp1,' '
	DO_LCD_DATA temp1

	ldi	temp1,'X'
	DO_LCD_DATA temp1

	ldi	temp1,' '
	DO_LCD_DATA temp1

	ldi	temp1,'('
	DO_LCD_DATA temp1
	
	ldi	temp1,'1'
	DO_LCD_DATA temp1

	ldi	temp1,'-'
	DO_LCD_DATA temp1

	ldi	temp1,'6'
	DO_LCD_DATA temp1

	ldi	temp1,'4'
	DO_LCD_DATA temp1

	ldi	temp1,')'
	DO_LCD_DATA temp1

	DO_LCD_COMMAND 0b11000000

	ldi	temp1,'X'
	DO_LCD_DATA temp1

	ldi	temp1,'='
	DO_LCD_DATA temp1
	ret


display_input_y:
	ldi	temp1,'E'
	DO_LCD_DATA temp1

	ldi	temp1,'n'
	DO_LCD_DATA temp1

	ldi	temp1,'t'
	DO_LCD_DATA temp1

	ldi	temp1,'e'
	DO_LCD_DATA temp1
	
	ldi	temp1,'r'
	DO_LCD_DATA temp1

	ldi	temp1,' '
	DO_LCD_DATA temp1

	ldi	temp1,'Y'
	DO_LCD_DATA temp1

	ldi	temp1,' '
	DO_LCD_DATA temp1

	ldi	temp1,'('
	DO_LCD_DATA temp1
	
	ldi	temp1,'1'
	DO_LCD_DATA temp1

	ldi	temp1,'-'
	DO_LCD_DATA temp1

	ldi	temp1,'6'
	DO_LCD_DATA temp1

	ldi	temp1,'4'
	DO_LCD_DATA temp1

	ldi	temp1,')'
	DO_LCD_DATA temp1

	DO_LCD_COMMAND 0b11000000

	ldi	temp1,'Y'
	DO_LCD_DATA temp1

	ldi	temp1,'='
	DO_LCD_DATA temp1
	ret


display_start:
	ldi	temp1,'P'
	DO_LCD_DATA temp1

	ldi	temp1,'u'
	DO_LCD_DATA temp1

	ldi	temp1,'s'
	DO_LCD_DATA temp1

	ldi	temp1,'h'
	DO_LCD_DATA temp1

	ldi	temp1,' '
	DO_LCD_DATA temp1

	ldi	temp1,'B'
	DO_LCD_DATA temp1

	ldi	temp1,'u'
	DO_LCD_DATA temp1

	ldi	temp1,'t'
	DO_LCD_DATA temp1
	
	ldi	temp1,'t'
	DO_LCD_DATA temp1

	ldi	temp1,'o'
	DO_LCD_DATA temp1

	ldi	temp1,'n'
	DO_LCD_DATA temp1

	DO_LCD_COMMAND 0b11000000

	ldi	temp1,'T'
	DO_LCD_DATA temp1

	ldi	temp1,'o'
	DO_LCD_DATA temp1

	ldi	temp1,' '
	DO_LCD_DATA temp1

	ldi	temp1,'S'
	DO_LCD_DATA temp1

	ldi	temp1,'t'
	DO_LCD_DATA temp1

	ldi	temp1,'a'
	DO_LCD_DATA temp1

	ldi	temp1,'r'
	DO_LCD_DATA temp1
	
	ldi	temp1,'t'
	DO_LCD_DATA temp1

	ldi	temp1,' '
	DO_LCD_DATA temp1

	ldi	temp1,'G'
	DO_LCD_DATA temp1

	ret


display_position:

	DO_LCD_COMMAND 0b00000001

	ldi	temp1,'('
	DO_LCD_DATA temp1

	mov	reader,	X_cursor
	rcall	LCD_DISPLAY_NUMBER

	ldi	temp1,','
	DO_LCD_DATA temp1

	mov	reader,	Y_cursor
	rcall	LCD_DISPLAY_NUMBER

	ldi	temp1,','
	DO_LCD_DATA temp1

	mov	reader,	Z_cursor
	rcall	LCD_DISPLAY_NUMBER

	ldi	temp1,')'
	DO_LCD_DATA temp1

	DO_LCD_COMMAND 0b11000000

	ldi	temp1,'S'
	DO_LCD_DATA temp1

	ret


display_abort:

	DO_LCD_COMMAND 0b00000001

	ldi	temp1,'S'
	DO_LCD_DATA temp1

	ldi	temp1,'e'
	DO_LCD_DATA temp1

	ldi	temp1,'a'
	DO_LCD_DATA temp1

	ldi	temp1,'r'
	DO_LCD_DATA temp1

	ldi	temp1,'c'
	DO_LCD_DATA temp1

	ldi	temp1,'h'
	DO_LCD_DATA temp1

	ldi	temp1,' '
	DO_LCD_DATA temp1

	ldi	temp1,'A'
	DO_LCD_DATA temp1

	ldi	temp1,'b'
	DO_LCD_DATA temp1

	ldi	temp1,'o'
	DO_LCD_DATA temp1

	ldi	temp1,'r'
	DO_LCD_DATA temp1

	ldi	temp1,'t'
	DO_LCD_DATA temp1

	DO_LCD_COMMAND 0b11000000

	ldi	temp1,'A'
	DO_LCD_DATA temp1

	ret

display_found:

	DO_LCD_COMMAND 0b00000001

	ldi	temp1,'('
	DO_LCD_DATA temp1

	mov	reader,	X_cursor
	rcall	LCD_DISPLAY_NUMBER

	ldi	temp1,','
	DO_LCD_DATA temp1

	mov	reader,	Y_cursor
	rcall	LCD_DISPLAY_NUMBER

	ldi	temp1,','
	DO_LCD_DATA temp1

	mov	reader,	Z_cursor
	rcall	LCD_DISPLAY_NUMBER

	ldi	temp1,')'
	DO_LCD_DATA temp1

	DO_LCD_COMMAND 0b11000000

	ldi	temp1,'F'
	DO_LCD_DATA temp1

	ret

	/*
	DO_LCD_COMMAND 0b00000001

	ldi	temp1,'P'
	DO_LCD_DATA temp1

	ldi	temp1,'o'
	DO_LCD_DATA temp1

	ldi	temp1,'s'
	DO_LCD_DATA temp1

	ldi	temp1,'i'
	DO_LCD_DATA temp1

	ldi	temp1,'c'
	DO_LCD_DATA temp1

	ldi	temp1,'t'
	DO_LCD_DATA temp1

	ldi	temp1,'i'
	DO_LCD_DATA temp1

	ldi	temp1,'o'
	DO_LCD_DATA temp1

	ldi	temp1,'n'
	DO_LCD_DATA temp1

	ldi	temp1,' '
	DO_LCD_DATA temp1

	ldi	temp1,'F'
	DO_LCD_DATA temp1

	ldi	temp1,'o'
	DO_LCD_DATA temp1

	ldi	temp1,'u'
	DO_LCD_DATA temp1

	ldi	temp1,'n'
	DO_LCD_DATA temp1

	ldi	temp1,'d'
	DO_LCD_DATA temp1

	DO_LCD_COMMAND 0b11000000
	ldi	temp1,'G'
	DO_LCD_DATA temp1

	*/
	