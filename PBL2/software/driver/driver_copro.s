@ ============================================================================
@ driver_copro.s - DRIVER do coprocessador grafico (biblioteca em Assembly ARM)
@
@ Biblioteca: NAO tem main. Contem as funcoes que os programas (em C ou em
@ Assembly) chamam para usar o coprocessador. Os prototipos para C estao em
@ copro.h. E o UNICO codigo do projeto que acessa os PIOs.
@
@   Baixo nivel (falam com o hardware)
@     copro_abre, copro_fecha, copro_reinicia, copro_status,
@     copro_envia, copro_envia_bloco, copro_espera_fim
@   Alto nivel (montam a instrucao da NOSSA ISA e chamam copro_envia)
@     copro_li, copro_tile, copro_scroll, copro_vertice, copro_poligono,
@     copro_move_poligono, copro_sprite_pos, copro_sprite_attr,
@     copro_move_sprite, copro_espera_quadro
@
@ Uso:
@   em C:        gcc -o menu menu.c driver_copro.s
@   em Assembly: as -o driver_copro.o driver_copro.s  (e ligar com ld junto do programa)
@
@ Regras (ARM EABI, as mesmas do gcc): argumentos em r0-r3, retorno em r0,
@ r4-r11 preservados. O driver fala com o Linux por chamadas de sistema
@ (svc #0) e NAO usa a biblioteca do C, entao serve tambem para programas
@ 100% Assembly.
@
@ Codigo independente de posicao: as variaveis sao achadas pelo endereco
@ RELATIVO ao PC (macro END_VAR), entao funciona mesmo quando o gcc gera
@ executavel PIE (que pode ser carregado em qualquer endereco).
@
@ As funcoes de alto nivel que recebem coordenadas usam os registradores r1 e
@ r2 DO COPROCESSADOR como temporarios (LI r1, x / LI r2, y / instrucao).
@ ============================================================================
        .syntax unified
        .arch   armv7-a
        .arm

@ ---------------- mapa MMIO (Platform Designer) ----------------
        .equ LW_BASE_PAGINA, 0xFF200   @ 0xFF200000 / 4096 (o mmap2 recebe em paginas)
        .equ LW_SPAN,        0x5000
        .equ OFS_INSTR,      0x00
        .equ OFS_CTRL,       0x10
        .equ OFS_STATUS,     0x20

        .equ CTRL_VALID,     1
        .equ CTRL_RESET,     2
        .equ ST_BUSY,        0x01
        .equ ST_DONE,        0x02
        .equ ST_FULL,        0x04
        .equ ST_ACK,         0x10

        .equ SYS_OPEN,       5
        .equ SYS_CLOSE,      6
        .equ SYS_MUNMAP,     91
        .equ SYS_NANOSLEEP,  162
        .equ SYS_MMAP2,      192
        .equ O_RDWR_O_SYNC,  0x101002
        .equ PROT_RW,        3
        .equ MAP_SHARED,     1

        .equ LIMITE_ESPERA,  20000000  @ leituras do status antes de desistir (~3 s na placa;
                                       @ precisa passar de 1 quadro: o WAITV segura a fila)
        .equ HIST_MAX,       64        @ tamanho do historico de instrucoes

@ ---------------- palavras-base das instrucoes (formato da ISA) ----------------
@ formato: op[31:27] A[26:22] B[21:17] C[16:12] baixos[11:0]
        .equ OP_LI,          0x08000000    @ LI rd, imm16
        .equ OP_WAITV,       0x38000000    @ WAITV
        .equ OP_SET_TILE,    0x40000000    @ SET_TILE lin, col, tile
        .equ OP_SET_SCROLL,  0x48022000    @ SET_SCROLL r1, r2
        .equ OP_POLY_VTX,    0x80022000    @ POLY_VTX slot, v, r1, r2
        .equ OP_POLY_CFG,    0x88000000    @ POLY_CFG slot, tipo, cor
        .equ OP_POLY_MOVE,   0x90022000    @ POLY_MOVE slot, r1, r2
        .equ OP_SPR_POS,     0xC0022000    @ SPR_POS n, r1, r2
        .equ OP_SPR_ATTR,    0xC8000000    @ SPR_ATTR n, tile, flags
        .equ OP_SPR_MOVE,    0xD0022000    @ SPR_MOVE n, r1, r2

@ END_VAR reg, simbolo : reg <- endereco de "simbolo", calculado a partir do PC
        .macro END_VAR reg, simbolo
        ldr     \reg, .Lofs\@
.Lpc\@: add     \reg, pc, \reg              @ no ARM, o PC lido aqui vale (.Lpc + 8)
        b       .Lfim\@
.Lofs\@:
        .word   \simbolo - (.Lpc\@ + 8)
.Lfim\@:
        .endm

@ ============================================================================
        .data
@ ============================================================================
        .align 2
lw_base:        .word 0                @ endereco virtual da ponte (0 = fechado)
fd_mem:         .word -1
        .global copro_hist, copro_hist_n
copro_hist_n:   .word 0                @ quantas palavras estao no historico
copro_hist:     .space 4 * HIST_MAX    @ ultimas palavras enviadas (o C le e mostra)

@ ============================================================================
        .text
@ ============================================================================
caminho_mem:
        .asciz  "/dev/mem"
        .align 2
tempo_1ms:      .word 0, 1000000       @ struct timespec {0 s, 1.000.000 ns}

@ ----------------------------------------------------------------------------
@ int copro_abre(void)
@   abre /dev/mem e mapeia a ponte lightweight (0xFF200000, 0x5000 bytes)
@   retorna 0 = ok, -1 = nao abriu /dev/mem (faltou sudo), -2 = mmap falhou
@ ----------------------------------------------------------------------------
        .global copro_abre
        .type   copro_abre, %function
copro_abre:
        push    {r4, r5, r7, lr}
        adr     r0, caminho_mem
        ldr     r1, =O_RDWR_O_SYNC
        mov     r2, #0
        mov     r7, #SYS_OPEN
        svc     #0                     @ fd = open("/dev/mem", O_RDWR | O_SYNC)
        cmp     r0, #0
        mvnlt   r0, #0                 @ -1
        poplt   {r4, r5, r7, pc}
        END_VAR r1, fd_mem
        str     r0, [r1]
        mov     r4, r0                 @ 5o argumento: fd
        ldr     r5, =LW_BASE_PAGINA    @ 6o argumento: deslocamento em paginas
        mov     r0, #0
        ldr     r1, =LW_SPAN
        mov     r2, #PROT_RW
        mov     r3, #MAP_SHARED
        mov     r7, #SYS_MMAP2
        svc     #0                     @ lw_base = mmap2(0, SPAN, RW, SHARED, fd, pagina)
        cmn     r0, #4096              @ -4095..-1 = erro
        mvnhi   r0, #1                 @ -2
        pophi   {r4, r5, r7, pc}
        END_VAR r1, lw_base
        str     r0, [r1]
        mov     r0, #0
        pop     {r4, r5, r7, pc}

@ void copro_fecha(void): desfaz o mapeamento e fecha /dev/mem
        .global copro_fecha
        .type   copro_fecha, %function
copro_fecha:
        push    {r4, r7}
        END_VAR r4, lw_base
        ldr     r0, [r4]
        cmp     r0, #0
        beq     1f
        ldr     r1, =LW_SPAN
        mov     r7, #SYS_MUNMAP
        svc     #0
        mov     r0, #0
        str     r0, [r4]
        END_VAR r4, fd_mem
        ldr     r0, [r4]
        mov     r7, #SYS_CLOSE
        svc     #0
1:      pop     {r4, r7}
        bx      lr

@ uint32_t copro_status(void): le o pio_status
        .global copro_status
        .type   copro_status, %function
copro_status:
        END_VAR r0, lw_base
        ldr     r0, [r0]
        ldr     r0, [r0, #OFS_STATUS]
        bx      lr

@ ----------------------------------------------------------------------------
@ espera (interna): r0 = mascara, r1 = valor
@   le o status ate (status & mascara) == valor. Retorna 0, ou -1 se demorar demais.
@ ----------------------------------------------------------------------------
espera:
        END_VAR r2, lw_base
        ldr     r2, [r2]
        ldr     r3, =LIMITE_ESPERA
1:      ldr     r12, [r2, #OFS_STATUS]
        and     r12, r12, r0
        cmp     r12, r1
        moveq   r0, #0
        bxeq    lr
        subs    r3, r3, #1
        bne     1b
        mvn     r0, #0
        bx      lr

@ int copro_espera_fim(void): espera o coprocessador terminar tudo (bit done)
        .global copro_espera_fim
        .type   copro_espera_fim, %function
copro_espera_fim:
        mov     r0, #ST_DONE
        mov     r1, #ST_DONE
        b       espera                 @ (o retorno da espera volta direto para quem chamou)

@ ----------------------------------------------------------------------------
@ void copro_reinicia(void)
@   pulso de reset (bit 1 do pio_ctrl) por ~1 ms e espera o fim da restauracao
@   do fundo (bit busy volta a 0)
@ ----------------------------------------------------------------------------
        .global copro_reinicia
        .type   copro_reinicia, %function
copro_reinicia:
        push    {r4, r7}
        END_VAR r4, lw_base
        ldr     r4, [r4]
        mov     r0, #CTRL_RESET
        str     r0, [r4, #OFS_CTRL]
        adr     r0, tempo_1ms
        mov     r1, #0
        mov     r7, #SYS_NANOSLEEP
        svc     #0
        mov     r0, #0
        str     r0, [r4, #OFS_CTRL]
        adr     r0, tempo_1ms
        mov     r1, #0
        mov     r7, #SYS_NANOSLEEP
        svc     #0
        pop     {r4, r7}
        mov     r0, #ST_BUSY
        mov     r1, #0
        b       espera

@ ----------------------------------------------------------------------------
@ int copro_envia(uint32_t instr)
@   entrega UMA instrucao (handshake de 4 fases):
@     1. espera fila nao cheia e ack = 0
@     2. palavra no pio_instr, valid = 1
@     3. espera ack = 1 (a unidade de busca guardou a palavra na fila)
@     4. valid = 0 e espera ack = 0
@   retorna 0 = ok, -1 = o coprocessador nao respondeu
@ ----------------------------------------------------------------------------
        .global copro_envia
        .type   copro_envia, %function
copro_envia:
        push    {r4, r5, r6, lr}
        mov     r4, r0
        END_VAR r5, lw_base
        ldr     r5, [r5]

        mov     r0, #(ST_FULL | ST_ACK)        @ 1. fila nao cheia E ack = 0
        mov     r1, #0
        bl      espera
        cmp     r0, #0
        bne     2f

        str     r4, [r5, #OFS_INSTR]           @ 2. palavra no pio_instr
        dmb                                    @    chega ANTES do valid
        mov     r1, #CTRL_VALID
        str     r1, [r5, #OFS_CTRL]            @    valid = 1

        mov     r0, #ST_ACK                    @ 3. espera ack = 1
        mov     r1, #ST_ACK
        bl      espera
        mov     r6, r0
        mov     r1, #0
        str     r1, [r5, #OFS_CTRL]            @ 4. valid = 0 (mesmo se deu erro)
        cmp     r6, #0
        bne     2f
        mov     r0, #ST_ACK
        mov     r1, #0
        bl      espera
        cmp     r0, #0
        bne     2f

        END_VAR r1, copro_hist_n               @ guarda no historico
        ldr     r2, [r1]
        cmp     r2, #HIST_MAX
        bhs     1f
        add     r3, r1, #4                     @ copro_hist vem logo depois de copro_hist_n
        str     r4, [r3, r2, lsl #2]           @ copro_hist[n] = palavra
        add     r2, r2, #1
        str     r2, [r1]
1:      mov     r0, #0
2:      pop     {r4, r5, r6, pc}

@ ----------------------------------------------------------------------------
@ int copro_envia_bloco(const uint32_t *inicio, const uint32_t *fim)
@   envia todas as palavras de [inicio, fim). Retorna 0 ou -1.
@ ----------------------------------------------------------------------------
        .global copro_envia_bloco
        .type   copro_envia_bloco, %function
copro_envia_bloco:
        push    {r4, r5, r6, lr}
        mov     r4, r0
        mov     r5, r1
1:      cmp     r4, r5
        movhs   r0, #0
        bhs     2f
        ldr     r0, [r4], #4
        bl      copro_envia
        cmp     r0, #0
        beq     1b
2:      pop     {r4, r5, r6, pc}

@ ============================================================================
@ ALTO NIVEL: cada funcao monta a palavra da nossa ISA e envia
@ ============================================================================

@ int copro_li(int rd, int valor)            ->  LI rd, valor
        .global copro_li
        .type   copro_li, %function
copro_li:
        and     r0, r0, #31
        lsl     r0, r0, #22                    @ rd no campo A [26:22]
        orr     r0, r0, #OP_LI
        uxth    r1, r1                         @ 16 bits de baixo (negativo vira complemento de 2)
        orr     r0, r0, r1
        b       copro_envia

@ int copro_espera_quadro(void)              ->  WAITV
        .global copro_espera_quadro
        .type   copro_espera_quadro, %function
copro_espera_quadro:
        mov     r0, #OP_WAITV
        b       copro_envia

@ int copro_tile(int lin, int col, int tile)  ->  SET_TILE lin, col, tile
        .global copro_tile
        .type   copro_tile, %function
copro_tile:
        and     r0, r0, #31
        and     r1, r1, #63
        and     r2, r2, #255
        lsl     r0, r0, #22                    @ linha no campo A [26:22]
        orr     r0, r0, r1, lsl #16            @ coluna em [21:16]
        orr     r0, r0, r2                     @ tile em [7:0]
        orr     r0, r0, #OP_SET_TILE
        b       copro_envia

@ ----------------------------------------------------------------------------
@ li_xy_envia (interna): r0 = palavra pronta, r1 = x, r2 = y
@   envia  LI r1, x  /  LI r2, y  /  palavra
@ ----------------------------------------------------------------------------
li_xy_envia:
        push    {r4, r5, r6, lr}
        mov     r4, r0
        mov     r5, r2
        mov     r0, #1
        bl      copro_li                       @ LI r1, x   (r1 ja tem o x)
        cmp     r0, #0
        bne     1f
        mov     r0, #2
        mov     r1, r5
        bl      copro_li                       @ LI r2, y
        cmp     r0, #0
        bne     1f
        mov     r0, r4
        bl      copro_envia                    @ a instrucao que usa r1 e r2
1:      pop     {r4, r5, r6, pc}

@ int copro_scroll(int x, int y)             ->  LI r1,x / LI r2,y / SET_SCROLL r1, r2
        .global copro_scroll
        .type   copro_scroll, %function
copro_scroll:
        mov     r2, r1
        mov     r1, r0
        ldr     r0, =OP_SET_SCROLL
        b       li_xy_envia

@ int copro_vertice(int slot, int v, int x, int y)  ->  ... / POLY_VTX slot, v, r1, r2
        .global copro_vertice
        .type   copro_vertice, %function
copro_vertice:
        and     r0, r0, #31
        and     r1, r1, #3
        lsl     r0, r0, #22
        orr     r0, r0, r1                     @ vertice em [1:0]
        ldr     r12, =OP_POLY_VTX
        orr     r0, r0, r12
        mov     r1, r2                         @ x
        mov     r2, r3                         @ y
        b       li_xy_envia

@ int copro_poligono(int slot, int tipo, int cor)   ->  POLY_CFG slot, tipo, cor
        .global copro_poligono
        .type   copro_poligono, %function
copro_poligono:
        and     r0, r0, #31
        and     r1, r1, #3
        and     r2, r2, #255
        lsl     r0, r0, #22
        orr     r0, r0, r1, lsl #8             @ tipo em [9:8]
        orr     r0, r0, r2                     @ cor em [7:0]
        orr     r0, r0, #OP_POLY_CFG
        b       copro_envia

@ int copro_move_poligono(int slot, int dx, int dy) ->  ... / POLY_MOVE slot, r1, r2
        .global copro_move_poligono
        .type   copro_move_poligono, %function
copro_move_poligono:
        and     r0, r0, #31
        lsl     r0, r0, #22
        ldr     r12, =OP_POLY_MOVE
        orr     r0, r0, r12
        b       li_xy_envia                    @ r1 = dx, r2 = dy (ja estao no lugar)

@ int copro_sprite_pos(int n, int x, int y)         ->  ... / SPR_POS n, r1, r2
        .global copro_sprite_pos
        .type   copro_sprite_pos, %function
copro_sprite_pos:
        and     r0, r0, #31
        lsl     r0, r0, #22
        ldr     r12, =OP_SPR_POS
        orr     r0, r0, r12
        b       li_xy_envia

@ int copro_move_sprite(int n, int dx, int dy)      ->  ... / SPR_MOVE n, r1, r2
        .global copro_move_sprite
        .type   copro_move_sprite, %function
copro_move_sprite:
        and     r0, r0, #31
        lsl     r0, r0, #22
        ldr     r12, =OP_SPR_MOVE
        orr     r0, r0, r12
        b       li_xy_envia

@ int copro_sprite_attr(int n, int tile, int flags) ->  SPR_ATTR n, tile, flags
@   flags: bit0 EN, bit1 FX, bit2 FY, bit3 BACK  (COPRO_EN, COPRO_FX... no copro.h)
        .global copro_sprite_attr
        .type   copro_sprite_attr, %function
copro_sprite_attr:
        and     r0, r0, #31
        and     r1, r1, #255
        and     r2, r2, #15
        lsl     r0, r0, #22
        orr     r0, r0, r2, lsl #8             @ EN FX FY BACK em [11:8]
        orr     r0, r0, r1                     @ tile em [7:0]
        orr     r0, r0, #OP_SPR_ATTR
        b       copro_envia

        .ltorg

        .section .note.GNU-stack, "", %progbits   @ pilha nao executavel (evita aviso do linker)
