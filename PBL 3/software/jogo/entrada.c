/* ============================================================================
 * entrada.c - teclado e mouse USB pelo /dev/input, cada um na sua THREAD
 *
 * O programa tem tres threads:
 *   - thread do TECLADO: dorme ate chegar um evento de tecla, le e anota no
 *     estado compartilhado (tecla segurada / tecla apertada);
 *   - thread do MOUSE:   dorme ate o mouse mexer ou clicar, le e anota
 *     (posicao do cursor / clique);
 *   - thread PRINCIPAL (jogo.c): a cada quadro chama entrada_le(), que copia
 *     o estado compartilhado e zera os "apertou" ja entregues ao jogo.
 *
 * As tres mexem nas mesmas variaveis, entao todo acesso e feito com a trava
 * (mutex) fechada: quem chega depois espera alguns microssegundos. Assim um
 * clique nunca e apagado no meio da copia e o jogo nunca le um x novo com um
 * y antigo. Teclado e mouse usados ao mesmo tempo chegam juntos no mesmo
 * quadro: cada thread anota o seu evento e o jogo copia os dois.
 *
 * Somente a thread principal fala com o driver do coprocessador: o
 * handshake valid/ack nao pode ser usado por duas threads ao mesmo tempo.
 *
 * Cada evento recebe a hora em que chegou; o jogo.c usa essa hora para
 * medir o tempo de resposta (requisito do PBL03: no maximo 100 ms).
 *
 * Deteccao dos dispositivos: examina /dev/input/event0..31 e pergunta a cada
 * um (ioctl EVIOCGBIT) o que ele e:
 *   - mouse:   movimento relativo (EV_REL) e botao esquerdo;
 *   - teclado: tem a tecla ESPACO.
 * Alguns teclados USB aparecem como mais de um dispositivo (teclas comuns e
 * teclas multimidia); por isso a thread do teclado vigia todos os teclados
 * achados com poll(), e a do mouse, todos os mouses.
 * ========================================================================== */
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <poll.h>
#include <pthread.h>
#include <sys/time.h>
#include <linux/input.h>
#include "jogo.h"

#define MAX_DEV 8

typedef struct {                      /* dispositivos vigiados por uma thread */
    int fd[MAX_DEV];
    int n;
    int eh_mouse;
} Grupo;

static Grupo teclados = {{0}, 0, 0};
static Grupo mouses   = {{0}, 0, 1};
static pthread_t th_teclado, th_mouse;
static int tem_th_teclado, tem_th_mouse;
static volatile int rodando;

/* ---------------- estado compartilhado (sempre com a trava) ---------------- */
static pthread_mutex_t trava = PTHREAD_MUTEX_INITIALIZER;

static unsigned char segurada[KEY_MAX + 1];   /* tecla segurada agora         */
static int  cur_x = TELA_W / 2, cur_y = TELA_H / 2;
static int  apertou_pulo, apertou_enter, apertou_pausa, apertou_reinicia,
            apertou_sair, apertou_pula_fase, apertou_clique;
static double t_evento_ms;            /* chegada do 1o evento ainda nao lido  */

static double agora_ms(void)
{
    struct timeval t;
    gettimeofday(&t, NULL);
    return t.tv_sec * 1000.0 + t.tv_usec / 1000.0;
}

#define TEM_BIT(mapa, bit) ((mapa)[(bit) / 8] & (1 << ((bit) % 8)))

/* ---------------- tratamento de um evento (chamado COM a trava) ---------- */
static void evento_teclado(const struct input_event *ev)
{
    if (ev->type != EV_KEY || ev->code > KEY_MAX) return;
    if (ev->value == 1) {                                 /* tecla desceu     */
        switch (ev->code) {
        case KEY_SPACE: apertou_pulo = 1;      break;
        case KEY_ENTER: apertou_enter = 1;     break;
        case KEY_P:     apertou_pausa = 1;     break;
        case KEY_R:     apertou_reinicia = 1;  break;
        case KEY_F:     apertou_pula_fase = 1; break;
        case KEY_ESC:
        case KEY_Q:     apertou_sair = 1;      break;
        default: break;
        }
        if (t_evento_ms == 0) t_evento_ms = agora_ms();
    }
    if (ev->value != 2)                                   /* 2 = repeticao    */
        segurada[ev->code] = (ev->value == 1);
}

static void evento_mouse(const struct input_event *ev)
{
    if (ev->type == EV_REL) {
        if (ev->code == REL_X) cur_x += ev->value;
        if (ev->code == REL_Y) cur_y += ev->value;
        if (cur_x < 0) cur_x = 0;
        if (cur_x > TELA_W - 1) cur_x = TELA_W - 1;
        if (cur_y < 0) cur_y = 0;
        if (cur_y > TELA_H - 1) cur_y = TELA_H - 1;
    }
    if (ev->type == EV_KEY && ev->code == BTN_LEFT && ev->value == 1) {
        apertou_clique = 1;
        if (t_evento_ms == 0) t_evento_ms = agora_ms();
    }
}

/* ---------------- corpo das threads do teclado e do mouse ---------------- */
static void *laco_entrada(void *arg)
{
    Grupo *g = (Grupo *)arg;
    struct pollfd pf[MAX_DEV];
    struct input_event ev;
    int i;

    for (i = 0; i < g->n; i++) { pf[i].fd = g->fd[i]; pf[i].events = POLLIN; }

    while (rodando) {
        /* dorme ate chegar evento (no maximo 100 ms, para ver se deve parar) */
        if (poll(pf, g->n, 100) <= 0) continue;

        pthread_mutex_lock(&trava);                       /* fecha a trava    */
        for (i = 0; i < g->n; i++)
            if (pf[i].revents & POLLIN)
                while (read(g->fd[i], &ev, sizeof ev) == sizeof ev) {
                    if (g->eh_mouse) evento_mouse(&ev);
                    else             evento_teclado(&ev);
                }
        pthread_mutex_unlock(&trava);                     /* abre a trava     */
    }
    return NULL;
}

/* ---------------- interface usada pelo jogo ---------------- */
int entrada_abre(void)
{
    char nome[32];
    unsigned char tipos[(EV_MAX + 7) / 8], teclas[(KEY_MAX + 7) / 8];
    int i, fd;

    teclados.n = mouses.n = 0;
    for (i = 0; i < 32; i++) {
        snprintf(nome, sizeof nome, "/dev/input/event%d", i);
        fd = open(nome, O_RDONLY | O_NONBLOCK);
        if (fd < 0) continue;

        memset(tipos, 0, sizeof tipos);
        memset(teclas, 0, sizeof teclas);
        ioctl(fd, EVIOCGBIT(0, sizeof tipos), tipos);
        ioctl(fd, EVIOCGBIT(EV_KEY, sizeof teclas), teclas);

        if (TEM_BIT(tipos, EV_REL) && TEM_BIT(teclas, BTN_LEFT) && mouses.n < MAX_DEV)
            mouses.fd[mouses.n++] = fd;
        else if (TEM_BIT(tipos, EV_KEY) && TEM_BIT(teclas, KEY_SPACE) && teclados.n < MAX_DEV)
            teclados.fd[teclados.n++] = fd;
        else
            close(fd);
    }
    printf("entrada: %d teclado(s), %d mouse(s)\n", teclados.n, mouses.n);
    if (teclados.n == 0) return -1;   /* da para jogar sem mouse, nao sem teclado */

    rodando = 1;
    if (pthread_create(&th_teclado, NULL, laco_entrada, &teclados) != 0) {
        printf("entrada: nao conseguiu criar a thread do teclado\n");
        rodando = 0;
        return -1;
    }
    tem_th_teclado = 1;
    if (mouses.n > 0) {
        if (pthread_create(&th_mouse, NULL, laco_entrada, &mouses) == 0)
            tem_th_mouse = 1;
        else
            printf("entrada: sem thread do mouse (o jogo segue so com o teclado)\n");
    }
    return 0;
}

void entrada_fecha(void)
{
    int i;
    rodando = 0;                      /* as threads saem em ate 100 ms        */
    if (tem_th_teclado) pthread_join(th_teclado, NULL);
    if (tem_th_mouse)   pthread_join(th_mouse, NULL);
    tem_th_teclado = tem_th_mouse = 0;
    for (i = 0; i < teclados.n; i++) close(teclados.fd[i]);
    for (i = 0; i < mouses.n; i++)   close(mouses.fd[i]);
    teclados.n = mouses.n = 0;
}

/* thread principal: copia o estado para o quadro atual e zera o que ja foi
 * entregue. Tudo com a trava fechada, para nenhuma das outras duas threads
 * escrever no meio da copia. */
void entrada_le(Entrada *e)
{
    pthread_mutex_lock(&trava);
    e->pulo      = apertou_pulo;
    e->enter     = apertou_enter;
    e->pausa     = apertou_pausa;
    e->reinicia  = apertou_reinicia;
    e->sair      = apertou_sair;
    e->pula_fase = apertou_pula_fase;
    e->clique    = apertou_clique;
    apertou_pulo = apertou_enter = apertou_pausa = apertou_reinicia = 0;
    apertou_sair = apertou_pula_fase = apertou_clique = 0;

    e->esq   = segurada[KEY_LEFT]  | segurada[KEY_A];
    e->dir   = segurada[KEY_RIGHT] | segurada[KEY_D];
    e->cima  = segurada[KEY_UP]    | segurada[KEY_W];
    e->baixo = segurada[KEY_DOWN]  | segurada[KEY_S];
    e->mouse_x = cur_x;
    e->mouse_y = cur_y;

    /* hora do 1o evento deste quadro (0 = nenhum), para medir a resposta */
    e->t_evento_ms = t_evento_ms;
    t_evento_ms = 0;
    pthread_mutex_unlock(&trava);
}
