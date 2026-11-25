/* ============================================================================
 * logica.c - regras do jogo: aluno, professor, pecas, caixa e pontuacao
 *
 * Tudo aqui e so conta em C sobre o estado do jogo (struct Jogo). Nada
 * desenha: quem manda a cena para o coprocessador e o jogo.c, depois que a
 * logica do quadro termina.
 *
 * Fisica (por quadro, a 60 quadros/s):
 *   - gravidade 0.22 px/q^2; pulo -3.4 px/q (sobe ~26 px: passa por cima de
 *     uma peca, nao alcanca a viga de cima);
 *   - aluno anda 1.5 px/q; na escada sobe/desce 1.3 px/q;
 *   - peca rola 1.0 + 0.15*(semestre-1) px/q e cai na ponta da viga;
 *   - ao passar por uma escada que desce, a peca pode descer por ela e cair
 *     direto na viga de baixo (chance de 20% no 1o semestre, +5% por
 *     semestre, ate 65%): o aluno nunca sabe por onde ela vai vir.
 *
 * Caixa de componentes: grade de 3 x 4. A peca que chega cai na coluna mais
 * proxima; grupos de GRUPO_MIN ou mais pecas IGUAIS encostadas (4 direcoes)
 * somem, as de cima descem e, se formar grupo de novo, elimina em cadeia
 * (combo x2, x3...).
 * ========================================================================== */
#include <stdlib.h>
#include "jogo.h"

#define GRAV      0.22f
#define V_ANDA    1.5f
#define V_ESCADA  1.3f
#define V_PULO    -3.4f
#define ALCANCE_FERRAMENTA 56         /* raio de acao do clique do mouse      */

Jogo J;

/* ---------------- aluno ---------------- */
static void aluno_reinicia(void)
{
    J.aluno.x = 24;  J.aluno.y = 224 - 16;   /* comeca no chao, a esquerda   */
    J.aluno.vy = 0;
    J.aluno.no_chao = 1;
    J.aluno.na_escada = 0;
    J.aluno.andando = 0;
    J.aluno.olhando_esq = 0;
    J.aluno.invulneravel = 120;              /* 2 s piscando                  */
}

/* centro x da escada perto do corpo do aluno (ou -1) */
static int escada_perto(int cx, int pes)
{
    static const int cols[] = {4, 30};       /* colunas de tiles das escadas  */
    int i;
    for (i = 0; i < 2; i++) {
        int ex = cols[i] * 8 + 4;
        if (cx > ex - 7 && cx < ex + 7 && escada_em(ex, pes + 12))
            return ex;
    }
    return -1;
}


// pra ver se resolve o bug da escada
static int escada_corpo_perto(int cx, int pes)
{
    static const int cols[] = {4, 30};
    int i;

    for (i = 0; i < 2; i++) {
        int ex = cols[i] * 8 + 4;

        if (cx > ex - 7 && cx < ex + 7 &&
            escada_em(ex, pes + 4))
            return ex;
    }

    return -1;
}


static void aluno_passo(const Entrada *e)
{
    Aluno *h = &J.aluno;
    int cx = (int)h->x + 8, pes = (int)h->y + 16;
    int ex;

    h->andando = 0;
    if (h->invulneravel > 0) h->invulneravel--;
    if (h->na_escada) {
        float v = (pes < h->esc_topo + 8) ? 3 * V_ESCADA : V_ESCADA;

        if (e->cima)  h->y -= v;
        if (e->baixo) h->y += v;

        h->andando = e->cima || e->baixo;
        pes = (int)h->y + 16;

        /* Sai pelo topo somente quando alcanca a plataforma */
        if (tile_solido(cx, pes + 1) && escada_em(cx, pes + 9)) {
            h->y = (float)(((pes + 1) / 8) * 8 - 16);
            h->na_escada = 0;
            h->no_chao = 1;
            h->vy = 0;
        }
        else if (escada_corpo_perto(cx, pes) < 0) {
            h->na_escada = 0;
            h->vy = 0;
            h->no_chao = tile_solido(cx, pes + 1);
        }
        else {
            return;
        }
    }


    /* entrar na escada */
    if ((e->cima || e->baixo) && (ex = escada_perto(cx, pes)) >= 0) {
        int desce = e->baixo && tile_solido(cx, pes + 1);
        if (e->cima || desce) {
            h->x = (float)(ex - 8);
            h->na_escada = 1;  h->no_chao = 0;  h->vy = 0;
            if (desce) h->y += 3;
            return;
        }
    }

    /* andar */
    if (e->esq) { h->x -= V_ANDA;  h->olhando_esq = 1;  h->andando = 1; }
    if (e->dir) { h->x += V_ANDA;  h->olhando_esq = 0;  h->andando = 1; }
    if (h->x < 0) h->x = 0;
    if (h->x > BARREIRA_X && pes > 200 && h->no_chao) h->x = BARREIRA_X;
    if (h->x > TELA_W - 16) h->x = TELA_W - 16;

    /* pulo e gravidade */
    if (e->pulo && h->no_chao) { h->vy = V_PULO;  h->no_chao = 0; }
    if (!h->no_chao) {
        h->vy += GRAV;
        h->y += h->vy;
        pes = (int)h->y + 16;
        if (h->vy > 0 && tile_solido((int)h->x + 8, pes)) {   /* aterrissou   */
            h->y = (float)((pes / 8) * 8 - 16);
            h->vy = 0;  h->no_chao = 1;
        }
    } else if (!tile_solido((int)h->x + 8, pes + 1)) {
        h->no_chao = 0;                /* saiu andando da beirada             */
        h->vy = 0;
    }
}

/* ---------------- pecas arremessadas ---------------- */
static void arremessa_peca(void)
{
    int i, n_tipos = (J.fase >= 3) ? 4 : 3;  /* disquete entra no 3o semestre */
    for (i = 0; i < MAX_PECAS; i++)
        if (!J.peca[i].ativa) break;
    if (i == MAX_PECAS) return;

    J.peca[i].ativa  = 1;
    J.peca[i].tipo   = rand() % n_tipos;
    J.peca[i].x      = J.prof_x + 22;          /* sai da mao levantada         */
    J.peca[i].y      = PROF_Y;
    J.peca[i].vy     = -1.5f;                  /* jogada para cima             */
    J.peca[i].caindo = 1;
    J.peca[i].viga   = N_VIGAS - 1;
    J.peca[i].dir    = 1;
    J.peca[i].pulada = 0;
    J.peca[i].viu_escada = 0;
    J.prof_arremessa = 20;                     /* pose de arremesso por 1/3 s  */
}

static float vel_peca(void)
{
    float v = 1.0f + 0.15f * (J.fase - 1);
    return (v > 2.0f) ? 2.0f : v;
}

/* chance (0..100) de a peca descer pela escada */
static int chance_escada(void)
{
    int c = 20 + 5 * (J.fase - 1);
    return (c > 65) ? 65 : c;
}

/* x do centro da escada que DESCE da viga v (v = 1..4), ou -1 */
static int escada_que_desce(int v)
{
    if (v < 1 || v >= N_VIGAS) return -1;
    return ((v % 2 == 0) ? 30 : 4) * 8 + 4;   /* colunas 30 e 4 se alternam */
}

static int caixa_entra(int tipo, float x);

/* move as pecas; devolve 1 se a caixa lotou */
static int pecas_passo(void)
{
    int i;
    for (i = 0; i < MAX_PECAS; i++) {
        Peca *g = &J.peca[i];
        if (!g->ativa) continue;

        if (g->caindo) {
            g->vy += GRAV;
            g->y += g->vy;
            if (g->vy > 0 && g->y + 16 >= VIGA_Y[g->viga] &&
                g->y + 16 <= VIGA_Y[g->viga] + 8) {
                /* so aterrissa se a viga existe nesse x (ou e o chao) */
                if (g->viga == 0 ||
                    (g->x + 8 >= VIGA_X0 && g->x + 8 <= VIGA_X1)) {
                    g->y = (float)(VIGA_Y[g->viga] - 16);
                    g->vy = 0;
                    g->caindo = 0;
                    g->viu_escada = 0;
                    /* zigue-zague: vigas pares para a direita, impares para a esquerda */
                    g->dir = (g->viga % 2 == 0) ? 1 : -1;
                } else
                    g->viga--;         /* passou do vao: segue para a de baixo */
            }
            if (g->y > TELA_H) g->ativa = 0;
            continue;
        }

        /* rolando sobre a viga g->viga */
        g->x += g->dir * vel_peca();

        /* passando pela escada que desce: sorteia se desce por ela */
        if (g->viga > 0 && !g->viu_escada) {
            int ex = escada_que_desce(g->viga), cx = (int)g->x + 8;
            if (ex >= 0 && cx >= ex - 1 && cx <= ex + 1) {
                g->viu_escada = 1;
                if (rand() % 100 < chance_escada()) {
                    g->x = (float)(ex - 8);           /* centraliza na escada  */
                    g->caindo = 1;
                    g->vy = 0.5f;
                    g->viga--;                        /* vai para a de baixo   */
                    continue;
                }
            }
        }

        if (g->viga > 0) {
            if (g->x + 8 < VIGA_X0 || g->x + 8 > VIGA_X1) {   /* caiu da ponta */
                g->caindo = 1;
                g->viga--;
            }
        } else {
            /* no chao: pula a lombada e entra na caixa */
            if (g->dir > 0 && g->x >= 240 && g->x < 243) {
                g->caindo = 1;  g->vy = -2.6f;
            }
            if (g->x >= POCO_X) {
                int tipo = g->tipo;
                g->ativa = 0;
                if (caixa_entra(tipo, g->x)) return 1;
            }
            if (g->x < -16) g->ativa = 0;
        }
    }
    return 0;
}

/* ---------------- caixa: pilha e eliminacao de agrupamentos ---------------- */
/* conta (e marca) o grupo de pecas iguais ligado a (c, l) */
static int caixa_grupo(int c, int l, int tipo, int marca[POCO_COLS][POCO_LINS])
{
    if (c < 0 || c >= POCO_COLS || l < 0 || l >= POCO_LINS) return 0;
    if (marca[c][l] || J.poco[c][l] != tipo) return 0;
    marca[c][l] = 1;
    return 1 + caixa_grupo(c - 1, l, tipo, marca) + caixa_grupo(c + 1, l, tipo, marca)
             + caixa_grupo(c, l - 1, tipo, marca) + caixa_grupo(c, l + 1, tipo, marca);
}

static void caixa_elimina(void)
{
    int cadeia = 1, mexeu = 1;
    while (mexeu) {
        int marca[POCO_COLS][POCO_LINS] = {{0}}, tira[POCO_COLS][POCO_LINS] = {{0}};
        int c, l, achou = 0;
        mexeu = 0;
        for (c = 0; c < POCO_COLS; c++)
            for (l = 0; l < POCO_LINS; l++) {
                int n;
                if (J.poco[c][l] < 0 || marca[c][l]) continue;
                n = caixa_grupo(c, l, J.poco[c][l], marca);
                if (n >= GRUPO_MIN) {
                    int c2, l2;
                    int m2[POCO_COLS][POCO_LINS] = {{0}};
                    caixa_grupo(c, l, J.poco[c][l], m2);
                    for (c2 = 0; c2 < POCO_COLS; c2++)
                        for (l2 = 0; l2 < POCO_LINS; l2++)
                            tira[c2][l2] |= m2[c2][l2];
                    J.pontos += 500L * n * cadeia;
                    achou = 1;
                }
            }
        if (achou) {
            int c2, l2, d;
            for (c2 = 0; c2 < POCO_COLS; c2++) {
                for (l2 = 0; l2 < POCO_LINS; l2++)
                    if (tira[c2][l2]) { J.poco[c2][l2] = -1; J.n_poco--; }
                /* as de cima descem (linha 0 = fundo) */
                d = 0;
                for (l2 = 0; l2 < POCO_LINS; l2++) {
                    if (J.poco[c2][l2] < 0) continue;
                    J.poco[c2][d++] = J.poco[c2][l2];
                    if (d - 1 != l2) J.poco[c2][l2] = -1;
                }
            }
            J.explosao_t = 14;
            J.explosao_x = POCO_X + 24;               /* centro da caixa      */
            J.explosao_y = POCO_Y_BASE - 32;
            J.estilhaca = 1;
            cadeia++;
            mexeu = 1;
        }
    }
}

/* poe a peca na caixa; devolve 1 se nao coube (caixa lotada) */
static int caixa_entra(int tipo, float x)
{
    int c = ((int)x - POCO_X + 8) / 16, tenta, l;
    if (c < 0) c = 0;
    if (c >= POCO_COLS) c = POCO_COLS - 1;

    for (tenta = 0; tenta < POCO_COLS; tenta++) {
        int cc = (c + tenta) % POCO_COLS;
        for (l = 0; l < POCO_LINS; l++)
            if (J.poco[cc][l] < 0) {
                J.poco[cc][l] = tipo;
                J.n_poco++;
                caixa_elimina();
                return 0;
            }
    }
    return 1;
}

/* ---------------- chave de fenda (clique do mouse) ----------------
 * Clicar numa peca perto do aluno desmonta a peca (300 pontos). Mas cada
 * peca desmontada deixa de ir para a caixa, onde poderia render um combo. */
static void chave_de_fenda(const Entrada *e)
{
    int i, hx = (int)J.aluno.x + 8, hy = (int)J.aluno.y + 8;
    for (i = 0; i < MAX_PECAS; i++) {
        Peca *g = &J.peca[i];
        int gx, gy, dx, dy;
        if (!g->ativa) continue;
        gx = (int)g->x + 8;  gy = (int)g->y + 8;
        if (e->mouse_x < gx - 10 || e->mouse_x > gx + 10 ||
            e->mouse_y < gy - 10 || e->mouse_y > gy + 10) continue;
        dx = gx - hx;  dy = gy - hy;
        if (dx * dx + dy * dy > ALCANCE_FERRAMENTA * ALCANCE_FERRAMENTA) continue;
        g->ativa = 0;
        J.pontos += 300;
        J.explosao_t = 10;
        J.explosao_x = gx;
        J.explosao_y = gy;
        J.estilhaca = 1;
        return;                       /* uma peca por clique                  */
    }
}

/* ---------------- professor ---------------- */
static void prof_passo(void)
{
    int intervalo = 150 - 15 * (J.fase - 1);   /* arremessa mais rapido a cada semestre */
    if (intervalo < 60) intervalo = 60;

    if (J.prof_arremessa > 0) J.prof_arremessa--;
    else {                                     /* parado enquanto arremessa    */
        J.prof_x += J.prof_dir * 1.0f;
        if (J.prof_x < PROF_XMIN) { J.prof_x = PROF_XMIN;  J.prof_dir = 1; }
        if (J.prof_x > PROF_XMAX) { J.prof_x = PROF_XMAX;  J.prof_dir = -1; }
    }

    J.solta_total = intervalo;
    if (--J.solta_em <= 0) {
        arremessa_peca();
        J.solta_em = intervalo;
    }
}

/* ---------------- montagem ---------------- */
void logica_nova_fase(void)
{
    int i, c, l;
    aluno_reinicia();
    for (i = 0; i < MAX_PECAS; i++) J.peca[i].ativa = 0;
    for (c = 0; c < POCO_COLS; c++)
        for (l = 0; l < POCO_LINS; l++) J.poco[c][l] = -1;
    J.n_poco = 0;
    J.prof_x = 80;  J.prof_dir = 1;
    J.prof_arremessa = 0;
    J.solta_em = 90;  J.solta_total = 90;
    J.explosao_t = 0;
    J.quadro = 0;
}

/* perdeu uma vida: as pecas somem e o aluno volta ao inicio; a caixa fica */
void logica_perdeu_vida(void)
{
    int i;
    for (i = 0; i < MAX_PECAS; i++) J.peca[i].ativa = 0;
    aluno_reinicia();
    J.solta_em = 90;  J.solta_total = 90;
    J.explosao_t = 0;
}

void logica_nova_partida(void)
{
    J.fase = 1;
    J.vidas = 3;
    J.pontos = 0;
    J.formado = 0;
    logica_nova_fase();
}

/* ---------------- um quadro de jogo ---------------- */
int logica_passo(const Entrada *e)
{
    Aluno *h = &J.aluno;
    int i, hx, hy;

    J.quadro++;
    aluno_passo(e);
    prof_passo();
    if (pecas_passo()) return 3;      /* caixa lotou                          */
    if (e->clique) chave_de_fenda(e);
    if (J.explosao_t > 0) J.explosao_t--;

    hx = (int)h->x;  hy = (int)h->y;

    /* caiu dentro da caixa */
    if (hx + 8 >= POCO_X && hy + 16 >= 160) return 1;

    if (h->invulneravel == 0) {
        /* atingido por uma peca */
        for (i = 0; i < MAX_PECAS; i++) {
            Peca *g = &J.peca[i];
            if (!g->ativa) continue;
            if (hx + 12 > g->x + 3 && hx + 4 < g->x + 13 &&
                hy + 15 > g->y + 3 && hy + 2 < g->y + 13)
                return 1;
        }
        /* encostou no professor */
        if (hx + 12 > J.prof_x + 4 && hx + 4 < J.prof_x + 28 &&
            hy + 15 > PROF_Y + 2 && hy < PROF_Y + 32)
            return 1;
    }

    /* pulou por cima de uma peca rolando: 100 pontos (uma vez por peca) */
    if (!h->no_chao && !h->na_escada)
        for (i = 0; i < MAX_PECAS; i++) {
            Peca *g = &J.peca[i];
            if (!g->ativa || g->caindo || g->pulada) continue;
            if (g->x + 8 > hx + 2 && g->x + 8 < hx + 14 &&
                g->y > hy + 8 && g->y < hy + 40) {
                g->pulada = 1;
                J.pontos += 100;
            }
        }

    /* pegou o diploma (ponta direita da viga do topo) */
    if (hy + 16 == VIGA_Y[N_VIGAS - 1] && hx + 8 > DIPLOMA_X - 8) return 2;

    return 0;
}
