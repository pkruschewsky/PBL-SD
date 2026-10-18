/* ============================================================================
 * demo.c - programa de DEMONSTRACAO do coprocessador (roda no ARM / Linux)
 *
 * Envia instrucoes da ISA pelo DRIVER em Assembly (driver_copro.s) e anima a cena:
 *   - cidade (fundo) com letreiro "TEC499 PBL2" e janelas piscando (SET_TILE)
 *   - triangulo vermelho (slot 0) e retangulo azul (slot 1)
 *   - sprite 0 indo e voltando na horizontal (WAITV + ADD + SPR_POS)
 *   - sprite 1 andando na diagonal com SPR_MOVE
 *   - retangulo subindo e descendo com POLY_MOVE
 *
 * (Programa de teste em C. O programa final exigido pelo PBL e em Assembly ARM.)
 *
 * Compilar na placa (demo.c, copro.h e driver_copro.s na mesma pasta):
 *                     gcc -o demo demo.c driver_copro.s
 * Rodar:              sudo ./demo            (anima 600 quadros = ~10 s)
 *                     sudo ./demo 0          (anima ate apertar Ctrl+C)
 *                     sudo ./demo reset      (so reinicia o coprocessador)
 * ========================================================================== */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include "copro.h"               /* DRIVER em Assembly (driver_copro.s) */

/* ---------------- montador minimo (mesma codificacao da ISA) ---------------- */
#define R(op,a,b,c)          (((uint32_t)(op)<<27)|((uint32_t)(a)<<22)|((uint32_t)(b)<<17)|((uint32_t)(c)<<12))
#define LI(rd,imm)           (R(1,rd,0,0) | ((uint32_t)(imm) & 0xFFFF))
#define ADD(rd,rs,rt)        R(2,rd,rs,rt)
#define SUB(rd,rs,rt)        R(3,rd,rs,rt)
#define ADDI(rd,rs,imm)      (R(4,rd,rs,0) | ((uint32_t)(imm) & 0x1FFFF))
#define WAITV                R(7,0,0,0)
#define SET_TILE(l,c,t)      (R(8,l,0,0) | ((uint32_t)(c)<<16) | ((t) & 0xFF))
#define SET_SCROLL(rs,rt)    R(9,0,rs,rt)
#define POLY_VTX(s,v,rs,rt)  (R(16,s,rs,rt) | ((v) & 3))
#define POLY_CFG(s,tp,cor)   (R(17,s,0,0) | ((uint32_t)(tp)<<8) | ((cor) & 0xFF))
#define POLY_MOVE(s,rs,rt)   R(18,s,rs,rt)
#define SPR_POS(n,rs,rt)     R(24,n,rs,rt)
#define SPR_ATTR(n,t,en,fx,fy,bk) (R(25,n,0,0) | ((uint32_t)(bk)<<11) | ((uint32_t)(fy)<<10) | \
                                   ((uint32_t)(fx)<<9) | ((uint32_t)(en)<<8) | ((t) & 0xFF))
#define SPR_MOVE(n,rs,rt)    R(26,n,rs,rt)
#define OFF 0
#define RECT 1
#define TRI 2
#define JANELA_ACESA   220   /* tiles avulsos: ver ferramentas/fundo/tabela_tiles.md */
#define JANELA_APAGADA 221

/* envia uma instrucao pelo driver; se o coprocessador nao responder, encerra */
static void envia(uint32_t p)
{
    if (copro_envia(p) != 0) {
        printf("ERRO: tempo esgotado (status=0x%08X)\n", copro_status());
        copro_fecha();
        exit(1);
    }
}

int main(int argc, char *argv[])
{
    int q, quadros = 600, x = 40, dir = 2, ry = 0, rdir = 1;
    int sx = 0;
    int scroll_contador = 0;
    int r = copro_abre();        /* driver: open("/dev/mem") + mmap da ponte */

    if (r == -1) { printf("ERRO: rode com sudo\n"); return 1; }
    if (r != 0)  { printf("ERRO: mmap\n"); return 1; }

    copro_reinicia();
    if (argc > 1 && strcmp(argv[1], "reset") == 0) { printf("Coprocessador reiniciado.\n"); copro_fecha(); return 0; }
    if (argc > 1) quadros = atoi(argv[1]);
    printf("Status apos reset: 0x%08X (esperado 0x0000000A ou 0x0000002A)\n", copro_status());

    /* ---------------- cena inicial ---------------- */
    /* letreiro "TEC499 PBL2" no ceu (tiles da fonte: letra = 170 + (letra-'A'),
       digito = 160 + digito, espaco = 196) */
    {
        const char *txt = "TEC499 PBL2";
        int i;
        for (i = 0; txt[i]; i++) {
            int c = txt[i], t = (c == ' ') ? 196 : (c <= '9') ? 160 + c - '0' : 170 + c - 'A';
            envia(SET_TILE(1, 2 + i, t));
        }
    }

    /* scroll comeca em (0, 0) */
    envia(LI(1, 0)); envia(LI(2, 0)); envia(SET_SCROLL(1, 2));

    /* triangulo vermelho no slot 0 */
    envia(LI(1, 160)); envia(LI(2, 40));  envia(POLY_VTX(0, 0, 1, 2));
    envia(LI(1, 120)); envia(LI(2, 120)); envia(POLY_VTX(0, 1, 1, 2));
    envia(LI(1, 200));                    envia(POLY_VTX(0, 2, 1, 2));
    envia(POLY_CFG(0, TRI, 0xE0));
    /* retangulo azul no slot 1 */
    envia(LI(1, 30));  envia(LI(2, 150)); envia(POLY_VTX(1, 0, 1, 2));
    envia(LI(1, 110)); envia(LI(2, 190)); envia(POLY_VTX(1, 1, 1, 2));
    envia(POLY_CFG(1, RECT, 0x03));
    /* sprite 0 (jogador) e sprite 1 (atras dos poligonos) */
    envia(LI(10, x));  envia(LI(11, 60)); envia(SPR_POS(0, 10, 11));
    envia(SPR_ATTR(0, 4, 1, 0, 0, 0));
    envia(LI(1, 20));  envia(LI(2, 20));  envia(SPR_POS(1, 1, 2));
    envia(SPR_ATTR(1, 8, 1, 0, 0, 1));
    /* registradores usados na animacao */
    envia(LI(12, dir));                    /* passo do sprite 0          */
    envia(LI(13, 1));  envia(LI(14, 1));   /* (dx, dy) do sprite 1       */
    envia(LI(15, 0));  envia(LI(16, 1));   /* (dx, dy) do retangulo      */
    copro_espera_fim();
    printf("Cena montada. Animando %s...\n", quadros ? "" : "(Ctrl+C para parar)");

    /* ---------------- laco de animacao: 1 bloco por quadro ---------------- */
    for (q = 0; quadros == 0 || q < quadros; q++) {
        /* o ARM decide a logica (bater na parede) e o coprocessador desenha */
        if (x >= 280 && dir > 0) { dir = -2; envia(LI(12, dir)); }
        if (x <= 20  && dir < 0) { dir =  2; envia(LI(12, dir)); }
        if (ry >= 40 && rdir > 0) { rdir = -1; envia(LI(16, 0xFFFF)); }
        if (ry <= 0  && rdir < 0) { rdir =  1; envia(LI(16, 1)); }
        x += dir; ry += rdir;

        envia(WAITV);                     /* espera o fim do quadro (sem tearing) */

        /* scroll horizontal: anda 1 pixel a cada 3 quadros */
        if (++scroll_contador >= 3) {
            scroll_contador = 0;
            sx = (sx + 1) % 320;
            envia(LI(1, sx)); envia(LI(2, 0)); envia(SET_SCROLL(1, 2));
        }

        envia(ADD(10, 10, 12));           /* ULA: x = x + passo                   */
        envia(SPR_POS(0, 10, 11));        /* motor de sprites recebe a posicao    */
        envia(SPR_MOVE(1, 13, 14));       /* sprite 1 anda na diagonal            */
        envia(POLY_MOVE(1, 15, 16));      /* retangulo sobe/desce                 */
        if ((q % 120) == 119) { envia(LI(1, 20)); envia(LI(2, 20)); envia(SPR_POS(1, 1, 2)); }
        /* janelas do predio cinza (linhas 20-21, colunas 0-3) piscam a cada 30 quadros */
        if (((q + 1) % 30) == 0) {
            int t = (((q + 1) % 60) == 30) ? JANELA_APAGADA : JANELA_ACESA, l, c;
            for (l = 20; l <= 21; l++) for (c = 0; c <= 3; c++) envia(SET_TILE(l, c, t));
        }
    }
    copro_espera_fim();
    printf("Fim. Status: 0x%08X%s\n", copro_status(),
           (copro_status() & COPRO_ST_ERR) ? "  (ERRO: opcode invalido recebido)" : "");

    copro_fecha();
    return 0;
}

