/* ============================================================================
 * jogo.c - RUMO AO DIPLOMA: estados, laco principal e envio da cena
 *
 * Papel de cada camada (arquitetura do PBL03):
 *   jogo.c / logica.c / fase.c / entrada.c  -> aplicacao em C (este programa)
 *   driver_copro.s (copro.h)                -> driver em Assembly ARM (MMIO)
 *   coprocessador na FPGA                   -> desenha a cena no VGA
 *
 * Laco principal (60 quadros/s, cadenciado pelo WAITV do coprocessador):
 *   entrada_le() -> logica_passo() -> envia so o que mudou -> espera o vblank
 *
 * Maquina de estados: ABERTURA -> MENU -> PARTIDA <-> PAUSA -> FIM -> MENU
 *   FIM tem dois finais: REPROVADO (vidas acabaram ou caixa lotou) e
 *   FORMADO (pegou o diploma do 10o semestre).
 *
 * Medidas para o relatorio (impressas no terminal ao sair):
 *   - latencia media de envio de um comando (medida com 2000 NOPs);
 *   - taxa de atualizacao da logica (quadros por segundo);
 *   - tempo de resposta a entrada (do evento ate a cena enviada);
 *   - uso de CPU do processo (tempo de CPU / tempo de relogio).
 *
 * Threads: o teclado e o mouse sao lidos cada um na sua thread (entrada.c).
 * Esta thread principal faz a logica e e a UNICA que chama o driver do
 * coprocessador.
 * ========================================================================== */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <sys/resource.h>
#include "copro.h"
#include "jogo.h"

/* ---------------- medidas ---------------- */
static double agora_ms(void)
{
    struct timeval t;
    gettimeofday(&t, NULL);
    return t.tv_sec * 1000.0 + t.tv_usec / 1000.0;
}

static double lat_envio_us;           /* latencia media de 1 comando          */
static double resp_soma_ms, resp_max_ms;   /* tempo de resposta a entrada     */
static long   resp_n;
static int    fps_atual = 60;         /* quadros/s medidos (janela de 2 s)    */
static long   quadros_total;
static double t_inicio_ms;

static void mede_latencia(void)
{
    double t0 = agora_ms();
    int i;
    for (i = 0; i < 2000; i++)
        copro_envia(0);               /* NOP                                  */
    copro_espera_fim();
    lat_envio_us = (agora_ms() - t0) * 1000.0 / 2000.0;
    printf("latencia media de envio: %.1f us por comando\n", lat_envio_us);
}

/* ---------------- envio da cena (so o que mudou) ---------------- */
static int attr_antes[32];            /* ultimo SPR_ATTR enviado por sprite   */
static int poco_antes[POCO_COLS][POCO_LINS];

static void sprite_attr(int n, int desenho, int flags)
{
    int v = (desenho << 8) | flags;
    if (attr_antes[n] == v) return;
    attr_antes[n] = v;
    copro_sprite_attr(n, desenho * 4, flags);
}

static void esconde_sprite(int n) { sprite_attr(n, 0, 0); }

static void cena_reseta(void)         /* forca reenviar tudo no proximo quadro */
{
    int i;
    for (i = 0; i < 32; i++) attr_antes[i] = -1;
    memset(poco_antes, 0xFF, sizeof poco_antes);
}

/* professor de 32x32 = 4 sprites: sup. esq., sup. dir., inf. esq., inf. dir. */
static void professor_envia(int x, int y, int arremessando)
{
    int base = arremessando ? DES_PROF_ARREMESSA : DES_PROF_PARADO, q;
    for (q = 0; q < 4; q++) {
        sprite_attr(SPR_PROF0 + q, base + q, COPRO_EN);
        copro_sprite_pos(SPR_PROF0 + q, x + 16 * (q % 2), y + 16 * (q / 2));
    }
}

static void cena_envia(const Entrada *e)
{
    int i, c, l;
    const Aluno *h = &J.aluno;

    /* aluno (pisca enquanto invulneravel); troca o desenho a cada 8 quadros
       quando esta andando ou subindo a escada */
    if (h->invulneravel > 0 && (J.quadro / 4) % 2)
        esconde_sprite(SPR_ALUNO);
    else if (h->na_escada)
        sprite_attr(SPR_ALUNO, DES_ALUNO_ESCADA,
                    COPRO_EN | ((h->andando && (J.quadro / 8) % 2) ? COPRO_FX : 0));
    else
        sprite_attr(SPR_ALUNO,
                    (h->andando && (J.quadro / 8) % 2) ? DES_ALUNO_ANDA : DES_ALUNO_PARADO,
                    COPRO_EN | (h->olhando_esq ? COPRO_FX : 0));
    copro_sprite_pos(SPR_ALUNO, (int)h->x, (int)h->y);

    /* professor: 4 sprites de 16x16 formando um desenho de 32x32 */
    professor_envia((int)J.prof_x, PROF_Y, J.prof_arremessa > 0);

    /* diploma no fim da viga do topo */
    sprite_attr(SPR_DIPLOMA, DES_DIPLOMA, COPRO_EN);
    copro_sprite_pos(SPR_DIPLOMA, DIPLOMA_X, VIGA_Y[N_VIGAS - 1] - 16);

    /* pecas rolando */
    for (i = 0; i < MAX_PECAS; i++) {
        const Peca *g = &J.peca[i];
        if (!g->ativa) { esconde_sprite(SPR_PECA0 + i); continue; }
        sprite_attr(SPR_PECA0 + i, PECA_DESENHO[g->tipo], COPRO_EN);
        copro_sprite_pos(SPR_PECA0 + i, (int)g->x, (int)g->y);
    }

    /* caixa de componentes: um sprite parado por celula */
    for (c = 0; c < POCO_COLS; c++)
        for (l = 0; l < POCO_LINS; l++) {
            int n = SPR_POCO0 + c * POCO_LINS + l;
            if (J.poco[c][l] == poco_antes[c][l]) continue;
            poco_antes[c][l] = J.poco[c][l];
            if (J.poco[c][l] < 0)
                esconde_sprite(n);
            else {
                copro_sprite_pos(n, POCO_X + 16 * c, POCO_Y_BASE - 16 * (l + 1));
                sprite_attr(n, PECA_DESENHO[J.poco[c][l]], COPRO_EN);
            }
        }

    /* faisca (peca desmontada ou grupo eliminado na caixa) */
    if (J.explosao_t > 0) {
        sprite_attr(SPR_FAISCA, DES_FAISCA, COPRO_EN);
        copro_sprite_pos(SPR_FAISCA, J.explosao_x - 8, J.explosao_y - 8);
    } else
        esconde_sprite(SPR_FAISCA);

    efeitos_quadro(e->mouse_x, e->mouse_y);   /* poligonos (efeitos.c)    */
    hud_atualiza();
    copro_hist_n = 0;
}

/* ---------------- telas fixas ---------------- */
static void limpa_tela(void)
{
    int l, c;
    for (l = 0; l < 30; l++)
        for (c = 0; c < 40; c++)
            copro_tile(l, c, 222);    /* preto                                */
}

static void esconde_tudo(void)
{
    int i;
    for (i = 0; i < 32; i++) esconde_sprite(i);
    efeitos_desliga_todos();
}

static void tela_abertura(void)
{
    limpa_tela();
    esconde_tudo();
    texto(3, 13, "RUMO AO DIPLOMA");
    texto(12, 4, "O PROFESSOR ESTA ARREMESSANDO PECAS");
    texto(14, 5, "SUBA A TORRE E PEGUE O DIPLOMA!");
    texto(17, 5, "3 PECAS IGUAIS NA CAIXA SOMEM");
    texto(25, 14, "APERTE ENTER");
    professor_envia(144, 48, 1);
    sprite_attr(SPR_ALUNO, DES_ALUNO_PARADO, COPRO_EN);
    copro_sprite_pos(SPR_ALUNO, 112, 160);
    sprite_attr(SPR_DIPLOMA, DES_DIPLOMA, COPRO_EN);
    copro_sprite_pos(SPR_DIPLOMA, 192, 160);
}

static void tela_menu(void)
{
    limpa_tela();
    esconde_tudo();
    cursor_liga();
    texto(6, 13, "RUMO AO DIPLOMA");
    texto(14, 17, "INICIAR");
    texto(17, 17, "SAIR");
    texto(24, 4, "SETAS E ENTER OU CLIQUE DO MOUSE");
}

static void menu_marca(void)
{
    texto(14, 15, J.opcao_menu == 0 ? "-" : " ");
    texto(17, 15, J.opcao_menu == 1 ? "-" : " ");
}

static void entra_na_fase(void)
{
    fase_desenha(J.fase);
    cena_reseta();
    esconde_tudo();
    efeitos_nova_fase();              /* lousa, cursor e efeitos zerados      */
}

static void tela_pausa(void)
{
    texto(13, 17, "PAUSA");
    texto(15, 6, "P CONTINUA  R REINICIA  Q SAIR");
    texto(21, 4, "F PULA O SEMESTRE - DEMONSTRACAO");
    {
        char s[40];
        snprintf(s, sizeof s, "TAXA %d QPS  ENVIO %d US", fps_atual, (int)lat_envio_us);
        texto(17, 8, s);
        snprintf(s, sizeof s, "RESPOSTA MEDIA %d MS",
                resp_n ? (int)(resp_soma_ms / resp_n + 0.5) : 0);
        texto(19, 4, s);
    }
}

static void tela_fim(const char *motivo)
{
    char s[40];
    limpa_tela();
    esconde_tudo();
    texto(8, 15, "REPROVADO!");
    texto(11, (40 - (int)strlen(motivo)) / 2, motivo);
    snprintf(s, sizeof s, "PONTOS: %06ld", J.pontos);
    texto(14, 13, s);
    snprintf(s, sizeof s, "SEMESTRE ALCANCADO: %d", J.fase);
    texto(16, 9, s);
    texto(22, 13, "APERTE ENTER");
}

static void tela_aprovado(void);

/* zerou o jogo: tela de formatura com confetes (animados no estado FIM) */
static void tela_formado(void)
{
    char s[40];
    limpa_tela();
    esconde_tudo();
    texto(3, 15, "PARABENS!");
    texto(5, 7, "VOCE CONCLUIU OS 10 SEMESTRES");
    texto(7, 14, "E SE FORMOU!");
    /* palco: retangulo de madeira com o aluno e o diploma em cima */
    copro_vertice(PL_MOLDURA, 0, 100, 128);
    copro_vertice(PL_MOLDURA, 1, 220, 140);
    copro_poligono(PL_MOLDURA, COPRO_RECT, 0x68);
    professor_envia(104, 96, 0);
    sprite_attr(SPR_ALUNO, DES_ALUNO_PARADO, COPRO_EN);
    copro_sprite_pos(SPR_ALUNO, 160, 112);
    sprite_attr(SPR_DIPLOMA, DES_DIPLOMA, COPRO_EN);
    copro_sprite_pos(SPR_DIPLOMA, 180, 112);
    snprintf(s, sizeof s, "PONTOS: %06ld", J.pontos);
    texto(20, 13, s);
    snprintf(s, sizeof s, "VIDAS RESTANTES: %d", J.vidas);
    texto(22, 11, s);
    texto(26, 14, "APERTE ENTER");
    confetes_inicia();
}

/* pegou o diploma: no ultimo semestre forma; nos outros, passa de semestre */
static void conclui_semestre(void)
{
    J.pontos += 1000L * J.fase;
    if (J.fase >= N_SEMESTRES) {
        J.formado = 1;
        J.estado = FIM;
        tela_formado();
        return;
    }
    tela_aprovado();
    J.fase++;
    logica_nova_fase();
    entra_na_fase();
}

/* pegou o diploma: mensagem por 2 s antes do proximo semestre */
static void tela_aprovado(void)
{
    char s[40];
    int q;
    snprintf(s, sizeof s, "APROVADO NO %d SEMESTRE!", J.fase);
    texto(13, (40 - (int)strlen(s)) / 2, s);
    for (q = 0; q < 120; q++) {
        copro_espera_quadro();
        copro_hist_n = 0;
    }
}

/* ---------------- principal ---------------- */
int main(void)
{
    Entrada e;
    double t_fps = 0;
    int quadros_fps = 0, r;

    r = copro_abre();
    if (r == -1) { printf("ERRO: nao abriu /dev/mem (rode com sudo)\n"); return 1; }
    if (r != 0)  { printf("ERRO: mmap da ponte falhou\n"); return 1; }
    if (entrada_abre() != 0) {
        printf("ERRO: nenhum teclado encontrado em /dev/input\n"
               "      (rode com sudo e confira o teclado USB)\n");
        copro_fecha();
        return 1;
    }

    copro_reinicia();
    mede_latencia();
    srand((unsigned)agora_ms());

    J.estado = ABERTURA;
    tela_abertura();
    t_inicio_ms = t_fps = agora_ms();

    for (;;) {
        entrada_le(&e);

        switch (J.estado) {
        case ABERTURA:
            if (e.enter || e.clique) { J.estado = MENU; tela_menu(); menu_marca(); }
            if (e.sair) goto fim;
            break;

        case MENU:
            if (e.cima || e.baixo) { J.opcao_menu ^= 1; menu_marca(); }
            if (e.mouse_y >= 108 && e.mouse_y < 126 && J.opcao_menu != 0) {
                J.opcao_menu = 0; menu_marca();
            }
            if (e.mouse_y >= 132 && e.mouse_y < 150 && J.opcao_menu != 1) {
                J.opcao_menu = 1; menu_marca();
            }
            cursor_envia(e.mouse_x, e.mouse_y);
            if (e.enter || e.clique) {
                if (J.opcao_menu == 1) goto fim;
                logica_nova_partida();
                entra_na_fase();
                J.estado = PARTIDA;
            }
            if (e.sair) goto fim;
            break;

        case PARTIDA:
            if (e.pausa) { J.estado = PAUSA; tela_pausa(); break; }
            if (e.sair)  { J.estado = FIM; tela_fim("PARTIDA ENCERRADA"); break; }

            switch (logica_passo(&e)) {
            case 1:                                   /* perdeu uma vida      */
                if (--J.vidas <= 0) {
                    J.estado = FIM;
                    tela_fim("AS VIDAS ACABARAM");
                } else
                    logica_perdeu_vida();
                break;
            case 2:                                   /* pegou o diploma      */
                conclui_semestre();
                break;
            case 3:                                   /* caixa lotou          */
                J.estado = FIM;
                tela_fim("A CAIXA DE COMPONENTES LOTOU");
                break;
            default:
                cena_envia(&e);
            }
            break;

        case PAUSA:
            if (e.pausa) {                            /* volta ao jogo        */
                entra_na_fase();
                J.estado = PARTIDA;
            }
            if (e.reinicia) {
                logica_nova_partida();
                entra_na_fase();
                J.estado = PARTIDA;
            }
            if (e.pula_fase) {                        /* demonstracao         */
                J.estado = PARTIDA;
                conclui_semestre();
                break;
            }
            if (e.sair) { J.estado = FIM; tela_fim("PARTIDA ENCERRADA"); }
            break;

        case FIM:
            if (J.formado) confetes_passo(quadros_total);   /* festa da formatura */
            if (e.enter || e.clique) {
                J.formado = 0;
                J.estado = MENU; tela_menu(); menu_marca();
            }
            if (e.sair) goto fim;
            break;
        }

        /* tempo de resposta: do evento chegar (thread de entrada) ate a cena
           que reage a ele estar entregue ao coprocessador */
        if (e.t_evento_ms > 0) {
            double r = agora_ms() - e.t_evento_ms;
            resp_soma_ms += r;
            resp_n++;
            if (r > resp_max_ms) resp_max_ms = r;
        }

        /* cadencia: espera o inicio do proximo quadro de video (60 Hz) */
        copro_espera_quadro();
        copro_hist_n = 0;
        quadros_total++;

        if (++quadros_fps >= 120) {                   /* taxa medida (2 s)    */
            double t = agora_ms();
            fps_atual = (int)(quadros_fps * 1000.0 / (t - t_fps) + 0.5);
            t_fps = t;
            quadros_fps = 0;
        }
    }

fim:
    {
        double total_s = (agora_ms() - t_inicio_ms) / 1000.0;
        struct rusage ru;
        getrusage(RUSAGE_SELF, &ru);
        double cpu_s = ru.ru_utime.tv_sec + ru.ru_utime.tv_usec / 1e6
                     + ru.ru_stime.tv_sec + ru.ru_stime.tv_usec / 1e6;
        printf("\n--- medidas da sessao (para o relatorio) ---\n");
        printf("tempo total:            %.1f s\n", total_s);
        printf("quadros processados:    %ld (%.1f por segundo)\n",
               quadros_total, total_s > 0 ? quadros_total / total_s : 0);
        printf("latencia media de envio: %.1f us por comando\n", lat_envio_us);
        if (resp_n > 0)
            printf("resposta a entrada:     media %.1f ms, pior %.1f ms (%ld eventos)\n",
                   resp_soma_ms / resp_n, resp_max_ms, resp_n);
        printf("uso de CPU do processo: %.1f%% de um nucleo\n",
               total_s > 0 ? 100.0 * cpu_s / total_s : 0);
    }
    entrada_fecha();                  /* para a thread de entrada primeiro    */
    copro_reinicia();
    copro_fecha();
    return 0;
}
