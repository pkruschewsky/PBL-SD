/* ============================================================================
 * efeitos.c - tudo que o jogo desenha com o RASTERIZADOR DE POLIGONOS
 *
 * Os poligonos vao para a camada de poligonos (framebuffer), que fica atras
 * dos sprites e na frente dos tiles do fundo. Slot menor fica na frente.
 * Os numeros dos slots estao em jogo.h (PL_...).
 *
 *   retangulos: cursor do mouse (2), barra de lotacao da caixa, lousa e
 *               moldura atras do professor, giz (tempo ate o arremesso)
 *   triangulos: estilhacos que voam quando uma peca e desmontada ou um
 *               grupo some na caixa, raios de furia do professor (a partir
 *               do 3o semestre), setas de tutorial nas escadas (1o semestre)
 *               e confetes na tela de formatura
 *
 * Para gastar pouco, cada efeito so manda instrucao quando algo muda; os
 * que se movem usam POLY_MOVE (o coprocessador soma o deslocamento nos
 * vertices) em vez de reenviar os 3 vertices a cada quadro.
 * ========================================================================== */
#include <stdlib.h>
#include "copro.h"
#include "jogo.h"

/* cores RGB332 */
#define C_BRANCO   0xFF
#define C_AMARELO  0xFC
#define C_LARANJA  0xF0
#define C_VERMELHO 0xE0
#define C_VERDE    0x1C
#define C_LOUSA    0x0C               /* verde escuro                         */
#define C_MADEIRA  0x68               /* marrom                               */
#define C_CINZA    0x92

static int limita(int v, int min, int max) { return v < min ? min : (v > max ? max : v); }

/* ---------------- liga/desliga ---------------- */
void efeitos_desliga_todos(void)
{
    int s;
    for (s = 0; s < 32; s++) copro_poligono(s, COPRO_OFF, 0);
}

/* ---------------- cursor do mouse: cruz com 2 retangulos ---------------- */
static int cur_antes_x = -1, cur_antes_y = -1;

void cursor_liga(void)
{
    copro_poligono(PL_CURSOR_H, COPRO_RECT, C_BRANCO);
    copro_poligono(PL_CURSOR_V, COPRO_RECT, C_BRANCO);
    cur_antes_x = cur_antes_y = -1;
}

void cursor_envia(int mx, int my)
{
    if (mx == cur_antes_x && my == cur_antes_y) return;
    cur_antes_x = mx;  cur_antes_y = my;
    copro_vertice(PL_CURSOR_H, 0, limita(mx - 5, 0, TELA_W - 1), limita(my - 1, 1, TELA_H - 1));
    copro_vertice(PL_CURSOR_H, 1, limita(mx + 5, 0, TELA_W - 1), limita(my + 1, 1, TELA_H - 1));
    copro_vertice(PL_CURSOR_V, 0, limita(mx - 1, 0, TELA_W - 1), limita(my - 5, 1, TELA_H - 1));
    copro_vertice(PL_CURSOR_V, 1, limita(mx + 1, 0, TELA_W - 1), limita(my + 5, 1, TELA_H - 1));
}

/* ---------------- barra de lotacao da caixa ---------------- */
static int barra_antes = -1;

void barra_caixa_envia(void)
{
    int n = J.n_poco;
    if (n == barra_antes) return;
    barra_antes = n;
    if (n == 0) { copro_poligono(PL_BARRA_CX, COPRO_OFF, 0); return; }
    copro_vertice(PL_BARRA_CX, 0, 266, POCO_Y_BASE - 5 * n);
    copro_vertice(PL_BARRA_CX, 1, 270, POCO_Y_BASE);
    copro_poligono(PL_BARRA_CX, COPRO_RECT,
                   (n >= 9) ? C_VERMELHO : (n >= 5) ? C_AMARELO : C_VERDE);
}

/* ---------------- lousa atras do professor + giz ---------------- */
#define LOUSA_X0  16
#define LOUSA_X1  236
#define GIZ_X0    24
#define GIZ_LARG  204
static int giz_antes = -1, giz_ligado;

void lousa_desenha(void)
{
    copro_vertice(PL_MOLDURA, 0, LOUSA_X0, 10);         /* moldura de madeira */
    copro_vertice(PL_MOLDURA, 1, LOUSA_X1, 63);
    copro_poligono(PL_MOLDURA, COPRO_RECT, C_MADEIRA);
    copro_vertice(PL_LOUSA, 0, LOUSA_X0 + 3, 13);       /* quadro verde       */
    copro_vertice(PL_LOUSA, 1, LOUSA_X1 - 3, 63);
    copro_poligono(PL_LOUSA, COPRO_RECT, C_LOUSA);
    giz_antes = -1;
    giz_ligado = 0;
}

/* risco de giz que encolhe ate o proximo arremesso (avisa o jogador) */
void giz_envia(void)
{
    int larg = (J.solta_total > 0) ? GIZ_LARG * J.solta_em / J.solta_total : 0;
    larg = limita(larg, 0, GIZ_LARG) & ~1;              /* passo de 2 pixels  */
    if (larg == giz_antes) return;
    giz_antes = larg;
    if (larg < 2) {
        copro_poligono(PL_GIZ, COPRO_OFF, 0);
        giz_ligado = 0;
        return;
    }
    copro_vertice(PL_GIZ, 0, GIZ_X0, 17);
    copro_vertice(PL_GIZ, 1, GIZ_X0 + larg, 20);
    if (!giz_ligado) {                                  /* liga uma vez so    */
        copro_poligono(PL_GIZ, COPRO_RECT, C_BRANCO);
        giz_ligado = 1;
    }
}

/* ---------------- estilhacos: 6 triangulos voando ---------------- */
typedef struct { float x, y, vx, vy; int px, py, vida; } Estilhaco;
static Estilhaco est[N_ESTILHACOS];

void estilhacos_solta(int cx, int cy)
{
    static const float VX[N_ESTILHACOS] = {-2.2f, -1.2f, -0.4f, 0.4f, 1.2f, 2.2f};
    static const int   COR[N_ESTILHACOS] = {C_AMARELO, C_LARANJA, C_CINZA,
                                            C_AMARELO, C_LARANJA, C_CINZA};
    int i;
    cx = limita(cx, 8, TELA_W - 9);
    cy = limita(cy, 16, TELA_H - 9);
    for (i = 0; i < N_ESTILHACOS; i++) {
        int s = PL_ESTILHACO0 + i;
        est[i].x = est[i].px = cx;
        est[i].y = est[i].py = cy;
        est[i].vx = VX[i];
        est[i].vy = -2.6f + 0.3f * (i % 3);
        est[i].vida = 28;
        /* triangulo pequeno com a ponta para cima */
        copro_vertice(s, 0, cx,     cy - 3);
        copro_vertice(s, 1, cx - 3, cy + 3);
        copro_vertice(s, 2, cx + 3, cy + 3);
        copro_poligono(s, COPRO_TRI, COR[i]);
    }
}

void estilhacos_passo(void)
{
    int i;
    for (i = 0; i < N_ESTILHACOS; i++) {
        Estilhaco *e = &est[i];
        int nx, ny, s = PL_ESTILHACO0 + i;
        if (e->vida <= 0) continue;
        e->vy += 0.25f;                                 /* gravidade          */
        e->x += e->vx;
        e->y += e->vy;
        nx = (int)e->x;  ny = (int)e->y;
        if (--e->vida == 0 || nx < 4 || nx > TELA_W - 5 || ny < 12 || ny > TELA_H - 5) {
            e->vida = 0;
            copro_poligono(s, COPRO_OFF, 0);
            continue;
        }
        if (nx != e->px || ny != e->py)
            copro_move_poligono(s, nx - e->px, ny - e->py);   /* POLY_MOVE  */
        e->px = nx;  e->py = ny;
    }
}

void estilhacos_apaga(void)
{
    int i;
    for (i = 0; i < N_ESTILHACOS; i++)
        if (est[i].vida > 0) {
            est[i].vida = 0;
            copro_poligono(PL_ESTILHACO0 + i, COPRO_OFF, 0);
        }
}

/* ---------------- raios de furia do professor (3o semestre em diante) ---- */
static int furia_antes = -1;

void furia_envia(void)
{
    int liga = (J.fase >= 3 && J.prof_arremessa > 0 && (J.prof_arremessa / 4) % 2 == 0);
    int px = (int)J.prof_x;
    if (liga == furia_antes) return;
    furia_antes = liga;
    if (!liga) {
        copro_poligono(PL_FURIA0, COPRO_OFF, 0);
        copro_poligono(PL_FURIA0 + 1, COPRO_OFF, 0);
        return;
    }
    /* professor fica parado enquanto arremessa: os raios ficam ao lado dele */
    copro_vertice(PL_FURIA0, 0, px - 12, 28);
    copro_vertice(PL_FURIA0, 1, px - 2,  36);
    copro_vertice(PL_FURIA0, 2, px - 9,  46);
    copro_poligono(PL_FURIA0, COPRO_TRI, C_AMARELO);
    copro_vertice(PL_FURIA0 + 1, 0, px + 44, 28);
    copro_vertice(PL_FURIA0 + 1, 1, px + 34, 36);
    copro_vertice(PL_FURIA0 + 1, 2, px + 41, 46);
    copro_poligono(PL_FURIA0 + 1, COPRO_TRI, C_AMARELO);
}

/* ---------------- setas de tutorial nas duas primeiras escadas ---------- */
static int setas_antes = -1;

void setas_envia(void)
{
    int liga = (J.fase == 1 && (J.quadro / 30) % 2 == 0);    /* pisca 1 vez/s */
    if (liga == setas_antes) return;
    if (setas_antes < 0) {                              /* posicao: uma vez   */
        /* ao lado da escada do chao (coluna 4), ponta para cima */
        copro_vertice(PL_SETA0, 0, 48, 202);
        copro_vertice(PL_SETA0, 1, 43, 212);
        copro_vertice(PL_SETA0, 2, 53, 212);
        /* ao lado da escada da viga 1 (coluna 30) */
        copro_vertice(PL_SETA0 + 1, 0, 232, 162);
        copro_vertice(PL_SETA0 + 1, 1, 227, 172);
        copro_vertice(PL_SETA0 + 1, 2, 237, 172);
    }
    setas_antes = liga;
    copro_poligono(PL_SETA0,     liga ? COPRO_TRI : COPRO_OFF, C_AMARELO);
    copro_poligono(PL_SETA0 + 1, liga ? COPRO_TRI : COPRO_OFF, C_AMARELO);
}

/* ---------------- quando a fase e redesenhada ---------------- */
void efeitos_nova_fase(void)
{
    efeitos_desliga_todos();
    cursor_liga();
    lousa_desenha();
    barra_antes = furia_antes = setas_antes = -1;
    {   /* estilhacos parados (os slots ja foram desligados acima) */
        int i;
        for (i = 0; i < N_ESTILHACOS; i++) est[i].vida = 0;
    }
}

/* tudo que muda a cada quadro da partida */
void efeitos_quadro(int mouse_x, int mouse_y)
{
    if (J.estilhaca) {
        estilhacos_solta(J.explosao_x, J.explosao_y);
        J.estilhaca = 0;
    } else
        estilhacos_passo();
    cursor_envia(mouse_x, mouse_y);
    barra_caixa_envia();
    giz_envia();
    furia_envia();
    setas_envia();
}

/* ---------------- confetes da formatura: 16 triangulos caindo ---------- */
typedef struct { float y, vy; int x, py, dx; } Confete;
static Confete conf[N_CONFETES];

static void confete_coloca(int i, int y)
{
    static const int COR[] = {C_VERMELHO, C_AMARELO, C_VERDE, 0x03, 0xE3, C_BRANCO, C_LARANJA, 0x1F};
    int s = PL_CONFETE0 + i;
    conf[i].x  = 12 + rand() % (TELA_W - 24);
    conf[i].y  = conf[i].py = y;
    conf[i].vy = 0.8f + (rand() % 10) / 10.0f;
    conf[i].dx = (rand() % 2) ? 1 : -1;
    copro_vertice(s, 0, conf[i].x,     y);
    copro_vertice(s, 1, conf[i].x + 5, y + 2);
    copro_vertice(s, 2, conf[i].x + 1, y + 6);
    copro_poligono(s, COPRO_TRI, COR[i % 8]);
}

void confetes_inicia(void)
{
    int i;
    for (i = 0; i < N_CONFETES; i++) confete_coloca(i, 10 + rand() % 120);
}

void confetes_passo(int quadro)
{
    int i;
    for (i = 0; i < N_CONFETES; i++) {
        int ny, dx = 0;
        conf[i].y += conf[i].vy;
        ny = (int)conf[i].y;
        if (ny > TELA_H - 12) { confete_coloca(i, 10); continue; }   /* volta ao topo */
        if ((quadro + i * 7) % 20 == 0) {               /* balanca de lado    */
            dx = conf[i].dx;
            conf[i].dx = -conf[i].dx;
            if (conf[i].x + dx < 4 || conf[i].x + dx > TELA_W - 10) dx = 0;
            conf[i].x += dx;
        }
        if (ny != conf[i].py || dx)
            copro_move_poligono(PL_CONFETE0 + i, dx, ny - conf[i].py);
        conf[i].py = ny;
    }
}
