/* ============================================================================
 * jogo.h - definicoes compartilhadas do jogo RUMO AO DIPLOMA
 *
 * No alto de uma torre de vigas, um professor arremessa pecas de hardware
 * (CPU, memoria RAM, HD e disquete). O aluno comeca la embaixo e sobe pelas
 * escadas desviando das pecas, ate pegar o diploma. As pecas rolam pelas
 * vigas ate cair na CAIXA DE COMPONENTES, no canto inferior direito:
 * 3 ou mais pecas iguais encostadas somem (pontos em cadeia). Se a caixa
 * lotar, fim de jogo. Pegando o diploma, passa de semestre; depois do
 * 10o semestre o aluno se FORMA e o jogo termina com a tela de formatura.
 *
 * Toda a cena e desenhada pelo coprocessador, atraves do driver em Assembly
 * (tiles do fundo, sprites e poligonos). A aplicacao nunca toca nos
 * registradores: so usa as funcoes de copro.h, como o PBL03 exige.
 * ========================================================================== */
#ifndef JOGO_H
#define JOGO_H
#include <stdint.h>

/* ---------------- tela e fase ---------------- */
#define TELA_W      320
#define TELA_H      240
#define N_VIGAS     5                 /* indice 0 = chao, 4 = viga do topo    */
#define N_SEMESTRES 10                /* pegou o diploma do 10o: formado      */

/* superficie (y do topo da viga) de cada viga, do chao para cima */
extern const int VIGA_Y[N_VIGAS];     /* {224, 184, 144, 104, 64}             */
#define VIGA_X0     16                /* vigas 1..4 vao de x=16 a x=264       */
#define VIGA_X1     264
#define BARREIRA_X  252               /* lombada no chao, antes da caixa      */

/* professor (32x32) anda na viga do topo, so na metade esquerda */
#define PROF_Y      32                /* VIGA_Y[4] - 32                       */
#define PROF_XMIN   24
#define PROF_XMAX   150
#define DIPLOMA_X   256

/* ---------------- caixa de componentes (eliminacao de agrupamentos) ---- */
#define POCO_COLS   3
#define POCO_LINS   4
#define POCO_X      272               /* celula (c,l): x = POCO_X + 16*c      */
#define POCO_Y_BASE 224               /* fundo da caixa (topo do chao)        */
#define GRUPO_MIN   3                 /* tamanho minimo do grupo que some     */

/* ---------------- pecas de hardware arremessadas ---------------- */
#define MAX_PECAS   6
#define N_TIPOS_MAX 4                 /* CPU, RAM, HD, disquete               */

typedef struct {
    int   ativa;
    int   tipo;                       /* 0..3 (indice em PECA_DESENHO)        */
    float x, y, vy;
    int   dir;                        /* +1 direita, -1 esquerda              */
    int   caindo;
    int   viga;                       /* em qual viga esta rolando            */
    int   pulada;                     /* o aluno ja ganhou pontos pulando ela */
    int   viu_escada;                 /* ja decidiu se desce a escada da viga  */
} Peca;

/* ---------------- aluno ---------------- */
typedef struct {
    float x, y, vy;
    int   no_chao;                    /* apoiado numa viga                    */
    int   na_escada;
    int   andando;                    /* andou neste quadro (anima o passo)   */
    int   esc_topo, esc_fundo;        /* na escada: y dos pes no topo e no fundo */   // <- NOVA
    int   olhando_esq;
    int   invulneravel;               /* quadros restantes de pisca           */
} Aluno;

/* ---------------- estados do jogo (maquina de estados do PBL03) ------- */
typedef enum { ABERTURA, MENU, PARTIDA, PAUSA, FIM } Estado;

/* ---------------- estado global ---------------- */
typedef struct {
    Estado estado;
    int    fase;                      /* semestre: 1, 2, 3...                 */
    int    vidas;
    long   pontos;
    int    opcao_menu;                /* 0 = iniciar, 1 = sair                */

    Aluno  aluno;
    Peca   peca[MAX_PECAS];
    int    poco[POCO_COLS][POCO_LINS];   /* -1 vazio; 0..3 = tipo da peca     */
    int    n_poco;                       /* celulas ocupadas                  */

    float  prof_x;                    /* professor no topo                    */
    int    prof_dir;
    int    prof_arremessa;            /* quadros restantes da pose de arremesso */
    int    solta_em;                  /* quadros ate arremessar a proxima peca*/
    int    solta_total;               /* intervalo atual entre arremessos     */

    int    explosao_t;                /* quadros restantes da faisca          */
    int    explosao_x, explosao_y;    /* centro da faisca                     */
    int    estilhaca;                 /* 1 = soltar estilhacos neste quadro   */
    int    formado;                   /* 1 = zerou o jogo (fim com vitoria)   */
    int    quadro;                    /* contador de quadros da partida       */
} Jogo;

extern Jogo J;

/* ---------------- entrada (entrada.c) ---------------- */
typedef struct {
    int esq, dir, cima, baixo;        /* teclas seguradas                     */
    int pulo, enter, pausa, reinicia, sair;   /* apertadas neste quadro       */
    int pula_fase;                    /* F na pausa: pula o semestre (demonstracao) */
    int mouse_x, mouse_y;             /* posicao do cursor na tela logica     */
    int clique;                       /* botao esquerdo apertado neste quadro */
    double t_evento_ms;               /* chegada do 1o evento do quadro (0 = nenhum) */
} Entrada;

int  entrada_abre(void);              /* acha teclado e mouse e cria as threads */
void entrada_le(Entrada *e);          /* copia o estado das threads de entrada */
void entrada_fecha(void);             /* para as threads e fecha os dispositivos */

/* ---------------- fase e texto (fase.c) ---------------- */
void fase_desenha(int fase);          /* tilemap inteiro da fase              */
void texto(int lin, int col, const char *s);      /* fonte dos tiles 160+     */
void texto_apaga(int lin, int col, int n);
void hud_atualiza(void);              /* pontos, vidas e semestre (so o que mudou) */
void hud_reseta(void);
int  tile_solido(int px, int py);     /* 1 se (px,py) cai em viga/chao/lombada */
int  escada_em(int px, int py);       /* 1 se ha escada nesse ponto           */

/* ---------------- poligonos (efeitos.c) ---------------- */
void efeitos_desliga_todos(void);     /* os 32 slots em OFF                   */
void efeitos_nova_fase(void);         /* lousa, cursor; zera os efeitos       */
void efeitos_quadro(int mouse_x, int mouse_y);   /* tudo que muda no quadro   */
void cursor_liga(void);
void cursor_envia(int mx, int my);
void lousa_desenha(void);
void estilhacos_apaga(void);
void confetes_inicia(void);           /* tela de formatura                    */
void confetes_passo(int quadro);

/* ---------------- logica (logica.c) ---------------- */
void logica_nova_partida(void);
void logica_nova_fase(void);
void logica_perdeu_vida(void);        /* tira as pecas e recoloca o aluno     */
/* devolve: 0 nada, 1 perdeu vida, 2 pegou o diploma, 3 caixa lotou */
int  logica_passo(const Entrada *e);

/* ---------------- sprites (numeros usados no SPR_POS / SPR_ATTR) ------- */
#define SPR_ALUNO    0
#define SPR_DIPLOMA  1
#define SPR_PROF0    2                /* 2..5 = professor (4 quartos 16x16)   */
#define SPR_PECA0    6                /* 6..11 = pecas rolando                */
#define SPR_FAISCA   12
#define SPR_POCO0    13               /* 13..24 = celulas da caixa            */

/* ---------------- desenhos da ROM de sprites (SPR_ATTR recebe desenho*4)
 * gerados por ferramentas/gera_sprites_jogo.py                            */
#define DES_PROF_PARADO    0          /* 0..3: SE, SD, IE, ID                 */
#define DES_PROF_ARREMESSA 4          /* 4..7: SE, SD, IE, ID                 */
#define DES_ALUNO_PARADO   8
#define DES_ALUNO_ANDA     9
#define DES_ALUNO_ESCADA   10
#define DES_DIPLOMA        15
#define DES_FAISCA         16

/* ---------------- slots de poligono (slot menor fica na frente) --------
 * Desenhados pelo rasterizador no framebuffer da camada de poligonos, que
 * fica atras dos sprites e na frente dos tiles do fundo.               */
#define PL_CURSOR_H   0               /* cursor do mouse: traco horizontal    */
#define PL_CURSOR_V   1               /*                  traco vertical      */
#define PL_ESTILHACO0 2               /* 2..7: estilhacos (triangulos)        */
#define N_ESTILHACOS  6
#define PL_FURIA0     8               /* 8..9: raios de furia do professor    */
#define PL_SETA0      10              /* 10..11: setas de tutorial (1o semestre) */
#define PL_BARRA_CX   12              /* barra de lotacao da caixa            */
#define PL_GIZ        13              /* giz na lousa: tempo ate o arremesso  */
#define PL_LOUSA      14              /* lousa verde atras do professor       */
#define PL_MOLDURA    15              /* moldura de madeira da lousa          */
#define PL_CONFETE0   16              /* 16..31: confetes da formatura        */
#define N_CONFETES    16
extern const int PECA_DESENHO[N_TIPOS_MAX];   /* CPU, RAM, HD, disquete      */
extern const char *PECA_NOME[N_TIPOS_MAX];

#endif
