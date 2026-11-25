/* ============================================================================
 * copro.h - interface do DRIVER do coprocessador grafico (driver_copro.s)
 *
 * As funcoes estao implementadas em Assembly ARM (driver_copro.s); este
 * arquivo so diz ao compilador C quais sao e como chama-las.
 *
 *   gcc -o meu_programa meu_programa.c driver_copro.s
 *
 * Todas as funcoes "int" retornam 0 se deu certo e -1 se o coprocessador
 * nao respondeu (FPGA nao programada, sistema nao gerado...).
 * ========================================================================== */
#ifndef COPRO_H
#define COPRO_H
#include <stdint.h>

/* ---------------- bits do pio_status ---------------- */
#define COPRO_ST_BUSY   (1u << 0)   /* UC executando (ou restaurando o fundo)   */
#define COPRO_ST_DONE   (1u << 1)   /* fila vazia e UC parada                   */
#define COPRO_ST_FULL   (1u << 2)   /* fila cheia                               */
#define COPRO_ST_EMPTY  (1u << 3)   /* fila vazia                               */
#define COPRO_ST_ACK    (1u << 4)   /* ack do handshake                         */
#define COPRO_ST_VBLANK (1u << 5)   /* tela no intervalo vertical               */
#define COPRO_ST_ERR    (1u << 6)   /* chegou opcode invalido (ate o reset)     */
#define COPRO_FLAGS(s)  (((s) >> 8) & 0xF)      /* N Z C V da ULA               */
#define COPRO_FILA(s)   (((s) >> 16) & 0x3F)    /* instrucoes na fila           */

/* ---------------- constantes das instrucoes ---------------- */
#define COPRO_OFF  0                /* tipos de poligono (POLY_CFG); slots 0 a 3 */
#define COPRO_RECT 1                /* RECT: vertice 0 = canto sup. esq., 1 = inf. dir. */
#define COPRO_TRI  2
#define COPRO_EN   1                /* flags do sprite (SPR_ATTR)               */
#define COPRO_FX   2                /* espelho horizontal                       */
#define COPRO_FY   4                /* espelho vertical                         */
#define COPRO_BACK 8                /* atras dos poligonos                      */

/* ---------------- baixo nivel ---------------- */
int      copro_abre(void);          /* 0 ok, -1 sem /dev/mem (use sudo), -2 mmap falhou */
void     copro_fecha(void);
void     copro_reinicia(void);      /* reset: some tudo e o fundo volta ao inicial  */
uint32_t copro_status(void);
int      copro_envia(uint32_t instrucao);                         /* 1 palavra da ISA */
int      copro_envia_bloco(const uint32_t *inicio, const uint32_t *fim);
int      copro_espera_fim(void);    /* espera executar tudo que foi enviado     */

/* ---------------- alto nivel (1 funcao = 1 a 3 instrucoes da ISA) ----------------
 * As que recebem coordenadas usam r1 e r2 do coprocessador como temporarios:
 *   LI r1, x  /  LI r2, y  /  instrucao                                         */
int copro_li(int rd, int valor);                          /* LI rd, valor        */
int copro_espera_quadro(void);                            /* WAITV               */
int copro_tile(int lin, int col, int tile);               /* SET_TILE            */
int copro_scroll(int x, int y);                           /* SET_SCROLL          */
int copro_vertice(int slot, int v, int x, int y);         /* POLY_VTX            */
int copro_poligono(int slot, int tipo, int cor);          /* POLY_CFG            */
int copro_move_poligono(int slot, int dx, int dy);        /* POLY_MOVE           */
int copro_sprite_pos(int n, int x, int y);                /* SPR_POS             */
int copro_sprite_attr(int n, int tile, int flags);        /* SPR_ATTR            */
int copro_move_sprite(int n, int dx, int dy);             /* SPR_MOVE            */

/* ---------------- historico: ultimas palavras enviadas ----------------
 * O driver guarda cada palavra enviada (ate 64). Zere copro_hist_n para
 * comecar de novo; o menu usa isso para mostrar as instrucoes geradas.      */
extern uint32_t copro_hist[64];
extern int      copro_hist_n;

/* ---------------- montagem de palavras (para quem quer usar copro_envia) ---- */
#define COPRO_R(op, a, b, c)  (((uint32_t)(op) << 27) | ((uint32_t)(a) << 22) | \
                               ((uint32_t)(b) << 17) | ((uint32_t)(c) << 12))
#define ISA_LI(rd, imm)           (COPRO_R(1, rd, 0, 0) | ((uint32_t)(imm) & 0xFFFF))
#define ISA_ADD(rd, rs, rt)       COPRO_R(2, rd, rs, rt)
#define ISA_SUB(rd, rs, rt)       COPRO_R(3, rd, rs, rt)
#define ISA_ADDI(rd, rs, imm)     (COPRO_R(4, rd, rs, 0) | ((uint32_t)(imm) & 0x1FFFF))
#define ISA_AND(rd, rs, rt)       COPRO_R(5, rd, rs, rt)
#define ISA_OR(rd, rs, rt)        COPRO_R(6, rd, rs, rt)
#define ISA_WAITV                 COPRO_R(7, 0, 0, 0)
#define ISA_SET_TILE(l, c, t)     (COPRO_R(8, l, 0, 0) | ((uint32_t)(c) << 16) | ((t) & 0xFF))
#define ISA_SET_SCROLL(rs, rt)    COPRO_R(9, 0, rs, rt)
#define ISA_POLY_VTX(s, v, rs, rt) (COPRO_R(16, s, rs, rt) | ((v) & 3))
#define ISA_POLY_CFG(s, tp, cor)  (COPRO_R(17, s, 0, 0) | ((uint32_t)(tp) << 8) | ((cor) & 0xFF))
#define ISA_POLY_MOVE(s, rs, rt)  COPRO_R(18, s, rs, rt)
#define ISA_SPR_POS(n, rs, rt)    COPRO_R(24, n, rs, rt)
#define ISA_SPR_ATTR(n, t, flags) (COPRO_R(25, n, 0, 0) | ((uint32_t)((flags) & 15) << 8) | ((t) & 0xFF))
#define ISA_SPR_MOVE(n, rs, rt)   COPRO_R(26, n, rs, rt)

#endif
