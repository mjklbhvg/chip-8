; Pong: This is just a test and far from a working game!

JP restart

; --------- VARIABLES ---------

player_score: DB 0
computer_score: DB 0

; These are stored as 6.2 bit fixed point numbers
ball_pos_x: DB 0
ball_pos_y: DB 0
ball_vel_x: DB 0
ball_vel_y: DB 0
; 0 means down/right, 1 means up/left
ball_dir_x: DB 0
ball_dir_y: DB 0

player_stick_y: DB 13
computer_stick_y: DB 13

; Sprites
stick_sprite:
	DB 0xc0
	DB 0xc0
	DB 0xc0
	DB 0xc0
	DB 0xc0
	DB 0xc0
	DB 0xc0
ball_sprite:
	DB 0x80

; --------- PROGRAM -----------

restart:
	; reset ball position to the middle of the screen
	LD V0, 128 ; x (32 << 2)
	LD V1, 64  ; y (16 << 2)
	; reset ball velocity
	LD V2, 3   ; x
	LD V3, 1   ; y
	LD V4, 0 ; x direction
	LD V5, 0 ; y direction

	LD I, ball_pos_x
	LD [I], V5

	; reset stick positions
	LD V0, 13
	LD V1, 13
	LD I, player_stick_y
	LD [I], V1

mainloop:
	LD V0, DT
	SE V0, 0
	JP mainloop

	; this runs each frame
	LD V0, 1
	LD DT, V0 ; setup delay timer for next frame

	CALL update_ball
	CALL update_sticks
	CALL repaint

	CALL handle_collision ; returns 1 in V0 if a reset should happen
	SE V0, 0
	JP restart
	
	JP mainloop

handle_collision: ; args: V0: ball collided, ret: V0 should reset
	LD VB, V0
	LD I, ball_pos_x
	LD V0, [I]
	SHR V0, V0
	SHR V0, V0
	LD VA, 0

	SNE V0, 1
	JP on_stick_position_player
	SNE V0, 0
	JP on_stick_position_player

	SNE V0, 62
	JP on_stick_position_computer
	SNE V0, 63
	JP on_stick_position_computer

	LD V0, 0
	JP ret_handle_collision
on_stick_position_player:
	LD VA, 1
on_stick_position_computer:
	; VA:  1 -> player, 0 -> computer

	SNE VB, 1
	JP bounce_ball

	; Someone scored! find out who and increment the score
	LD I, player_score
	LD V1, [I]
	SNE VA, 0
	ADD V0, 1
	SE VA, 0
	ADD V1, 1
	LD [I], V1

	LD V0, 1 ; should reset
	LD V2, 2
	LD ST, V2
	JP ret_handle_collision
bounce_ball:
	LD I, ball_dir_x
	LD V0, [I]
	LD V2, 1
	XOR V0, V2
	LD [I], V0

	; reset the ball before the stick to avoid
	; colliding again in the next frame
	LD I, ball_pos_x
	LD V0, [I]
	SE VA, 0
	LD V0, 8
	SNE VA, 0
	LD V0, 244
	LD [I], V0

	; now mutate the ball speed randomly for fun!
	LD I, ball_vel_x
	LD V1, [I]

	RND V2, 3
	ADD V0, V2
	RND V2, 1
	ADD V1, V2

	RND V2, 1
	SUB V0, V2
	RND V2, 1
	SUB V1, V2
	SNE V0, 0
	LD V0, 1

	LD [I], V1

	LD V0, 0 ; no reset
ret_handle_collision:
	RET

update_ball:
	LD I, ball_pos_x
	LD V5, [I]
	SE V4, 0
	SUB V0, V2
	SNE V4, 0
	ADD V0, V2

	SE V5, 0
	SUB V1, V3
	SNE V5, 0
	ADD V1, V3

check_wall_collisions:
	LD VA, 0
	LD VB, 31
	LD VC, V1
	SHR VC, V0
	SHR VC, V0

	SNE VC, VA
	LD V5, 0
	SNE VC, VB
	LD V5, 1

	LD [I], V5
	RET

update_sticks:
	LD V9, 1 ; amount to move on pressed key

	; player
	LD I, player_stick_y
	LD V0, [I]

	LD V2, 1 ; key '1' for up
	SKNP V2
	SUB V0, V9

	LD V2, 2 ; key '2' for down
	SKNP V2
	ADD V0, V9
	; write updated position back
	LD [I], V0

	; computer
	; first get the ball y-position into V2
	LD I, ball_pos_x
	LD V1, [I]
	; check if the ball is on the right side of the board,
	; if not skip the move
	LD VA, 128
	SUBN V0, VA
	SE VF, 0
	JP skip_move

	LD V2, V1 ; ball y-position in V2
	SHR V2, V2
	SHR V2, V2

	LD I, computer_stick_y
	LD V0, [I]
	LD VA, 2
	SUB V2, VA ; TODO: stuff breaks when this is negative
	SUBN V2, V0 ; VF is 1 if ball is below stick
	SNE V2, 1
	JP skip_move
	LD V4, VF
	LD V3, 0
	SE V4, V3
	; move down
	SUB V0, V9

	SNE V4, V3
	; move up
	ADD V0, V9
	; write updated position back
	LD [I], V0
skip_move:
	RET

repaint: ; ret: V0: the ball collided
	CLS

	; player score
	LD I, player_score
	LD V1, [I]
	LD V2, 25
	CALL paint_score

	; computer score
	LD V0, V1
	LD V2, 38
	CALL paint_score

	; player stick
	LD I, player_stick_y
	LD V1, [I]
	LD I, stick_sprite
	LD V2, 0
	DRW V2, V0, 7

	; computer stick
	LD V2, 62
	DRW V2, V1, 7

	; finally paint the ball
	LD I, ball_pos_x
	LD V1, [I]
	SHR V0, V0
	SHR V0, V0
	SHR V1, V0
	SHR V1, V0
	LD I, ball_sprite
	DRW V0, V1, 1
	LD V0, VF
	RET

paint_score: ; args: V0: score, V2: x position
	LD F, V0
	LD VF, 1
	DRW V2, VF, 5
	RET

