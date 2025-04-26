
.section .text

.global crashMe
crashMe:
	bkpt
	svc 0
	bkpt
	bx lr
