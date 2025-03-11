;******************************************************************************
; Reloj Digital con ATmega 328p
; Autor: saraxhr 
; Fecha: 2025-03-04
; Hora: 20:49:54
;******************************************************************************

.include "m328pdef.inc"

; Definiciones de pines
; Segmentos del display (PORTD)
.equ SEGMENT_A = PD1
.equ SEGMENT_B = PD0
.equ SEGMENT_C = PD2
.equ SEGMENT_D = PD3
.equ SEGMENT_E = PD4
.equ SEGMENT_F = PD5
.equ SEGMENT_G = PD6

; Pines de control para multiplexación
.equ DISPLAY1_PIN = PD7
.equ DISPLAY2_PIN = PB0
.equ DISPLAY3_PIN = PB1
.equ DISPLAY4_PIN = PB2

; LEDs y Buzzer (PORTB)
.equ LED1_PIN = PB4
.equ LED2_PIN = PB3
.equ BUZZER_PIN = PB5

; Botones (PORTC)
.equ BTN_MODE = PC0
.equ BTN_SELECT = PC1
.equ BTN_INCREMENT = PC2
.equ BTN_DECREMENT = PC3
.equ BTN_ALARM_OFF = PC4

; Estados de la FSM
.equ STATE_SHOW_TIME = 0x00
.equ STATE_SHOW_DATE = 0x10
.equ STATE_SHOW_ALARM = 0x20
.equ STATE_SET_HOUR = 0x01
.equ STATE_SET_MINUTE = 0x02
.equ STATE_SET_DAY = 0x11
.equ STATE_SET_MONTH = 0x12
.equ STATE_SET_ALARM_HOUR = 0x21
.equ STATE_SET_ALARM_MINUTE = 0x22
.equ STATE_ALARM_ON = 0xF1

; Vector Table
.cseg
.org 0x0000
    jmp RESET           ; Reset Handler
.org INT0addr
    reti               ; External Interrupt Request 0
.org INT1addr
    reti               ; External Interrupt Request 1
.org PCI0addr
    reti               ; Pin Change Interrupt Request 0
.org PCI1addr
    jmp PCINT1_ISR     ; Pin Change Interrupt Request 1
.org PCI2addr
    reti               ; Pin Change Interrupt Request 2
.org WDTaddr
    reti               ; Watchdog Time-out Interrupt
.org OC2Aaddr
    reti               ; Timer/Counter2 Compare Match A
.org OC2Baddr
    reti               ; Timer/Counter2 Compare Match B
.org OVF2addr
    reti               ; Timer/Counter2 Overflow
.org ICP1addr
    reti               ; Timer/Counter1 Capture Event
.org OC1Aaddr
    jmp TIMER1_COMP    ; Timer/Counter1 Compare Match A
.org OC1Baddr
    reti               ; Timer/Counter1 Compare Match B
.org OVF1addr
    reti               ; Timer/Counter1 Overflow
.org OC0Aaddr
    jmp TIMER0_COMP    ; Timer/Counter0 Compare Match A
.org OC0Baddr
    reti               ; Timer/Counter0 Compare Match B
.org OVF0addr
    reti               ; Timer/Counter0 Overflow

; Mover el inicio del código a 0x100 para evitar conflictos
.org 0x100             ; Nueva dirección de inicio para el código

; Tablas de datos
.cseg
.org 0x100  ; Asegurar que comienza en una dirección alineada
digit_table:
    .dw 0b00111111  ; 0
    .dw 0b00000110  ; 1
    .dw 0b01011011  ; 2
    .dw 0b01001111  ; 3
    .dw 0b01100110  ; 4
    .dw 0b01101101  ; 5
    .dw 0b01111101  ; 6
    .dw 0b00000111  ; 7
    .dw 0b01111111  ; 8
    .dw 0b01101111  ; 9



days_in_month:         ; Tabla de días por mes
    .db 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31

buzzer_pattern:
    .db 0xFF, 0x00      ; Patrón simple de encendido/apagado para la alarma

; Variables en SRAM
.dseg
.org 0x200            ; Mover las variables más arriba en la SRAM
current_hours:    .byte 1
current_minutes:  .byte 1
current_seconds:  .byte 1
current_day:      .byte 1
current_month:    .byte 1
alarm_hours:      .byte 1
alarm_minutes:    .byte 1
alarm_enabled:    .byte 1
estado_actual:    .byte 1
display_buffer:   .byte 4
current_digit:    .byte 1
timer0_count:     .byte 1
timer1_count:     .byte 1
led_state:        .byte 1
digit_blink_state: .byte 1
last_button_state: .byte 1
button_debounce_timer: .byte 1

.cseg


RESET:
    ; Inicialización del stack
    ldi r16, low(RAMEND)
    out SPL, r16
    ldi r16, high(RAMEND)
    out SPH, r16

    ; Configuración de puertos
    ; PORTB - Configurar salidas (displays 2-4, LEDs y buzzer)
    in r16, DDRB
    ori r16, (1<<BUZZER_PIN)|(1<<LED1_PIN)|(1<<LED2_PIN)|(1<<DISPLAY2_PIN)|(1<<DISPLAY3_PIN)|(1<<DISPLAY4_PIN)
    out DDRB, r16
    
    in r16, PORTB
    andi r16, ~((1<<BUZZER_PIN)|(1<<LED1_PIN)|(1<<LED2_PIN)|(1<<DISPLAY2_PIN)|(1<<DISPLAY3_PIN)|(1<<DISPLAY4_PIN))
    out PORTB, r16

    ; PORTC - Configurar entradas con pull-up (botones)
    in r16, DDRC
    andi r16, ~((1<<BTN_MODE)|(1<<BTN_SELECT)|(1<<BTN_INCREMENT)|(1<<BTN_DECREMENT)|(1<<BTN_ALARM_OFF))
    out DDRC, r16
    
    in r16, PORTC
    ori r16, (1<<BTN_MODE)|(1<<BTN_SELECT)|(1<<BTN_INCREMENT)|(1<<BTN_DECREMENT)|(1<<BTN_ALARM_OFF)
    out PORTC, r16

    ; PORTD - Configurar salidas (segmentos y DISPLAY1)
    ldi r16, 0xFF        ; Todos los pines como salida
    out DDRD, r16
    clr r16
    out PORTD, r16       ; Inicialmente apagados

    ; Configurar Timer0 para multiplexación (CTC, 4ms)
    ldi r16, (1<<WGM01)  ; Modo CTC
    out TCCR0A, r16
    ldi r16, (1<<CS01)|(1<<CS00)  ; Prescaler 64
    out TCCR0B, r16
    ldi r16, 249         ; Para 4ms con prescaler 64
    out OCR0A, r16
    ldi r16, (1<<OCIE0A) ; Habilitar interrupción Compare Match A
    sts TIMSK0, r16

    ; Configurar Timer1 para base de tiempo (CTC, 500ms)
    ldi r16, (1<<WGM12)  ; Modo CTC
    sts TCCR1B, r16
    ldi r16, (1<<CS12)|(1<<CS10)  ; Prescaler 1024
    sts TCCR1B, r16
    ldi r16, high(7812)  ; Para 500ms con prescaler 1024
    sts OCR1AH, r16
    ldi r16, low(7812)
    sts OCR1AL, r16
    ldi r16, (1<<OCIE1A) ; Habilitar interrupción Compare Match A
    sts TIMSK1, r16

    ; Configurar Pin Change Interrupt para PORTC
    ldi r16, (1<<PCIE1)  ; Habilitar PCINT[14:8] para PORTC
    sts PCICR, r16
    ldi r16, 0x1F        ; Habilitar PCINT[12:8] para PC[4:0]
    sts PCMSK1, r16

    ; Inicializar variables
    ldi r16, 21          ; Hora inicial: 21:32:57
    sts current_hours, r16
    ldi r16, 32
    sts current_minutes, r16
    ldi r16, 57
    sts current_seconds, r16
    
    ldi r16, 4           ; Fecha inicial: 4 de marzo
    sts current_day, r16
    ldi r16, 3
    sts current_month, r16

    clr r16
    sts alarm_hours, r16
    sts alarm_minutes, r16
    sts alarm_enabled, r16
    sts estado_actual, r16
    sts current_digit, r16
    sts timer0_count, r16
    sts timer1_count, r16
    sts led_state, r16
    sts digit_blink_state, r16
    sts last_button_state, r16
    sts button_debounce_timer, r16

    ; Habilitar interrupciones globales
    sei

main_loop:
    call read_buttons
    call check_state
    jmp main_loop

PCINT1_ISR:
    push r16
    in r16, SREG
    push r16
    push r17
    push r18

    ; Leer estado actual de botones
    in r16, PINC
    com r16              ; Invertir porque son pull-up
    andi r16, 0x1F      ; Mantener solo los 5 bits de botones

    ; Comparar con estado anterior
    lds r17, last_button_state
    mov r18, r16
    eor r18, r17        ; r18 tendrá los bits que cambiaron
    and r16, r18        ; r16 tendrá solo los botones que se presionaron

    ; Verificar debounce timer
    lds r17, button_debounce_timer
    tst r17
    brne pcint1_end     ; Si el timer no es 0, ignorar

 
  
    ; Iniciar timer de debounce
    ldi r16, 10         ; 10 * 4ms = 40ms debounce
    sts button_debounce_timer, r16

pcint1_end:
    in r16, PINC
    com r16
    andi r16, 0x1F
    sts last_button_state, r16

    pop r18
    pop r17
    pop r16
    out SREG, r16
    pop r16
    reti
	


; Rutinas de interrupción de timers
TIMER0_COMP:
    push r16
    in r16, SREG
    push r16
    push r17
    push r18
    
    ; Decrementar timer de debounce si no es 0
    lds r16, button_debounce_timer
    tst r16
    breq skip_debounce
    dec r16
    sts button_debounce_timer, r16
skip_debounce:

    ; Manejar parpadeo en modo configuración
    lds r16, estado_actual
    cpi r16, STATE_SHOW_TIME
    breq no_blink
    cpi r16, STATE_SHOW_DATE
    breq no_blink
    cpi r16, STATE_SHOW_ALARM
    breq no_blink
    
    ; En modo configuración, toggle estado de parpadeo cada 250ms
    lds r16, digit_blink_state
    inc r16
    cpi r16, 63         ; ~250ms
    brne save_blink
    clr r16
save_blink:
    sts digit_blink_state, r16
    
no_blink:
    ; Multiplexación de displays
    call multiplex_displays
    
    ; Contador de multiplexación
    lds r16, timer0_count
    inc r16
    cpi r16, 250       ; 250 * 4ms = 1s
    brne save_timer0
    clr r16
    
save_timer0:
    sts timer0_count, r16
    
    pop r18
    pop r17
    pop r16
    out SREG, r16
    pop r16
    reti

TIMER1_COMP:
    push r16
    in r16, SREG
    push r16
    push r17
    
    ; Contador para LED (ahora más lento)
    lds r16, timer1_count
    inc r16
    cpi r16, 5        ; Aumentado a 5 para un parpadeo más lento
    brne save_timer1
    clr r16
    
    ; Toggle estado de LEDs con encendido/apagado más definido
    lds r17, led_state
    com r17
    sts led_state, r17
    
    ; Actualizar LEDs - Asegurar que se encienden/apagan completamente
    in r17, PORTB     ; Leer estado actual de PORTB
    andi r17, ~((1<<LED1_PIN)|(1<<LED2_PIN))  ; Limpiar bits de LED
    
    lds r16, led_state
    sbrc r16, 0
    ori r17, (1<<LED1_PIN)|(1<<LED2_PIN)    ; Encender ambos LEDs
    
    out PORTB, r17    ; Actualizar PORTB
    
save_timer1:
    sts timer1_count, r16
    
    ; Incrementar segundos
    lds r16, current_seconds
    inc r16
    cpi r16, 60
    brne save_seconds
    
    ; Si llegamos a 60 segundos, incrementar minutos
    clr r16
    sts current_seconds, r16
    
    lds r16, current_minutes
    inc r16
    cpi r16, 60
    brne save_minutes
    
    ; Si llegamos a 60 minutos, incrementar horas
    clr r16
    sts current_minutes, r16
    
    lds r16, current_hours
    inc r16
    cpi r16, 24
    brne save_hours
    
    ; Si llegamos a 24 horas, incrementar día
    clr r16
    sts current_hours, r16
    call increment_day
    jmp timer1_end
    
save_hours:
    sts current_hours, r16
    jmp timer1_end
    
save_minutes:
    sts current_minutes, r16
    jmp timer1_end
    
save_seconds:
    sts current_seconds, r16
    
timer1_end:
    call check_alarm_time
    
    pop r17
    pop r16
    out SREG, r16
    pop r16
    reti

TIMER2_COMP:
    push r16
    in r16, SREG
    push r16
    push r17
    
    lds r16, estado_actual
    cpi r16, STATE_ALARM_ON
    brne timer2_end
    
    ; Toggle buzzer pin para generar tono
    in r16, PINB
    ldi r17, (1<<BUZZER_PIN)
    eor r16, r17
    out PORTB, r16
    
timer2_end:
    pop r17
    pop r16
    out SREG, r16
    pop r16
    reti

	multiplex_displays:
    push r16
    push r17
    push r18
    push ZL
    push ZH
    
    ; Apagar todos los displays primero
    in r16, PORTB
    andi r16, ~((1<<DISPLAY2_PIN)|(1<<DISPLAY3_PIN)|(1<<DISPLAY4_PIN))
    out PORTB, r16
    cbi PORTD, DISPLAY1_PIN
    
    ; Obtener dígito actual
    lds r16, current_digit

    ; Verificar si estamos en modo configuración y si el dígito debe parpadear
    lds r18, estado_actual
    cpi r18, STATE_SET_HOUR
    brne check_minute_digit_label
    jmp check_hour_digit

check_minute_digit_label:
    cpi r18, STATE_SET_MINUTE
    brne check_day_digit_label
    jmp check_minute_digit

check_day_digit_label:
    cpi r18, STATE_SET_DAY
    brne check_month_digit_label
    jmp check_day_digit

check_month_digit_label:
    cpi r18, STATE_SET_MONTH
    brne check_alarm_hour_label
    jmp check_month_digit

check_alarm_hour_label:
    cpi r18, STATE_SET_ALARM_HOUR
    brne check_alarm_minute_label
    jmp check_alarm_hour

check_alarm_minute_label:
    cpi r18, STATE_SET_ALARM_MINUTE
    brne show_digit_label
    jmp check_alarm_minute

show_digit_label:
    jmp show_digit     ; No estamos en modo configuración

check_hour_digit:
    cpi r16, 2          ; ¿Es dígito de hora? (0 o 1)
    brge show_digit     ; Si es >= 2, mostrar normal
    jmp check_blink    ; Si es 0 o 1, parpadear

check_minute_digit:
    cpi r16, 2          ; ¿Es dígito de minuto? (2 o 3)
    brlt show_digit     ; Si es < 2, mostrar normal
    jmp check_blink    ; Si es 2 o 3, parpadear

check_day_digit:
    cpi r16, 2          ; ¿Es dígito de día? (0 o 1)
    brge show_digit     ; Si es >= 2, mostrar normal
    jmp check_blink    ; Si es 0 o 1, parpadear

check_month_digit:
    cpi r16, 2          ; ¿Es dígito de mes? (2 o 3)
    brlt show_digit     ; Si es < 2, mostrar normal
    jmp check_blink    ; Si es 2 o 3, parpadear

check_alarm_hour:
    cpi r16, 2          ; ¿Es dígito de hora de alarma? (0 o 1)
    brge show_digit     ; Si es >= 2, mostrar normal
    jmp check_blink    ; Si es 0 o 1, parpadear

check_alarm_minute:
    cpi r16, 2          ; ¿Es dígito de minuto de alarma? (2 o 3)
    brlt show_digit     ; Si es < 2, mostrar normal
    jmp check_blink    ; Si es 2 o 3, parpadear

check_blink:
    lds r18, digit_blink_state
    sbrc r18, 5         ; Parpadear cada ~250ms
    jmp skip_digit     ; Si el bit 5 está en 1, no mostrar dígito

show_digit:
    ; Cargar valor del dígito desde buffer
    ldi ZL, LOW(display_buffer)
    ldi ZH, HIGH(display_buffer)
    add ZL, r16
    ld r17, Z          ; r17 contiene el número a mostrar (0-9)
    
    ; Convertir a patrón de segmentos
    ldi ZL, LOW(2*digit_table)
    ldi ZH, HIGH(2*digit_table)
    add ZL, r17
    lpm r17, Z         ; r17 ahora contiene el patrón de segmentos
    
    ; Mostrar segmentos
    out PORTD, r17
    
    ; Seleccionar display actual
    cpi r16, 0
    brne try_display2
    sbi PORTD, DISPLAY1_PIN
    jmp next_digit
    
try_display2:
    cpi r16, 1
    brne try_display3
    sbi PORTB, DISPLAY2_PIN
    jmp next_digit
    
try_display3:
    cpi r16, 2
    brne try_display4
    sbi PORTB, DISPLAY3_PIN
    jmp next_digit
    
try_display4:
    sbi PORTB, DISPLAY4_PIN
    jmp next_digit

skip_digit:
    ; No mostrar nada en este ciclo
    clr r17
    out PORTD, r17
    
next_digit:
    ; Incrementar índice de dígito actual
    inc r16
    cpi r16, 4
    brne save_digit
    clr r16
    
save_digit:
    sts current_digit, r16
    
    pop ZH
    pop ZL
    pop r18
    pop r17
    pop r16
    ret
    
  

; Rutina de manejo de botones
read_buttons:
    push r16
    push r17
    
    in r16, PINC              ; Leer estado de botones
    com r16                   ; Invertir bits (pull-up)
    andi r16, 0x1F           ; Mantener solo los 5 bits de botones
    
    breq read_buttons_end     ; Si no hay botones presionados, salir
    
    sbrc r16, BTN_MODE
    call handle_mode_button
    
    sbrc r16, BTN_SELECT
    call handle_select_button
    
    sbrc r16, BTN_INCREMENT
    call handle_increment_button
    
    sbrc r16, BTN_DECREMENT
    call handle_decrement_button
    
    sbrc r16, BTN_ALARM_OFF
    call handle_alarm_off_button
    
read_buttons_end:
    pop r17
    pop r16
    ret

; Rutina de verificación de estado
check_state:
    push r16
    
    lds r16, estado_actual
    
    cpi r16, STATE_SHOW_TIME
    breq show_time_state
    cpi r16, STATE_SHOW_DATE
    breq show_date_state
    cpi r16, STATE_SHOW_ALARM
    breq show_alarm_state
    cpi r16, STATE_ALARM_ON
    breq alarm_on_state
    
    ; Estados de configuración
    cpi r16, STATE_SET_HOUR
    breq show_time_state
    cpi r16, STATE_SET_MINUTE
    breq show_time_state
    cpi r16, STATE_SET_DAY
    breq show_date_state
    cpi r16, STATE_SET_MONTH
    breq show_date_state
    cpi r16, STATE_SET_ALARM_HOUR
    breq show_alarm_state
    cpi r16, STATE_SET_ALARM_MINUTE
    breq show_alarm_state
    
    jmp check_state_end

show_time_state:
    call update_time_display
    jmp check_state_end
    
show_date_state:
    call update_date_display
    jmp check_state_end
    
show_alarm_state:
    call update_alarm_display
    jmp check_state_end
    
alarm_on_state:
    call update_time_display
    
check_state_end:
    pop r16
    ret

; Rutina de incremento de día
increment_day:
    push r16
    push r17
    push ZL
    push ZH
    
    lds r16, current_day
    inc r16
    
    ; Obtener máximo de días para el mes actual
    lds r17, current_month
    dec r17
    ldi ZL, LOW(2*days_in_month)
    ldi ZH, HIGH(2*days_in_month)
    add ZL, r17
    lpm r17, Z
    
    cp r16, r17
    brlo save_inc_day
    ldi r16, 1
    
save_inc_day:
    sts current_day, r16
    
    pop ZH
    pop ZL
    pop r17
    pop r16
    ret

; Rutina de verificación de alarma
check_alarm_time:
    push r16
    push r17
    
    lds r16, alarm_enabled
    cpi r16, 0
    breq check_alarm_end
    
    lds r16, current_hours
    lds r17, alarm_hours
    cp r16, r17
    brne check_alarm_end
    
    lds r16, current_minutes
    lds r17, alarm_minutes
    cp r16, r17
    brne check_alarm_end
    
    lds r16, current_seconds
    cpi r16, 0
    brne check_alarm_end
    
    ; Activar alarma
    ldi r16, STATE_ALARM_ON
    sts estado_actual, r16
    
check_alarm_end:
    pop r17
    pop r16
    ret

	; Rutinas de actualización de display
update_time_display:
    push r16
    push r17
    
    lds r16, current_hours
    call convert_to_bcd
    sts display_buffer, r17    ; Decenas de hora
    sts display_buffer+1, r16  ; Unidades de hora
    
    lds r16, current_minutes
    call convert_to_bcd
    sts display_buffer+2, r17  ; Decenas de minutos
    sts display_buffer+3, r16  ; Unidades de minutos
    
    pop r17
    pop r16
    ret

update_date_display:
    push r16
    push r17
    
    lds r16, current_day
    call convert_to_bcd
    sts display_buffer, r17    ; Decenas del día
    sts display_buffer+1, r16  ; Unidades del día
    
    lds r16, current_month
    call convert_to_bcd
    sts display_buffer+2, r17  ; Decenas del mes
    sts display_buffer+3, r16  ; Unidades del mes
    
    pop r17
    pop r16
    ret

update_alarm_display:
    push r16
    push r17
    
    lds r16, alarm_hours
    call convert_to_bcd
    sts display_buffer, r17    ; Decenas de hora alarma
    sts display_buffer+1, r16  ; Unidades de hora alarma
    
    lds r16, alarm_minutes
    call convert_to_bcd
    sts display_buffer+2, r17  ; Decenas de minutos alarma
    sts display_buffer+3, r16  ; Unidades de minutos alarma
    
    pop r17
    pop r16
    ret

; Rutinas de manejo de botones específicos
handle_mode_button:
    push r16
    
    lds r16, estado_actual
    
    cpi r16, STATE_SHOW_TIME
    brne mode_check_1
    ldi r16, STATE_SHOW_DATE
    jmp save_mode
mode_check_1:
    cpi r16, STATE_SHOW_DATE
    brne mode_check_2
    ldi r16, STATE_SHOW_ALARM
    jmp save_mode
mode_check_2:
    ldi r16, STATE_SHOW_TIME
save_mode:
    sts estado_actual, r16
    call debounce_delay
    
    pop r16
    ret

handle_select_button:
    push r16
    
    lds r16, estado_actual
    
    cpi r16, STATE_SHOW_TIME
    brne select_check_1
    ldi r16, STATE_SET_HOUR
    jmp save_select
select_check_1:
    cpi r16, STATE_SET_HOUR
    brne select_check_2
    ldi r16, STATE_SET_MINUTE
    jmp save_select
select_check_2:
    cpi r16, STATE_SET_MINUTE
    brne select_check_3
    ldi r16, STATE_SHOW_TIME
    jmp save_select
select_check_3:
    cpi r16, STATE_SHOW_DATE
    brne select_check_4
    ldi r16, STATE_SET_DAY
    jmp save_select
select_check_4:
    cpi r16, STATE_SET_DAY
    brne select_check_5
    ldi r16, STATE_SET_MONTH
    jmp save_select
select_check_5:
    cpi r16, STATE_SET_MONTH
    brne select_check_6
    ldi r16, STATE_SHOW_DATE
    jmp save_select
select_check_6:
    cpi r16, STATE_SHOW_ALARM
    brne select_check_7
    ldi r16, STATE_SET_ALARM_HOUR
    jmp save_select
select_check_7:
    cpi r16, STATE_SET_ALARM_HOUR
    brne select_check_8
    ldi r16, STATE_SET_ALARM_MINUTE
    jmp save_select
select_check_8:
    ldi r16, STATE_SHOW_ALARM
save_select:
    sts estado_actual, r16
    call debounce_delay
    
    pop r16
    ret

handle_increment_button:
    push r16
    
    lds r16, estado_actual
    
    cpi r16, STATE_SET_HOUR
    brne inc_check_1
    call increment_hour
    jmp inc_end
inc_check_1:
    cpi r16, STATE_SET_MINUTE
    brne inc_check_2
    call increment_minute
    jmp inc_end
inc_check_2:
    cpi r16, STATE_SET_DAY
    brne inc_check_3
    call increment_day
    jmp inc_end
inc_check_3:
    cpi r16, STATE_SET_MONTH
    brne inc_check_4
    call increment_month
    jmp inc_end
inc_check_4:
    cpi r16, STATE_SET_ALARM_HOUR
    brne inc_check_5
    call increment_alarm_hour
    jmp inc_end
inc_check_5:
    cpi r16, STATE_SET_ALARM_MINUTE
    brne inc_end
    call increment_alarm_minute
inc_end:
    call debounce_delay
    pop r16
    ret

handle_decrement_button:
    push r16
    
    lds r16, estado_actual
    
    cpi r16, STATE_SET_HOUR
    brne dec_check_1
    call decrement_hour
    jmp dec_end
dec_check_1:
    cpi r16, STATE_SET_MINUTE
    brne dec_check_2
    call decrement_minute
    jmp dec_end
dec_check_2:
    cpi r16, STATE_SET_DAY
    brne dec_check_3
    call decrement_day
    jmp dec_end
dec_check_3:
    cpi r16, STATE_SET_MONTH
    brne dec_check_4
    call decrement_month
    jmp dec_end
dec_check_4:
    cpi r16, STATE_SET_ALARM_HOUR
    brne dec_check_5
    call decrement_alarm_hour
    jmp dec_end
dec_check_5:
    cpi r16, STATE_SET_ALARM_MINUTE
    brne dec_end
    call decrement_alarm_minute
dec_end:
    call debounce_delay
    pop r16
    ret

handle_alarm_off_button:
    push r16
    
    lds r16, estado_actual
    cpi r16, STATE_ALARM_ON
    brne toggle_alarm
    
    ; Apagar alarma activa
    ldi r16, STATE_SHOW_TIME
    sts estado_actual, r16
    clr r16
    sts buzzer_pattern, r16
    cbi PORTB, BUZZER_PIN
    jmp alarm_off_end
    
toggle_alarm:
    ; Toggle estado de alarma
    lds r16, alarm_enabled
    com r16
    sts alarm_enabled, r16
    
alarm_off_end:
    call debounce_delay
    pop r16
    ret

; Rutina de retardo para debounce
debounce_delay:
    push r16
    push r17
    push r18
    
    ldi r16, 50      ; Ajustar según necesidad
delay_loop1:
    ldi r17, 255
delay_loop2:
    ldi r18, 255
delay_loop3:
    dec r18
    brne delay_loop3
    dec r17
    brne delay_loop2
    dec r16
    brne delay_loop1
    
    pop r18
    pop r17
    pop r16
    ret

; Conversión BCD
convert_to_bcd:
    push r18
    clr r17                    ; Contador de decenas
    
bcd_loop:
    cpi r16, 10
    brlo bcd_end              ; Si es menor que 10, terminamos
    inc r17                   ; Incrementar decenas
    subi r16, 10             ; Restar 10
    jmp bcd_loop
    
bcd_end:
    pop r18
    ret

	; Rutinas de incremento/decremento de hora y minutos
increment_hour:
    push r16
    
    lds r16, current_hours
    inc r16
    cpi r16, 24
    brne save_inc_hour
    clr r16
save_inc_hour:
    sts current_hours, r16
    call update_time_display
    
    pop r16
    ret

decrement_hour:
    push r16
    
    lds r16, current_hours
    dec r16
    cpi r16, 0xFF
    brne save_dec_hour
    ldi r16, 23
save_dec_hour:
    sts current_hours, r16
    call update_time_display
    
    pop r16
    ret

increment_minute:
    push r16
    
    lds r16, current_minutes
    inc r16
    cpi r16, 60
    brne save_inc_minute
    clr r16
save_inc_minute:
    sts current_minutes, r16
    call update_time_display
    
    pop r16
    ret

decrement_minute:
    push r16
    
    lds r16, current_minutes
    dec r16
    cpi r16, 0xFF
    brne save_dec_minute
    ldi r16, 59
save_dec_minute:
    sts current_minutes, r16
    call update_time_display
    
    pop r16
    ret

; Rutinas de incremento/decremento de mes
increment_month:
    push r16
    
    lds r16, current_month
    inc r16
    cpi r16, 13
    brne save_inc_month
    ldi r16, 1
save_inc_month:
    sts current_month, r16
    call validate_day
    call update_date_display
    
    pop r16
    ret

decrement_month:
    push r16
    
    lds r16, current_month
    dec r16
    cpi r16, 0
    brne save_dec_month
    ldi r16, 12
save_dec_month:
    sts current_month, r16
    call validate_day
    call update_date_display
    
    pop r16
    ret

; Rutinas de decremento de día
decrement_day:
    push r16
    push r17
    push ZL
    push ZH
    
    lds r16, current_day
    dec r16
    cpi r16, 0
    brne save_dec_day
    
    ; Cargar último día del mes
    lds r17, current_month
    dec r17
    ldi ZL, LOW(2*days_in_month)
    ldi ZH, HIGH(2*days_in_month)
    add ZL, r17
    lpm r16, Z
    
save_dec_day:
    sts current_day, r16
    call update_date_display
    
    pop ZH
    pop ZL
    pop r17
    pop r16
    ret

; Rutinas de incremento/decremento de alarma
increment_alarm_hour:
    push r16
    
    lds r16, alarm_hours
    inc r16
    cpi r16, 24
    brne save_inc_alarm_h
    clr r16
save_inc_alarm_h:
    sts alarm_hours, r16
    call update_alarm_display
    
    pop r16
    ret

decrement_alarm_hour:
    push r16
    
    lds r16, alarm_hours
    dec r16
    cpi r16, 0xFF
    brne save_dec_alarm_h
    ldi r16, 23
save_dec_alarm_h:
    sts alarm_hours, r16
    call update_alarm_display
    
    pop r16
    ret

increment_alarm_minute:
    push r16
    
    lds r16, alarm_minutes
    inc r16
    cpi r16, 60
    brne save_inc_alarm_m
    clr r16
save_inc_alarm_m:
    sts alarm_minutes, r16
    call update_alarm_display
    
    pop r16
    ret

decrement_alarm_minute:
    push r16
    
    lds r16, alarm_minutes
    dec r16
    cpi r16, 0xFF
    brne save_dec_alarm_m
    ldi r16, 59
save_dec_alarm_m:
    sts alarm_minutes, r16
    call update_alarm_display
    
    pop r16
    ret

; Rutina de validación de día al cambiar mes
validate_day:
    push r16
    push r17
    push ZL
    push ZH
    
    ; Verificar que el día actual es válido para el nuevo mes
    lds r16, current_day
    lds r17, current_month
    dec r17
    
    ldi ZL, LOW(2*days_in_month)
    ldi ZH, HIGH(2*days_in_month)
    add ZL, r17
    lpm r17, Z
    
    cp r16, r17
    brlo validate_day_end
    sts current_day, r17
    
validate_day_end:
    pop ZH
    pop ZL
    pop r17
    pop r16
    ret
