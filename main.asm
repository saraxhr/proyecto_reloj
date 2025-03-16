.include "m328pdef.inc"

; Definición de registros
.def temp = r16
.def display_actual = r17
.def digit_sel = r18
.def hora_h = r19
.def hora_l = r20
.def min_h = r21
.def min_l = r22
.def seg_h = r23
.def seg_l = r24
.def debounce_counter = r25 
.def temp2 = r3         ; Registro temporal adicional
.def modo = r4          ; 0 = hora, 1 = fecha, 2 = alarma
.def dia_h = r5         ; Decenas de día
.def dia_l = r6         ; Unidades de día
.def mes_h = r7         ; Decenas de mes
.def mes_l = r8         ; Unidades de mes
.def led_counter = r13    ; Contador para el parpadeo de LEDs




; Definición de botones y LEDS
.equ BUTTON_SEL = PINC1
.equ BUTTON_INC = PINC2
.equ BUTTON_DEC = PINC3
.equ LED1 = 3            ; PB3
.equ LED2 = 4            ; PB4
; Vector de interrupciones
.org 0x0000
    rjmp RESET
.org PCI1addr
    rjmp PIN_CHANGE_ISR
.org OVF0addr
    rjmp TIMER0_OVF

; Tabla de segmentos (cátodo común)
tabla_7seg:
    .db 0b00111111, 0b00000110  ; 0, 1
    .db 0b01011011, 0b01001111  ; 2, 3
    .db 0b01100110, 0b01101101  ; 4, 5
    .db 0b01111101, 0b00000111  ; 6, 7
    .db 0b01111111, 0b01101111  ; 8, 9

	RESET:
    ; Stack setup
    ldi temp, high(RAMEND)
    out SPH, temp
    ldi temp, low(RAMEND)
    out SPL, temp

    ; Configuración de puertos
    ldi temp, 0xFF        ; PORTD como salida
    out DDRD, temp
    ldi temp, 0x1F        ; PB0-PB4 como salidas (0b00011111) - Agregado PB3 y PB4 para LEDs
    out DDRB, temp
    ldi temp, 0x00        ; PORTC como entrada
    out DDRC, temp
    ldi temp, 0x0E        ; Pull-up en PC1-PC3 (0b00001110)
    out PORTC, temp       ; Activar pull-ups

    ; Inicializar contador de LEDs
    clr led_counter       ; Agregar esta línea

    ; Inicialización de variables
    clr display_actual
    clr digit_sel
    clr hora_h
    ldi temp, 1           ; Iniciar en 01:00
    mov hora_l, temp
    clr min_h
    clr min_l

    clr modo            ; Iniciar en modo hora
    ldi temp, 1
    mov dia_l, temp     ; Iniciar en día 01
    clr dia_h
    ldi temp, 1
    mov mes_l, temp     ; Iniciar en mes 01
    clr mes_h

    ; Configuración de PORTC
    ldi temp, 0x00      ; PORTC como entrada
    out DDRC, temp
    ldi temp, 0x0F      ; Pull-up en PC0-PC3 (0b00001111)
    out PORTC, temp

    ; Configuración Timer0 para multiplexación
    ldi temp, (1<<CS01)   ; Prescaler 8
    out TCCR0B, temp
    ldi temp, (1<<TOIE0)
    sts TIMSK0, temp

    ; Configuración de interrupciones para botones
    ldi temp, (1<<PCIE1)  ; Habilitar PCINT para PORTC
    sts PCICR, temp
    ldi temp, (1<<PCINT9)|(1<<PCINT10)|(1<<PCINT11)  ; Habilitar pines específicos
    sts PCMSK1, temp

    sei                   ; Habilitar interrupciones globales

MAIN_LOOP:
    rjmp MAIN_LOOP

TIMER0_OVF:
    push temp
    in temp, SREG
    push temp
    push temp2        ; Guardar temp2 (r3)

    ; Verificar si estamos en modo hora antes de cualquier operación con LEDs
    mov temp, modo
    cpi temp, 0
    brne set_leds_by_mode   ; Si no estamos en modo hora, configurar LEDs según modo

    ; Solo manejar parpadeo en modo hora
    mov temp, led_counter
    inc temp
    mov led_counter, temp
    cpi temp, 250        
    brne continue_display

    ; Toggle LEDs solo en modo hora
    clr led_counter
    in temp, PORTB
    sbrc temp, 3
    rjmp toggle_off
    
toggle_on:
    sbi PORTB, 3
    sbi PORTB, 4
    rjmp continue_display

toggle_off:
    cbi PORTB, 3
    cbi PORTB, 4
    rjmp continue_display

set_leds_by_mode:
    cpi temp, 1          ; ¿Es modo fecha?
    breq set_fecha_leds_timer    ; Si es modo fecha, ir a set_fecha_leds_timer
    
    ; Si llegamos aquí, es modo alarma
    cbi PORTB, 3       ; Apagar ambos LEDs para modo alarma
    cbi PORTB, 4
    rjmp continue_display

set_fecha_leds_timer:    
    ; Modo fecha - LEDs siempre encendidos
    sbi PORTB, 3
    sbi PORTB, 4
    rjmp continue_display

set_alarma_leds_timer:
    ; Modo alarma - LEDs siempre apagados
    cbi PORTB, 3
    cbi PORTB, 4

continue_display:
    ; Apagar displays manteniendo estado de LEDs
    in temp, PORTB
    andi temp, (1<<3)|(1<<4)    ; Mantener solo los bits de LEDs (PB3 y PB4)
    mov temp2, temp             ; Guardar estado de LEDs
    
    ldi temp, 0x00             ; Limpiar displays
    out PORTB, temp
    out PORTD, temp
    
    ; Restaurar estado de LEDs
    in temp, PORTB
    or temp, temp2             ; Combinar con estado guardado de LEDs
    out PORTB, temp

    ; Rotar al siguiente display
    inc display_actual
    andi display_actual, 0x03

    ; Verificar modo actual
    mov temp, modo
    cpi temp, 0
    breq show_hora_modo
    cpi temp, 1
    breq show_fecha_modo
    rjmp show_alarma_modo

show_hora_modo:
    mov temp, display_actual
    cpi temp, 0
    breq show_hora_h
    cpi temp, 1
    breq show_hora_l
    cpi temp, 2
    breq show_min_h
    rjmp show_min_l

show_fecha_modo:
    mov temp, display_actual
    cpi temp, 0
    breq show_dia_h
    cpi temp, 1
    breq show_dia_l
    cpi temp, 2
    breq show_mes_h
    rjmp show_mes_l

show_alarma_modo:
    mov temp, display_actual
    cpi temp, 0
    breq show_hora_h
    cpi temp, 1
    breq show_hora_l
    cpi temp, 2
    breq show_min_h
    rjmp show_min_l

show_dia_h:
    mov temp, dia_h
    rcall mostrar_digito
    sbi PORTD, 7
    rjmp end_timer0

show_dia_l:
    mov temp, dia_l
    rcall mostrar_digito
    sbi PORTB, 0
    rjmp end_timer0

show_mes_h:
    mov temp, mes_h
    rcall mostrar_digito
    sbi PORTB, 1
    rjmp end_timer0

show_mes_l:
    mov temp, mes_l
    rcall mostrar_digito
    sbi PORTB, 2
    rjmp end_timer0

show_hora_h:
    mov temp, hora_h
    rcall mostrar_digito
    sbi PORTD, 7
    rjmp end_timer0

show_hora_l:
    mov temp, hora_l
    rcall mostrar_digito
    sbi PORTB, 0
    rjmp end_timer0

show_min_h:
    mov temp, min_h
    rcall mostrar_digito
    sbi PORTB, 1
    rjmp end_timer0

show_min_l:
    mov temp, min_l
    rcall mostrar_digito
    sbi PORTB, 2
    rjmp end_timer0

end_timer0:
    pop temp2           ; Restaurar temp2
    pop temp
    out SREG, temp
    pop temp
    reti

mostrar_digito:
    push ZH
    push ZL
    
    ldi ZH, high(tabla_7seg * 2)
    ldi ZL, low(tabla_7seg * 2)
    add ZL, temp
    lpm temp, Z
    out PORTD, temp
    
    pop ZL
    pop ZH
    ret

PIN_CHANGE_ISR:
    push temp
    in temp, SREG
    push temp

    ; Antirrebote
    ldi debounce_counter, 255
outer_delay:
    ldi temp, 255
inner_delay:
    dec temp
    brne inner_delay
    dec debounce_counter
    brne outer_delay

    ; Leer estado actual de los botones
    in temp, PINC
    
    ; Verificar botón de modo (PC0)
    sbrs temp, PINC0
    rcall cambiar_modo
    
    ; Verificar otros botones
    sbrs temp, BUTTON_SEL
    rcall cambiar_digito
    
    sbrs temp, BUTTON_INC
    rcall incrementar_digito
    
    sbrs temp, BUTTON_DEC
    rcall decrementar_digito

    ; Esperar a que se suelten los botones
wait_release:
    in temp, PINC
    andi temp, 0x0F     ; Máscara para PC0-PC3
    cpi temp, 0x0F      ; Verificar si todos los botones están liberados
    brne wait_release

    pop temp
    out SREG, temp
    pop temp
    reti
	cambiar_digito:
    push temp
    
    mov temp, modo      ; Cargar el modo actual
    cpi temp, 0        ; ¿Es modo hora?
    brne check_fecha_sel
    
    ; Modo hora
    inc digit_sel      ; Incrementar selección
    cpi digit_sel, 4   ; ¿Llegó a 4?
    brne exit_sel      ; Si no, salir
    clr digit_sel      ; Si sí, volver a 0
    rjmp exit_sel

check_fecha_sel:
    cpi temp, 1        ; ¿Es modo fecha?
    brne check_alarma_sel
    
    ; Modo fecha
    inc digit_sel      ; Incrementar selección
    cpi digit_sel, 4   ; ¿Llegó a 4?
    brne exit_sel      ; Si no, salir
    clr digit_sel      ; Si sí, volver a 0
    rjmp exit_sel

check_alarma_sel:
    ; Modo alarma (por ahora igual que hora)
    inc digit_sel      ; Incrementar selección
    cpi digit_sel, 4   ; ¿Llegó a 4?
    brne exit_sel      ; Si no, salir
    clr digit_sel      ; Si sí, volver a 0

exit_sel:
    pop temp
    ret


cambiar_modo:
    push temp           

    ; Cambiar modo de manera simple (0->1->2->0)
    mov temp, modo      
    inc temp           
    cpi temp, 3        
    brne save_new_modo     
    clr temp           

save_new_modo:
    mov modo, temp      ; Guardar nuevo modo
    
    ; Configurar LEDs directamente según el modo
    cpi temp, 0        ; Verificar modo
    breq set_hora_leds
    cpi temp, 1
    breq set_fecha_leds
    rjmp set_alarma_leds

set_hora_leds:
    sbi PORTB, 3       ; Encender ambos LEDs para modo hora
    sbi PORTB, 4
    clr led_counter    ; Resetear contador para parpadeo
    rjmp end_modo

set_fecha_leds:
    sbi PORTB, 3       ; Encender ambos LEDs para modo fecha
    sbi PORTB, 4
    rjmp end_modo

set_alarma_leds:
    cbi PORTB, 3       ; Apagar ambos LEDs para modo alarma
    cbi PORTB, 4

end_modo:
    pop temp           
    ret

; Rutinas de incremento

incrementar_digito:
    push temp
    mov temp, modo
    cpi temp, 0
    brne check_fecha     ; Si no es modo hora, verificar si es modo fecha
    
    ; Modo hora (modo = 0)
    pop temp
    push temp
    mov temp, digit_sel
    
    cpi temp, 0
    breq inc_hora_h
    cpi temp, 1
    breq inc_hora_l
    cpi temp, 2
    breq inc_min_h
    cpi temp, 3
    breq inc_min_l
    rjmp inc_exit

check_fecha:
    cpi temp, 1
    brne inc_exit      ; Si no es modo fecha, salir (por ahora ignoramos modo alarma)
    
    ; Modo fecha (modo = 1)
    pop temp
    push temp
    mov temp, digit_sel
    
    cpi temp, 0
    breq inc_dia_h
    cpi temp, 1
    breq inc_dia_l
    cpi temp, 2
    breq inc_mes_h
    cpi temp, 3
    breq inc_mes_l
    rjmp inc_exit

inc_hora_h:
    inc hora_h
    cpi hora_h, 3
    brne exit_inc_h
    clr hora_h
exit_inc_h:
    pop temp
    ret

inc_hora_l:              ; PB0 - debe contar de 0 a 9
    inc hora_l
    cpi hora_l, 10      ; Comprobar si llegó a 10
    brne no_reset_hora_l
    clr hora_l          ; Si llegó a 10, volver a 0
no_reset_hora_l:
    pop temp
    ret

inc_min_h:
    inc min_h
    cpi min_h, 6
    brne exit_inc_mh
    clr min_h
exit_inc_mh:
    pop temp
    ret

inc_min_l:              ; PB2 - debe contar de 0 a 9
    inc min_l
    cpi min_l, 10      ; Comprobar si llegó a 10
    brne no_reset_min_l
    clr min_l          ; Si llegó a 10, volver a 0
no_reset_min_l:
    pop temp
    ret

inc_dia_h:
    inc dia_h
    rcall verificar_dia
    rjmp inc_exit

inc_dia_l:
    inc dia_l
    rcall verificar_dia
    rjmp inc_exit

inc_mes_h:
    inc mes_h
    rcall verificar_mes
    rjmp inc_exit

inc_mes_l:
    inc mes_l
    rcall verificar_mes
    rjmp inc_exit

inc_exit:
    pop temp
    ret

decrementar_digito:
    push temp
    mov temp, digit_sel
    
    cpi temp, 0
    brne check_dec_1
    rjmp dec_hora_h
    
check_dec_1:
    cpi temp, 1
    brne check_dec_2
    rjmp dec_hora_l
    
check_dec_2:
    cpi temp, 2
    brne check_dec_3
    rjmp dec_min_h
    
check_dec_3:
    cpi temp, 3
    brne dec_exit
    rjmp dec_min_l
    
dec_exit:
    pop temp
    ret

dec_hora_h:
    dec hora_h
    brpl exit_dec_h
    ldi hora_h, 2
exit_dec_h:
    pop temp
    ret

dec_hora_l:             ; PB0 - debe contar de 9 a 0
    dec hora_l
    brpl exit_dec_l     ; Si es positivo, mantener el valor
    ldi hora_l, 9      ; Si es negativo, volver a 9
exit_dec_l:
    pop temp
    ret

dec_min_h:
    dec min_h
    brpl exit_dec_mh
    ldi min_h, 5
exit_dec_mh:
    pop temp
    ret

dec_min_l:             ; PB2 - debe contar de 9 a 0
    dec min_l
    brpl exit_dec_ml   ; Si es positivo, mantener el valor
    ldi min_l, 9      ; Si es negativo, volver a 9
exit_dec_ml:
    pop temp
    ret

	verificar_dia:
    push r16        ; Usar r16 en lugar de temp
    push r17        ; Usar r17 en lugar de temp2
    
    ; Combinar mes_h y mes_l en un solo número
    mov r16, mes_h
    lsl r16         ; Multiplicar por 10
    lsl r16
    lsl r16
    add r16, mes_h
    lsl r16
    add r16, mes_l  ; r16 ahora tiene el número de mes (1-12)
    
    ; Combinar dia_h y dia_l
    mov r17, dia_h
    lsl r17         ; Multiplicar por 10
    lsl r17
    lsl r17
    add r17, dia_h
    lsl r17
    add r17, dia_l  ; r17 ahora tiene el número de día

    ; Verificar el mes
    cpi r16, 2      ; Febrero
    breq check_feb
    cpi r16, 4      ; Abril
    breq check_30
    cpi r16, 6      ; Junio
    breq check_30
    cpi r16, 9      ; Septiembre
    breq check_30
    cpi r16, 11     ; Noviembre
    breq check_30
    
    ; Meses de 31 días
    cpi r17, 32
    brlo exit_verify
    ldi r16, 0
    mov dia_h, r16
    ldi r16, 1
    mov dia_l, r16
    rjmp exit_verify

check_30:
    cpi r17, 31
    brlo exit_verify
    ldi r16, 0
    mov dia_h, r16
    ldi r16, 1
    mov dia_l, r16
    rjmp exit_verify

check_feb:
    cpi r17, 29
    brlo exit_verify
    ldi r16, 0
    mov dia_h, r16
    ldi r16, 1
    mov dia_l, r16

exit_verify:
    pop r17
    pop r16
    ret

verificar_mes:
    push r16
    
    ; Combinar mes_h y mes_l
    mov r16, mes_h
    lsl r16
    lsl r16
    lsl r16
    add r16, mes_h
    lsl r16
    add r16, mes_l

    cpi r16, 13
    brlo exit_verify_mes
    ldi r16, 0
    mov mes_h, r16
    ldi r16, 1
    mov mes_l, r16

exit_verify_mes:
    pop r16
    ret
