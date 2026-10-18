@ ==========================================================================
@ programa_isa.s - GERADO AUTOMATICAMENTE por montador.py a partir de demo.asm
@ NAO EDITE A MAO: altere o .asm e rode o montador de novo.
@
@ Cada bloco vira uma tabela de palavras de 32 bits (codigo de maquina da
@ NOSSA ISA). O ARM nao executa estas palavras: ele so as le da memoria e
@ as envia, uma a uma, para o coprocessador pelos PIOs.
@ ==========================================================================
        .section .rodata
        .align 2

        .global isa_cena, isa_cena_fim
isa_cena:
        .word 0x404200BD      @ SET_TILE   1, 2, 189          ; T
        .word 0x404300AE      @ SET_TILE   1, 3, 174          ; E
        .word 0x404400AC      @ SET_TILE   1, 4, 172          ; C
        .word 0x404500A4      @ SET_TILE   1, 5, 164          ; 4
        .word 0x404600A9      @ SET_TILE   1, 6, 169          ; 9
        .word 0x404700A9      @ SET_TILE   1, 7, 169          ; 9
        .word 0x404800C4      @ SET_TILE   1, 8, 196          ; (espaco)
        .word 0x404900B9      @ SET_TILE   1, 9, 185          ; P
        .word 0x404A00AB      @ SET_TILE   1, 10, 171         ; B
        .word 0x404B00B5      @ SET_TILE   1, 11, 181         ; L
        .word 0x404C00A2      @ SET_TILE   1, 12, 162         ; 2
        .word 0x0D000000      @ LI         r20, 0
        .word 0x0D400001      @ LI         r21, 1
        .word 0x48280000      @ SET_SCROLL r20, r0
        .word 0x084000A0      @ LI         r1, 160
        .word 0x08800028      @ LI         r2, 40
        .word 0x80022000      @ POLY_VTX   0, 0, r1, r2
        .word 0x08400078      @ LI         r1, 120
        .word 0x08800078      @ LI         r2, 120
        .word 0x80022001      @ POLY_VTX   0, 1, r1, r2
        .word 0x084000C8      @ LI         r1, 200
        .word 0x80022002      @ POLY_VTX   0, 2, r1, r2
        .word 0x880002E0      @ POLY_CFG   0, TRI, VERMELHO
        .word 0x0840001E      @ LI         r1, 30
        .word 0x08800096      @ LI         r2, 150
        .word 0x80422000      @ POLY_VTX   1, 0, r1, r2
        .word 0x0840006E      @ LI         r1, 110
        .word 0x088000BE      @ LI         r2, 190
        .word 0x80422001      @ POLY_VTX   1, 1, r1, r2
        .word 0x88400103      @ POLY_CFG   1, RECT, AZUL
        .word 0x0A800028      @ LI         r10, X_INICIAL
        .word 0x0AC0003C      @ LI         r11, 60
        .word 0xC014B000      @ SPR_POS    0, r10, r11
        .word 0xC8000104      @ SPR_ATTR   0, TILE_JOGADOR, EN
        .word 0x08400014      @ LI         r1, 20
        .word 0x08800014      @ LI         r2, 20
        .word 0xC0422000      @ SPR_POS    1, r1, r2
        .word 0xC8400908      @ SPR_ATTR   1, TILE_INIMIGO, EN, BACK
        .word 0x0B000002      @ LI         r12, PASSO_X       ; passo do sprite 0
        .word 0x0B400001      @ LI         r13, 1             ; dx do sprite 1
        .word 0x0B800001      @ LI         r14, 1             ; dy do sprite 1
        .word 0x0BC00000      @ LI         r15, 0             ; dx do retangulo
        .word 0x0C000001      @ LI         r16, 1             ; dy do retangulo
isa_cena_fim:

        .global isa_quadro, isa_quadro_fim
isa_quadro:
        .word 0x38000000      @ WAITV                         ; espera o vblank: atualiza sem "rasgar" a imagem
        .word 0x1294C000      @ ADD        r10, r10, r12      ; ULA: x = x + passo
        .word 0xC014B000      @ SPR_POS    0, r10, r11        ; motor de sprites recebe a nova posicao
        .word 0xD05AE000      @ SPR_MOVE   1, r13, r14        ; sprite 1 anda (dx, dy)
        .word 0x905F0000      @ POLY_MOVE  1, r15, r16        ; retangulo anda (dx, dy)
isa_quadro_fim:

        .global isa_scroll, isa_scroll_fim
isa_scroll:
        .word 0x15295000      @ ADD        r20, r20, r21      ; ULA: scroll_x = scroll_x + 1
        .word 0x48280000      @ SET_SCROLL r20, r0
isa_scroll_fim:

        .global isa_scroll_volta, isa_scroll_volta_fim
isa_scroll_volta:
        .word 0x0D000000      @ LI         r20, 0
        .word 0x48280000      @ SET_SCROLL r20, r0
isa_scroll_volta_fim:

        .global isa_vira_esquerda, isa_vira_esquerda_fim
isa_vira_esquerda:
        .word 0x0B00FFFE      @ LI         r12, -PASSO_X
isa_vira_esquerda_fim:

        .global isa_vira_direita, isa_vira_direita_fim
isa_vira_direita:
        .word 0x0B000002      @ LI         r12, PASSO_X
isa_vira_direita_fim:

        .global isa_ret_sobe, isa_ret_sobe_fim
isa_ret_sobe:
        .word 0x0C00FFFF      @ LI         r16, -1
isa_ret_sobe_fim:

        .global isa_ret_desce, isa_ret_desce_fim
isa_ret_desce:
        .word 0x0C000001      @ LI         r16, 1
isa_ret_desce_fim:

        .global isa_spr1_volta, isa_spr1_volta_fim
isa_spr1_volta:
        .word 0x08400014      @ LI         r1, 20
        .word 0x08800014      @ LI         r2, 20
        .word 0xC0422000      @ SPR_POS    1, r1, r2
isa_spr1_volta_fim:

        .global isa_luzes_apagam, isa_luzes_apagam_fim
isa_luzes_apagam:
        .word 0x450000DD      @ SET_TILE   20, 0, JANELA_APAGADA
        .word 0x450100DD      @ SET_TILE   20, 1, JANELA_APAGADA
        .word 0x450200DD      @ SET_TILE   20, 2, JANELA_APAGADA
        .word 0x450300DD      @ SET_TILE   20, 3, JANELA_APAGADA
        .word 0x454000DD      @ SET_TILE   21, 0, JANELA_APAGADA
        .word 0x454100DD      @ SET_TILE   21, 1, JANELA_APAGADA
        .word 0x454200DD      @ SET_TILE   21, 2, JANELA_APAGADA
        .word 0x454300DD      @ SET_TILE   21, 3, JANELA_APAGADA
isa_luzes_apagam_fim:

        .global isa_luzes_acendem, isa_luzes_acendem_fim
isa_luzes_acendem:
        .word 0x450000DC      @ SET_TILE   20, 0, JANELA_ACESA
        .word 0x450100DC      @ SET_TILE   20, 1, JANELA_ACESA
        .word 0x450200DC      @ SET_TILE   20, 2, JANELA_ACESA
        .word 0x450300DC      @ SET_TILE   20, 3, JANELA_ACESA
        .word 0x454000DC      @ SET_TILE   21, 0, JANELA_ACESA
        .word 0x454100DC      @ SET_TILE   21, 1, JANELA_ACESA
        .word 0x454200DC      @ SET_TILE   21, 2, JANELA_ACESA
        .word 0x454300DC      @ SET_TILE   21, 3, JANELA_ACESA
isa_luzes_acendem_fim:

        .section .note.GNU-stack, "", %progbits
