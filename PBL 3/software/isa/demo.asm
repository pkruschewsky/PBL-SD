; ============================================================================
; demo.asm - PROGRAMA DE DEMONSTRACAO escrito no Assembly da NOSSA ISA
;
; Monta a cena e anima:
;   - cidade com scroll horizontal (feito pela ULA do coprocessador)
;   - letreiro "TEC499 PBL2" escrito com os tiles de fonte (SET_TILE)
;   - janelas de um predio apagando e acendendo (SET_TILE durante a animacao)
;   - triangulo vermelho (slot 0) e retangulo azul (slot 1) subindo/descendo
;   - sprite 0 indo e voltando na horizontal
;   - sprite 1 andando na diagonal, POR TRAS dos poligonos (atributo BACK)
;
; Montar:   python3 montador.py demo.asm      (gera demo.lst e programa_isa.s)
;
; Como as instrucoes vem do ARM (busca assincrona, por FIFO) e a ISA nao tem
; desvios, o programa e dividido em
; BLOCOS. O programa ARM (demo_arm.s) decide quando enviar cada bloco:
;
;   cena          1 vez, no inicio
;   quadro        1 vez por quadro (comeca com WAITV)
;   scroll        a cada 3 quadros
;   scroll_volta  quando o scroll chega em 320 (volta para 0)
;   vira_*        quando o sprite 0 bate na borda esquerda/direita
;   ret_*         quando o retangulo chega no limite de cima/baixo
;   spr1_volta    a cada 120 quadros (sprite 1 volta para o canto)
;   luzes_apagam  / luzes_acendem   a cada 30 quadros (janelas do predio cinza piscam)
;
; Mapa dos registradores do coprocessador usados:
;   r1, r2   temporarios (x, y) para montar a cena
;   r10,r11  (x, y) do sprite 0           r12      passo de x do sprite 0
;   r13,r14  (dx, dy) do sprite 1          r15,r16  (dx, dy) do retangulo
;   r20      scroll_x atual                r21      passo do scroll (1)
; ============================================================================

        .equ VERMELHO,      0xE0      ; RGB332 111 000 00
        .equ AZUL,          0x03      ; RGB332 000 000 11
        .equ TILE_JOGADOR,  4
        .equ TILE_INIMIGO,  8
        .equ JANELA_ACESA,  220       ; tiles avulsos (ver ferramentas/fundo/tabela_tiles.md)
        .equ JANELA_APAGADA, 221
        .equ X_INICIAL,     40        ; tem que bater com X_INICIAL do demo_arm.s
        .equ PASSO_X,       2

; ----------------------------------------------------------------------------
        .bloco cena
; ----------------------------------------------------------------------------
        ; letreiro "TEC499 PBL2" no ceu (linha 1, colunas 2 a 12), com os tiles da fonte:
        ; letra = 170 + (letra - 'A'), digito = 160 + digito, espaco = 196
        SET_TILE   1, 2, 189          ; T
        SET_TILE   1, 3, 174          ; E
        SET_TILE   1, 4, 172          ; C
        SET_TILE   1, 5, 164          ; 4
        SET_TILE   1, 6, 169          ; 9
        SET_TILE   1, 7, 169          ; 9
        SET_TILE   1, 8, 196          ; (espaco)
        SET_TILE   1, 9, 185          ; P
        SET_TILE   1, 10, 171         ; B
        SET_TILE   1, 11, 181         ; L
        SET_TILE   1, 12, 162         ; 2

        ; scroll comeca em (0, 0); r21 = passo usado pela ULA no bloco scroll
        LI         r20, 0
        LI         r21, 1
        SET_SCROLL r20, r0

        ; triangulo vermelho no slot 0: (160,40) (120,120) (200,120)
        LI         r1, 160
        LI         r2, 40
        POLY_VTX   0, 0, r1, r2
        LI         r1, 120
        LI         r2, 120
        POLY_VTX   0, 1, r1, r2
        LI         r1, 200
        POLY_VTX   0, 2, r1, r2
        POLY_CFG   0, TRI, VERMELHO

        ; retangulo azul no slot 1: canto (30,150) ate (110,190)
        LI         r1, 30
        LI         r2, 150
        POLY_VTX   1, 0, r1, r2
        LI         r1, 110
        LI         r2, 190
        POLY_VTX   1, 1, r1, r2
        POLY_CFG   1, RECT, AZUL

        ; sprite 0 (jogador) em (40, 60)
        LI         r10, X_INICIAL
        LI         r11, 60
        SPR_POS    0, r10, r11
        SPR_ATTR   0, TILE_JOGADOR, EN

        ; sprite 1 em (20, 20), atras dos poligonos
        LI         r1, 20
        LI         r2, 20
        SPR_POS    1, r1, r2
        SPR_ATTR   1, TILE_INIMIGO, EN, BACK

        ; registradores da animacao
        LI         r12, PASSO_X       ; passo do sprite 0
        LI         r13, 1             ; dx do sprite 1
        LI         r14, 1             ; dy do sprite 1
        LI         r15, 0             ; dx do retangulo
        LI         r16, 1             ; dy do retangulo

; ----------------------------------------------------------------------------
        .bloco quadro                 ; enviado 1 vez por quadro
; ----------------------------------------------------------------------------
        WAITV                         ; espera o vblank: atualiza sem "rasgar" a imagem
        ADD        r10, r10, r12      ; ULA: x = x + passo
        SPR_POS    0, r10, r11        ; motor de sprites recebe a nova posicao
        SPR_MOVE   1, r13, r14        ; sprite 1 anda (dx, dy)
        POLY_MOVE  1, r15, r16        ; retangulo anda (dx, dy)

; ----------------------------------------------------------------------------
        .bloco scroll                 ; a cada 3 quadros
; ----------------------------------------------------------------------------
        ADD        r20, r20, r21      ; ULA: scroll_x = scroll_x + 1
        SET_SCROLL r20, r0

        .bloco scroll_volta           ; quando scroll_x chegaria a 320
        LI         r20, 0
        SET_SCROLL r20, r0

; ----------------------------------------------------------------------------
; mudancas de direcao (o ARM decide QUANDO; o coprocessador so troca o passo)
; ----------------------------------------------------------------------------
        .bloco vira_esquerda
        LI         r12, -PASSO_X

        .bloco vira_direita
        LI         r12, PASSO_X

        .bloco ret_sobe
        LI         r16, -1

        .bloco ret_desce
        LI         r16, 1

        .bloco spr1_volta             ; sprite 1 volta para (20, 20)
        LI         r1, 20
        LI         r2, 20
        SPR_POS    1, r1, r2

; ----------------------------------------------------------------------------
; luzes do predio cinza (colunas 0 a 3, andares das linhas 20 e 21 do mapa)
; ----------------------------------------------------------------------------
        .bloco luzes_apagam
        SET_TILE   20, 0, JANELA_APAGADA
        SET_TILE   20, 1, JANELA_APAGADA
        SET_TILE   20, 2, JANELA_APAGADA
        SET_TILE   20, 3, JANELA_APAGADA
        SET_TILE   21, 0, JANELA_APAGADA
        SET_TILE   21, 1, JANELA_APAGADA
        SET_TILE   21, 2, JANELA_APAGADA
        SET_TILE   21, 3, JANELA_APAGADA

        .bloco luzes_acendem
        SET_TILE   20, 0, JANELA_ACESA
        SET_TILE   20, 1, JANELA_ACESA
        SET_TILE   20, 2, JANELA_ACESA
        SET_TILE   20, 3, JANELA_ACESA
        SET_TILE   21, 0, JANELA_ACESA
        SET_TILE   21, 1, JANELA_ACESA
        SET_TILE   21, 2, JANELA_ACESA
        SET_TILE   21, 3, JANELA_ACESA
