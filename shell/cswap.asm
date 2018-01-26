; $Id$
; File:
;                          cswap.asm
; Description:
;                       command.com swapping
;
;                    Copyright (c) 2001 tom ehlert
;                       All Rights Reserved
;
; This file is part of DOS-C.
;
; DOS-C is free software; you can redistribute it and/or
; modify it under the terms of the GNU General Public License
; as published by the Free Software Foundation; either version
; 2, or (at your option) any later version.
;
; DOS-C is distributed in the hope that it will be useful, but
; WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See
; the GNU General Public License for more details.
;
; You should have received a copy of the GNU General Public
; License along with DOS-C; see the file COPYING.  If not,
; write to the Free Software Foundation, 675 Mass Ave,
; Cambridge, MA 02139, USA.
;
;

%include "../include/model.inc"

segment _BSS 			; transient data (in DS)

 	global _SwapResidentSize
_SwapResidentSize  resw 1

	global _XMSsave
_XMSsave	resw 8
%define currentSegmOfFreeCOMsave	_XMSsave+8

execSS resw 1
execSP resw 1

segment _DATA

resize_free db 4ah

segment _TEXT

	global _dosFCB1,_dosFCB2
_dosFCB1 times 37 db 0
_dosFCB2 times 37 db 0

;;	global _dosCMDTAIL, _dosCMDNAME		use command line from within PSP
	global _dosCMDNAME
;;_dosCMDTAIL  times 128 db 0
_dosCMDNAME times 128 db 0
 		times 256	db 0
;;    global localStack
localStack:


	global _dosParamDosExec
_dosParamDosExec times 22	db 0


	global _XMSdriverAdress
_XMSdriverAdress dd 0
%define callXMS		call far [_XMSdriverAdress]

 	global _SwapTransientSize
_SwapTransientSize  dw 0

	global _XMSrestore
_XMSrestore	times 8 DW 0
%define xms_handle	_XMSrestore+4
%define currentSegmOfFreeCOM	_XMSrestore+14

	global _termAddr
_termAddr:
terminationAddressOffs	DW 0
terminationAddressSegm	DW 0
	global _myPID
_myPID	DW 0
	global _origPPID
_origPPID DW 0
	global _canexit
_canexit	DB 0		; 1 -> can exit; _else_ --> cannot exit

    global _mySS, _mySP
_mySS DW 0
_mySP DW 0

execRetval dw 0

;	global real_XMSexec
real_XMSexec:
		int 21h	; shrink/free: first thing done from resident code

		; do exec


;;		mov ax, cs
                   		; ds:dx = ASCIZ program name
;;		mov ds, ax
		mov  dx,_dosCMDNAME
		       
                        ; es:bx = parameter block
		mov es, cx
		mov bx, _dosParamDosExec


						; our temporary stack
;;        mov ss, ax
;;        mov  sp,localStack


		mov ax,04b00h		; load & execute
		int 21h

		jc  exec_error
		xor ax,ax


exec_error:
		cld					; don't rely on that

	; reload into memory

        mov cx, cs
        mov ss, cx
        mov  sp,localStack-6	; location on stack of return cs:ip and ds

		; restore:

        mov ds, cx
		mov [execRetval],ax
							; we need some memory

		;; First ensure that FreeCOM is reloaded in low memory
		;; so that LOADHIGH would come into problems
;;ska		mov ax, 5800h		; Get current allocation strategy
;;ska		int 21h
;;ska		mov dx, ax

;;ska		mov ax, 5801h		; Set current allocation strategy
;;ska		mov bx, 0			; low memory / first fit
;;ska		int 21h
		; ignore any errors

		mov ah,48h
		mov bx,[_SwapTransientSize]
		int 21h

;;ska		pushf

		; Restore Alloc Strat
;;ska		mov ax, 5801h		; Set current allocation strategy
;;ska		mov bx, dx
;;ska		int 21h

;;ska		popf
		jc DOS_trouble_while_swapping_in

                                ; calculate relocation factor

		mov bx,ax				; new execute address
		sub bx,[currentSegmOfFreeCOM]		; new address - old address
		push bx					;
		mov  [currentSegmOfFreeCOM],ax	; new prog address

								; restore everything to XMS
		mov ah,0bh
		mov si,_XMSrestore
		callXMS

		pop bx                  ; get relocation factor back

		cmp ax,1
		jnz XMS_trouble_while_swapping_in

		mov bp,sp
		add [bp+2],bx		; relocate return segment

		retf						; done

XMS_err 		db 'XMS copy error$'
DOS_err 		db 'Memory allocation error$'
common_error	db 0dh,0ah,0ah,'FreeCOM: XMSSwap-In: $'

XMS_trouble_while_swapping_in:
	mov bx,XMS_err
	jmp short trouble_while_swapping_in

DOS_trouble_while_swapping_in:
	mov bx,DOS_err

trouble_while_swapping_in:
;		push cs							; do some error message
;		pop  ds
		mov dx, common_error
		mov ah,09
		int 21h

		mov dx,bx
		mov ah,09
		int 21h

terminate_myself:
		mov ax,04cffh					; and die ...
		int 21h

		;; FALL THROUGH for elder FreeCOM kernels that simply ignore
		;; DOS-4C for shells

	;; central PSP:0xa hook <-> may be called in every circumstance
	global _terminateFreeCOMHook
_terminateFreeCOMHook:
	mov ax, cs				; setup run environment (in this module)
	mov ss, ax
	mov sp, localStack
	mov ds, ax

	; Next time we hit here it's != 1 --> no zero flag --> I_AM_DEAD status
	dec BYTE [_canexit]
	jnz I_AM_DEAD

	mov ax, [_myPID]		; our own PSP [in case we arrived here
	mov es, ax				; in some strange ways]

	; Make sure the current PSP hasn't patched to nonsense already
	mov bx, ax
	mov ah, 50h				; Set PSP
	int 21h

	; Reset old termination address
	mov ax, [terminationAddressOffs]
	mov [es:0ah], ax
	mov ax, [terminationAddressSegm]
	mov [es:0ch], ax

	; Drop our "Shell" privileges
	mov ax, [_origPPID]		; original parent process ID
	mov [es:16h], ax

	; Kill the XMS memory block
	mov dx, [xms_handle]
	or dx, dx
	jz terminate_myself		; no block to deallocate
	mov ah, 0ah				; deallocate XMS memory block
	callXMS

	; Now, DOS-4C should proceed correctly
	jmp short terminate_myself


I_AM_DEAD:								; process 0 can't terminate ...
	mov dx, dead_loop_string
	mov ah, 9
	int 21h
I_AM_DEAD_loop:
	hlt
	jmp short I_AM_DEAD_loop

dead_loop_string	DB 13,10,7,'Cannot terminate permanent FreeCOM instance'
	DB 13,10,'System halted ... reboot or power off now$'

;
; as I don't know how to set the old interrupt handler
; I write my own
; or we use the TURBO_C _restorezero() and use the
; DOS default handler for that

%if 0
MsgZerodivide db 'integer zero divide$'
	global _ZeroDivideInterrupt
_ZeroDivideInterrupt:

		push cs
		pop ds
		mov dx,MsgZerodivide
		mov ah,09
		int 21h

        mov ax,04c7fh       ; terminate with errorlevel 127
        int 21h
		jmp _ZeroDivideInterrupt
%endif


;********************************************************************
; *************   END OF RESIDENT AREA ******************************
;********************************************************************
	global _SWAPresidentEnd
_SWAPresidentEnd:

%if 0
;
; normal EXEC
;

		global _DosEXEC
_DosEXEC:
						; save ALL registers needed later
		push si
		push di
		push bp
		push ds

		push cs                   		; ds:dx = ASCIZ program name
		pop	 ds

		mov  dx,_dosCMDNAME

		mov [execSS],ss
		mov [execSP],sp

		push cs
		pop  es
		mov bx, _dosParamDosExec

		mov ax,04b00h
		int 21h

		jc      exec_error2  ; if there was an error, the error code is in AX

		xor ax,ax

exec_error2:

		cld					; don't rely on that

		mov ss,[cs:execSS]
		mov sp,[cs:execSP]

		pop ds
		pop bp
		pop di
		pop	si
		retf
%endif

;; Added here to make it more easier for the C-part to make a XMS
;; request, because the code:
;;		(*XMSdriverAdress)();
;; is translated into something like:
;;		mov ax, _CODE		;; immediate value
;;		mov es, ax
;;		call DWORD PTR es:[_XMSdriverAdress]
;; detroying AX already holding the API function number

;; To be called with _far_!!
	global _XMSrequest
	;; Note: Because [CS:driverAdress] == [residentCS:driverAdress]
	;; we need not use a similiar approach as with XMSexec
_XMSrequest:
		jmp far [cs:_XMSdriverAdress]

;; Added here to make it more easier for the C-part to call functions
;; located in the resident part, because:
;;		_XMSexec();
;; is translated into something like:
;;		nop
;;		push cs			<-> WRONG!!
;;		call _XMSexec
;; now also used to contain code that does not need to be resident.

;;TODO: DS ought to be equal to SS, DS could be reconstructed from
;;	SS at the end of the XMSexec function
		global	_XMSexec
_XMSexec:
		extern _residentCS
						; save ALL registers needed later
		push si
		push di
		push bp

		mov [execSS],ss
		mov [execSP],sp

						; save everything to XMS
		mov ah,0bh
		mov si,_XMSsave
		call far [cs:_XMSdriverAdress]

;;TODO: test of result

		mov es,[currentSegmOfFreeCOMsave]
						; first time: shrink current psp
		mov ah,[resize_free]
		mov bx,[_SwapResidentSize]

		mov dx, ds
		mov cx, [_residentCS]
		mov ds, cx

        mov [_mySS],ss  ; 2E
        mov [_mySP],sp  ; 2E

		mov ss, cx		; this stack is definitely large enough AND present
        mov  sp,localStack

		push dx			; save DS of transient portion
		push cs			; save segment of transient portion
		push WORD ret_from_resident
		push cx
		push WORD real_XMSexec
		retf

ret_from_resident:
		mov ax,[execRetval]

                                    ; relocate segment registers
		add [bp+4],bx				; ds
		pop ds

		mov byte [resize_free],49h ; change to "free" for next times

		add [currentSegmOfFreeCOMsave],bx
		mov cx,[execSS]
		add cx,bx
		mov ss,cx
		mov sp,[execSP]

		pop bp
		pop di
		pop	si
		retn						; done (really)
