@ ============================================================================
@ demo_arm.s - PROGRAMA EM ASSEMBLY DO ARM (HPS, Linux) que usa o coprocessador
@
@ Papel de cada um (busca ASSINCRONA: FIFO entre o ARM e a unidade de controle):
@   - o ARM le o codigo de maquina da NOSSA ISA (tabelas em programa_isa.s,
@     geradas pelo montador a partir de demo.asm) e ENVIA cada palavra para o
@     coprocessador pelos PIOs, seguindo o handshake valid/ack;
@   - o ARM decide QUANDO enviar cada bloco (a ISA nao tem desvios): bater na
@     borda, contar quadros, voltar o scroll...;
@   - quem DESENHA e faz as contas (x = x + passo, scroll + 1, mover vertices)
@     e o coprocessador, executando as instrucoes recebidas.
@
@ Assembly puro, sem a biblioteca do C. O acesso ao hardware (abrir a ponte,
@ handshake, reset, status) e feito pelo DRIVER (driver_copro.s); este arquivo
@ so contem a logica da demonstracao.
@
@ Compilar na placa (os 3 arquivos .s na mesma pasta):
@     as -o demo_arm.o demo_arm.s
@     as -o programa_isa.o programa_isa.s
@     as -o driver_copro.o driver_copro.s
@     ld -o demo_arm demo_arm.o programa_isa.o driver_copro.o
@ Rodar:
@     sudo ./demo_arm           anima 600 quadros (~10 s)
@     sudo ./demo_arm 0         anima ate apertar Ctrl+C
@     sudo ./demo_arm 1200      anima 1200 quadros
@     sudo ./demo_arm reset     so reinicia o coprocessador
@
@ Convencao das sub-rotinas (a mesma do driver e do gcc): argumentos em r0-r3,
@ retorno em r0; cada rotina preserva r4-r11 (empilha o que usar). O numero da
@ chamada de sistema vai em r7, por isso toda rotina que faz svc salva r7.
@ ============================================================================
        .syntax unified
        .arch   armv7-a
        .arm

@ ---------------- bit do pio_status usado aqui (os outros ficam no driver) ----------------
        .equ ST_ERR,         0x40      @ bit6: chegou opcode invalido

@ ---------------- Linux (ARM EABI) ----------------
        .equ SYS_WRITE,      4
        .equ SYS_EXIT_GROUP, 248
        .equ STDOUT,         1

@ ---------------- parametros da animacao ----------------
@ (X_INICIAL e PASSO_X tem que ser os mesmos do demo.asm)
@ Podem ser trocados livremente: o codigo carrega cada um com "ldr rX, =VALOR",
@ que aceita qualquer numero (um "cmp r9, #278" nao montaria, porque o ARM so
@ aceita como imediato numeros de 8 bits rotacionados).
        .equ X_INICIAL,      40
        .equ PASSO_X,        2
        .equ X_MAX,          280       @ sprite 0 vira para a esquerda aqui
        .equ X_MIN,          20        @ ... e para a direita aqui
        .equ RY_MAX,         40        @ retangulo desce ate 40 px e volta
        .equ SCROLL_CADA,    3         @ scroll anda 1 px a cada 3 quadros
        .equ SCROLL_LARGURA, 320       @ scroll volta a 0 ao chegar em 320
        .equ SPR1_CADA,      120       @ sprite 1 volta ao canto a cada 120 quadros
        .equ LUZES_CADA,     30        @ janelas piscam a cada 30 quadros (4 x 30 = SPR1_CADA)
        .equ QUADROS_PADRAO, 600

@ Envia um bloco do programa da ISA (rotulos gerados pelo montador) pelo driver
        .macro ENVIA_BLOCO nome
        ldr     r0, =isa_\nome
        ldr     r1, =isa_\nome\()_fim
        bl      copro_envia_bloco
        cmp     r0, #0
        bne     falha_envio            @ coprocessador nao respondeu
        .endm

@ ============================================================================
        .data
@ ============================================================================
        .align 2
buf_hex:        .asciz "0x00000000"
txt_reset:      .asciz "reset"
msg_sudo:       .asciz "ERRO: nao abriu /dev/mem (rode com sudo)\n"
msg_mmap:       .asciz "ERRO: mmap\n"
msg_reiniciado: .asciz "Coprocessador reiniciado.\n"
msg_status1:    .asciz "Status apos reset: "
msg_status2:    .asciz " (esperado 0x0000000A ou 0x0000002A)\n"
msg_cena:       .asciz "Cena montada. Animando...\n"
msg_cena_inf:   .asciz "Cena montada. Animando (Ctrl+C para parar)...\n"
msg_tempo:      .asciz "ERRO: tempo esgotado (status="
msg_fecha:      .asciz ")\n"
msg_fim:        .asciz "Fim. Status: "
msg_err_op:     .asciz "  (ERRO: opcode invalido recebido)"
msg_nl:         .asciz "\n"

@ ============================================================================
        .text
@ ============================================================================
        .global _start
_start:
        ldr     r0, [sp]               @ argc
        add     r1, sp, #4             @ argv
        bl      main
        mov     r7, #SYS_EXIT_GROUP    @ termina com o codigo devolvido em r0
        svc     #0

@ ----------------------------------------------------------------------------
@ main(r0 = argc, r1 = argv) -> r0 = codigo de saida
@
@ Registradores do laco de animacao (copias, no ARM, do que o coprocessador faz):
@   r4  = passo do retangulo (+1 desce, -1 sobe)   r8  = contador de quadros 0..119 (sprite 1 e luzes)
@   r5  = scroll_x atual                           r9  = x do sprite 0
@   r6  = contador para o scroll (0..2)            r10 = passo do sprite 0 (+2 / -2)
@   r7  = quadros que faltam (-1 = infinito)       r11 = deslocamento do retangulo (0..40)
@ ----------------------------------------------------------------------------
main:
        push    {r4-r11, lr}
        sub     sp, sp, #4             @ mantem a pilha alinhada em 8 bytes
        mov     r4, r0                 @ argc
        mov     r5, r1                 @ argv

        @ ---- driver: abre /dev/mem e mapeia a ponte lightweight (0xFF200000) ----
        bl      copro_abre
        cmp     r0, #0
        beq     1f
        cmn     r0, #1                 @ -1: nao abriu /dev/mem
        ldreq   r0, =msg_sudo
        ldrne   r0, =msg_mmap          @ -2: mmap falhou
        bl      escreve
        mov     r0, #1
        b       sai
1:
        bl      copro_reinicia         @ driver: pulso de reset (e espera restaurar o fundo)

        @ ---- argumentos: "reset" ou numero de quadros ----
        ldr     r7, =QUADROS_PADRAO
        cmp     r4, #2
        blt     args_ok
        ldr     r0, [r5, #4]           @ argv[1]
        ldr     r1, =txt_reset
        bl      compara_texto
        cmp     r0, #0
        bne     args_numero
        ldr     r0, =msg_reiniciado
        bl      escreve
        b       encerra
args_numero:
        ldr     r0, [r5, #4]
        bl      converte_numero
        movs    r7, r0
        mvneq   r7, #0                 @ 0 -> -1 (infinito)
args_ok:

        @ ---- status logo apos o reset ----
        ldr     r0, =msg_status1
        bl      escreve
        bl      copro_status
        bl      escreve_hex
        ldr     r0, =msg_status2
        bl      escreve

        @ ---- envia a cena inicial e espera o coprocessador terminar ----
        ENVIA_BLOCO cena
        bl      copro_espera_fim       @ driver: espera executar tudo
        cmp     r7, #0
        ldrge   r0, =msg_cena
        ldrlt   r0, =msg_cena_inf
        bl      escreve

        @ ---- estado inicial das copias no ARM ----
        mov     r4, #1                 @ retangulo comeca descendo
        mov     r5, #0                 @ scroll_x
        mov     r6, #0
        mov     r8, #0
        ldr     r9, =X_INICIAL
        ldr     r10, =PASSO_X
        mov     r11, #0

@ ============ laco de animacao: um conjunto de blocos por quadro ============
laco:
        cmp     r7, #0
        beq     fim_laco

        @ -- sprite 0 bateu na direita? (x >= X_MAX e indo para a direita)
        ldr     r12, =X_MAX
        cmp     r9, r12
        blt     1f
        cmp     r10, #0
        ble     1f
        ldr     r10, =-PASSO_X
        ENVIA_BLOCO vira_esquerda
1:      @ -- sprite 0 bateu na esquerda? (x <= X_MIN e indo para a esquerda)
        ldr     r12, =X_MIN
        cmp     r9, r12
        bgt     2f
        cmp     r10, #0
        bge     2f
        ldr     r10, =PASSO_X
        ENVIA_BLOCO vira_direita
2:      @ -- retangulo chegou embaixo? (desceu RY_MAX)
        ldr     r12, =RY_MAX
        cmp     r11, r12
        blt     3f
        cmp     r4, #0
        ble     3f
        mov     r4, #-1
        ENVIA_BLOCO ret_sobe
3:      @ -- retangulo voltou ao topo?
        cmp     r11, #0
        bgt     4f
        cmp     r4, #0
        bge     4f
        mov     r4, #1
        ENVIA_BLOCO ret_desce
4:      add     r9, r9, r10            @ acompanha o que o coprocessador vai calcular
        add     r11, r11, r4

        @ -- bloco do quadro: WAITV + atualizacoes (calculadas pela ULA do coprocessador)
        ENVIA_BLOCO quadro

        @ -- scroll a cada SCROLL_CADA quadros
        add     r6, r6, #1
        ldr     r12, =SCROLL_CADA
        cmp     r6, r12
        blt     6f
        mov     r6, #0
        add     r5, r5, #1
        ldr     r12, =SCROLL_LARGURA
        cmp     r5, r12
        blt     5f
        mov     r5, #0
        ENVIA_BLOCO scroll_volta       @ chegou em 320: volta para 0
        b       6f
5:      ENVIA_BLOCO scroll             @ coprocessador faz scroll_x + 1
6:
        @ -- sprite 1 volta ao canto a cada SPR1_CADA quadros
        add     r8, r8, #1
        @ -- luzes do predio cinza: dentro de cada ciclo de 120 quadros (r8),
        @    apagam nos quadros 30 e 90 e acendem nos quadros 60 e 120
        cmp     r8, #LUZES_CADA
        cmpne   r8, #(3 * LUZES_CADA)          @ "cmpne": so compara se o anterior deu diferente
        bne     8f
        ENVIA_BLOCO luzes_apagam
        b       9f
8:      cmp     r8, #(2 * LUZES_CADA)
        cmpne   r8, #(4 * LUZES_CADA)
        bne     9f
        ENVIA_BLOCO luzes_acendem
9:
        ldr     r12, =SPR1_CADA
        cmp     r8, r12
        blt     7f
        mov     r8, #0
        ENVIA_BLOCO spr1_volta
7:
        cmp     r7, #0
        subgt   r7, r7, #1             @ se for infinito (-1), nao conta
        b       laco

fim_laco:
        bl      copro_espera_fim       @ espera o coprocessador esvaziar a fila
        ldr     r0, =msg_fim
        bl      escreve
        bl      copro_status
        mov     r4, r0
        bl      escreve_hex
        tst     r4, #ST_ERR
        ldrne   r0, =msg_err_op
        blne    escreve
        ldr     r0, =msg_nl
        bl      escreve

encerra:
        bl      copro_fecha
        mov     r0, #0
sai:
        add     sp, sp, #4
        pop     {r4-r11, pc}

@ ----------------------------------------------------------------------------
@ falha_envio: o driver nao conseguiu entregar uma instrucao (o coprocessador
@ nao respondeu). Mostra o status, fecha a ponte e encerra com codigo 1.
@ ----------------------------------------------------------------------------
falha_envio:
        ldr     r0, =msg_tempo
        bl      escreve
        bl      copro_status
        bl      escreve_hex
        ldr     r0, =msg_fecha
        bl      escreve
        bl      copro_fecha
        mov     r0, #1
        mov     r7, #SYS_EXIT_GROUP
        svc     #0

@ ----------------------------------------------------------------------------
@ Rotinas de texto (o que o printf/atoi/strcmp fariam em C)
@ ----------------------------------------------------------------------------
@ escreve(r0 = texto terminado em 0)
escreve:
        push    {r7, lr}
        mov     r1, r0
        mov     r2, #0                 @ conta os caracteres
1:      ldrb    r3, [r1, r2]
        cmp     r3, #0
        addne   r2, r2, #1
        bne     1b
        mov     r0, #STDOUT
        mov     r7, #SYS_WRITE         @ write(1, texto, tamanho)
        svc     #0
        pop     {r7, pc}

@ escreve_hex(r0 = valor): imprime "0x" e 8 digitos hexadecimais
escreve_hex:
        push    {r4, lr}
        ldr     r1, =buf_hex
        add     r2, r1, #9             @ ultimo digito
        mov     r3, #8
1:      and     r12, r0, #0xF
        cmp     r12, #10
        addlt   r12, r12, #'0'
        addge   r12, r12, #('A' - 10)
        strb    r12, [r2], #-1
        lsr     r0, r0, #4
        subs    r3, r3, #1
        bne     1b
        mov     r0, r1
        bl      escreve
        pop     {r4, pc}

@ converte_numero(r0 = texto) -> r0 = valor decimal (para no 1o caractere nao-digito)
converte_numero:
        mov     r1, r0
        mov     r0, #0
        mov     r3, #10
1:      ldrb    r2, [r1], #1
        sub     r2, r2, #'0'
        cmp     r2, #9
        bxhi    lr                     @ nao e digito (ou fim do texto)
        mla     r0, r0, r3, r2         @ valor = valor * 10 + digito
        b       1b

@ compara_texto(r0, r1) -> r0 = 0 se os textos forem iguais
compara_texto:
1:      ldrb    r2, [r0], #1
        ldrb    r3, [r1], #1
        cmp     r2, r3
        movne   r0, #1
        bxne    lr
        cmp     r2, #0
        bne     1b
        mov     r0, #0
        bx      lr

        .ltorg                         @ constantes usadas pelos "ldr rX, =..."

        .section .note.GNU-stack, "", %progbits   @ pilha nao executavel (evita aviso do linker)
