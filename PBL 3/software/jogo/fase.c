/* ============================================================================
 * fase.c - desenho da fase (tiles do fundo), textos e mapa de colisao
 *
 * A torre e desenhada uma vez por fase com SET_TILE, e o programa guarda uma
 * copia do mapa (40 x 30) para responder rapido "tem viga aqui?" sem nunca
 * precisar ler nada do coprocessador.
 *
 * Tiles usados (fixos na ROM do fundo desde a fase 2):
 *   160..169  digitos          170..195  letras       196..201  " :!-.?"
 *   208+      materiais (tijolo, pedra, gelo, lava, metal...)
 *   222       preto (fundo)    223       branco
 * A "escada" e a letra H empilhada: dois trilhos e um degrau por tile.
 * ========================================================================== */
#include <stdio.h>
#include <string.h>
#include "copro.h"
#include "jogo.h"

const int VIGA_Y[N_VIGAS] = {224, 184, 144, 104, 64};
/* desenhos das pecas na ROM de sprites (ferramentas/gera_sprites_jogo.py) */
const int   PECA_DESENHO[N_TIPOS_MAX] = {11, 12, 13, 14};
const char *PECA_NOME[N_TIPOS_MAX]    = {"CPU", "RAM", "HD", "DISQUETE"};
#define T_PRETO   222
#define T_ESCADA  177                 /* letra H                              */

/* material da viga muda a cada semestre, so pela aparencia */
static const int MATERIAL[] = {215, 208, 218, 216, 209};   /* metal, tijolo,
                                                              gelo, lava, pedra */
#define N_MATERIAIS 5

/* mapa de colisao: bit 1 = solido (viga/chao/lombada), bit 2 = escada */
#define M_SOLIDO 1
#define M_ESCADA 2
static unsigned char mapa[30][40];

/* escadas: coluna e faixa de linhas de tiles (inclusive) */
static const int ESCADA[][3] = {      /* {coluna, linha_de_cima, linha_de_baixo} */
    { 4, 24, 27},                     /* chao   -> viga 1                     */
    {30, 19, 22},                     /* viga 1 -> viga 2                     */
    { 4, 14, 17},                     /* viga 2 -> viga 3                     */
    {30,  9, 12},                     /* viga 3 -> viga 4 (topo)              */
};
#define N_ESCADAS 4

/* ---------------- consultas usadas pela logica ---------------- */
int tile_solido(int px, int py)
{
    if (px < 0 || px >= TELA_W || py < 0 || py >= TELA_H) return 0;
    return (mapa[py / 8][px / 8] & M_SOLIDO) != 0;
}

int escada_em(int px, int py)
{
    if (px < 0 || px >= TELA_W || py < 0 || py >= TELA_H) return 0;
    return (mapa[py / 8][px / 8] & M_ESCADA) != 0;
}

/* ---------------- texto com os tiles da fonte ---------------- */
static int tile_do_char(char ch)
{
    if (ch >= '0' && ch <= '9') return 160 + (ch - '0');
    if (ch >= 'A' && ch <= 'Z') return 170 + (ch - 'A');
    if (ch >= 'a' && ch <= 'z') return 170 + (ch - 'a');
    switch (ch) {
    case ':': return 197;
    case '!': return 198;
    case '-': return 199;
    case '.': return 200;
    case '?': return 201;
    default:  return 196;             /* espaco                               */
    }
}

void texto(int lin, int col, const char *s)
{
    for (; *s && col < 40; s++, col++)
        copro_tile(lin, col, tile_do_char(*s));
}

void texto_apaga(int lin, int col, int n)
{
    while (n-- > 0 && col < 40)
        copro_tile(lin, col++, T_PRETO);
}

/* ---------------- HUD (linha 0): so reenvia o que mudou ---------------- */
static char hud_antes[41];

void hud_reseta(void)
{
    memset(hud_antes, 0, sizeof hud_antes);
    texto(0, 1, "PONTOS");            /* valor nas colunas 8..13              */
    texto(0, 16, "VIDAS");            /* valor na coluna 22                   */
    texto(0, 26, "SEMESTRE");         /* valor nas colunas 35..36             */
}

void hud_atualiza(void)
{
    char agora[32];
    int i;
    /* agora[0..5] pontos, agora[6] vidas, agora[7..8] semestre */
    snprintf(agora, sizeof agora, "%06ld%1d%2d",
             J.pontos > 999999 ? 999999 : J.pontos, J.vidas % 10, J.fase % 100);
    for (i = 0; i < 6; i++)
        if (agora[i] != hud_antes[i]) copro_tile(0, 8 + i, tile_do_char(agora[i]));
    if (agora[6] != hud_antes[6]) copro_tile(0, 22, tile_do_char(agora[6]));
    if (agora[7] != hud_antes[7]) copro_tile(0, 35, tile_do_char(agora[7]));
    if (agora[8] != hud_antes[8]) copro_tile(0, 36, tile_do_char(agora[8]));
    memcpy(hud_antes, agora, 9);
}

/* ---------------- desenho da fase ---------------- */
static void poe(int lin, int col, int tile, int marca)
{
    copro_tile(lin, col, tile);
    mapa[lin][col] = marca;
}

void fase_desenha(int fase)
{
    int mat = MATERIAL[(fase - 1) % N_MATERIAIS];
    int l, c, v, e;

    memset(mapa, 0, sizeof mapa);

    /* fundo preto (tela inteira) */
    for (l = 0; l < 30; l++)
        for (c = 0; c < 40; c++)
            copro_tile(l, c, T_PRETO);

    /* chao: linhas 28 e 29, largura toda */
    for (l = 28; l <= 29; l++)
        for (c = 0; c < 40; c++)
            poe(l, c, mat, M_SOLIDO);

    /* vigas 1 a 4: colunas 2..32 (x de 16 a 263) */
    for (v = 1; v < N_VIGAS; v++) {
        l = VIGA_Y[v] / 8;            /* 23, 18, 13, 8                        */
        for (c = 2; c <= 32; c++)
            poe(l, c, mat, M_SOLIDO);
    }

    /* lombada na frente da caixa (o aluno nao passa; as pecas pulam) */
    poe(26, 33, mat, M_SOLIDO);
    poe(27, 33, mat, M_SOLIDO);

    /* escadas (a logica deixa atravessar a viga na coluna da escada) */
    for (e = 0; e < N_ESCADAS; e++)
        for (l = ESCADA[e][1]; l <= ESCADA[e][2]; l++)
            poe(l, ESCADA[e][0], T_ESCADA, M_ESCADA);

    /* letreiro da caixa de componentes */
    texto(19, 34, "CAIXA");

    hud_reseta();
}
