; Pong: This is just a test and far from a working game!

; V9     - player stick y 
; VA, VB - ball coords, shift right by 2 to get on-screen position
; VC, VD - ball velocity MSB is direction. The ball can travel faster than one
;	pixel per frame, breaking the hit detection with the sticks :|
; VE,    - scores, 4bits each

restart:
	; initial ball position
	LD VA, 128
	LD VB, 60

	; initial player stick position
	LD V9, 13

	LD VC, 2 ; initial ball-vel x
	LD VD, 1 ; initial ball-vel y

mainloop:
	
	CALL process_input

	LD V0, DT
	SE V0, 0
	JP mainloop

	;; this runs each frame
	LD V0, 1
	LD DT, V0 ; setup delay timer for next frame

	CALL update_ball
	
	; ball on-screen x
	LD V0, VA
	SHR V0, V0
	SHR V0, V0
	
	; ball on-screen y
	LD V1, VB
	SHR V1, V1
	SHR V1, V1

	; invert ball y direction if it hits the top or bottom borders
	LD V2, 0x80
	SNE V1, 0
	XOR VD, V2
	SNE V1, 31
	XOR VD, V2

	CALL repaint
	; at this point VF is 1 if the ball collided with something
	; -> save it in V1
	LD V1, VF
	CALL handle_collision ; returns 1 in v0 if a reset should happen
	SNE V0, 1
	JP restart
	
	; randomly increase ball speed
	;RND V0, 0xFF
	;SNE V0, 0
	;ADD VC, 1
	JP mainloop

handle_collision: ; args: V0 = ball on-screen x, V1 = collision flag
	LD V5, 0x80
	SNE V0, 62
	JP computer_check
	SNE V0, 1
	JP player_check
	LD V0, 0
	RET
player_check:
	SE V1, 1
	JP computer_scores
	; the player reflected! set the balls x position to 2 << 2
	; and  invert the ball x velocty
	LD VA, 8
	XOR VC, V5
	JP change_ball_speed
computer_scores:
	LD V0, 10
	LD ST, V0
	LD V0, 0x10
	ADD VE, V0
	LD V0, 1
	RET
computer_check:
	SE V1, 1
	JP player_scores
	; the computer reflected!
	LD VA, 244
	XOR VC, V5
	JP change_ball_speed
player_scores:
	LD V0, 10
	LD ST, V0
	LD V0, 1
	ADD VE, V0
	RET
change_ball_speed:
	; add or suptract some ball speed randomly

	; 50% chance to flip the ball y direction
	RND V0, 0x80
	RND V1, 1
	SNE V1, 0
	XOR VD, V0

	; add 0-2 to ball y-speed
	RND V0, 2
	ADD VD, V0

	; subtract 0-2 from ball y-speed
	RND V0, 2
	SUB VD, V0
	SNE VF, 0
	LD VD, 0

	; randomly increase ball x-speed
	RND V0, 1
	ADD VC, V0
	LD V0, 0
	RET

process_input:
	LD V0, 1
	LD V1, 1
	SKNP V0
	SUB V9, V1
	LD V0, 2
	SKNP V0
	ADD V9, V1
	RET
	
repaint: ; args: V0 = ball on-screen x, V1 = ball on-screen y
	LD V2, 1 ; player stick x, score sprites y
	LD V3, 62 ; computer stick x
	
	; calculate computer's stick y based on the ball y
	LD V4, V1
	LD V5, 2
	SUB V4, V5

	LD V5, 25 ; player score x
	LD V6, 38 ; computer score x

	; player score
	LD V7, VE
	LD V8, 0xF
	AND V7, V8

	; computer score
	LD V8, VE
	SHR V8, V8
	SHR V8, V8
	SHR V8, V8
	SHR V8, V8

	; draw the sticks
	LD I, stick_sprite
	CLS
	DRW V2, V9, 5 ; player
	DRW V3, V4, 5 ; computer
	
	; draw the scores
	LD F, V7
	DRW V5, V2, 5
	LD F, V8
	DRW V6, V2, 5

	; draw the ball
	LD I, ball_sprite
	DRW V0, V1, 1
	RET
	
update_ball:
	LD V2, 0x7f
	
	LD V1, VC
	AND V1, V2
	LD V0, VC
	SHL V0, V0
	SNE VF, 0 ; ball is going to the left
	ADD VA, V1
	LD V0, VC
	SHL V0, V0
	SE VF, 0 ; ball is going to the right
	SUB VA, V1

	LD V1, VD
	AND V1, V2
	LD V0, VD
	SHL V0, V0
	SNE VF, 0 ; ball is going down
	ADD VB, V1
	LD V0, VD
	SHL V0, V0
	SE VF, 0 ; ball is going up
	SUB VB, V1
	RET

stick_sprite:
	DB 0x80
	DB 0x80
	DB 0x80
	DB 0x80
	DB 0x80
ball_sprite:
	DB 0x80
