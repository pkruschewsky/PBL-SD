/* ============================================================================
 * menu.c - MENU para testar o coprocessador grafico sem programar
 *
 * Cada opcao vira instrucoes da NOSSA ISA, enviadas pelo DRIVER em Assembly
 * (driver_copro.s). Depois de cada acao o menu mostra as instrucoes enviadas.
 *
 * Compilar na placa (menu.c, copro.h e driver_copro.s na mesma pasta):
 *     gcc -o menu menu.c driver_copro.s
 * Rodar:
 *     sudo ./menu
 * ========================================================================== */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <sys/time.h>
#include <sys/select.h>
#include "copro.h"

static int spr_x[32], spr_y[32];      /* posicao dos sprites (para a animacao quicar) */

/* ---------------- entrada pelo teclado ---------------- */
static void le_linha(char *buf, int tam)
{
    if (!fgets(buf, tam, stdin)) { printf("\n"); copro_fecha(); exit(0); }
    buf[strcspn(buf, "\r\n")] = 0;
}

/* le um inteiro entre min e max (aceita negativo e 0x...); repete ate valer */
static int le_int(const char *pergunta, int min, int max)
{
    char buf[64], *fim;
    for (;;) {
        printf("  %s (%d a %d): ", pergunta, min, max);
        fflush(stdout);
        le_linha(buf, sizeof buf);
        long v = strtol(buf, &fim, 0);
        if (fim != buf && *fim == 0 && v >= min && v <= max) return (int)v;
        printf("    valor invalido.\n");
    }
}

static int le_cor(void)
{
    printf("  Cores: 1-vermelho 2-verde 3-azul 4-amarelo 5-branco 6-outra (RGB332)\n");
    static const int cores[] = {0xE0, 0x1C, 0x03, 0xFC, 0xFF};
    int i = le_int("cor", 1, 6);
    return (i <= 5) ? cores[i - 1] : le_int("valor RGB332 (ex.: 0xE0)", 0, 255);
}

/* ---------------- mostra as instrucoes enviadas (desmontador simples) ---------------- */
static void mostra_enviadas(void)
{
    static const char *tipos[] = {"OFF", "RECT", "TRI", "?"};
    char s[64];
    int i;
    for (i = 0; i < copro_hist_n; i++) {
        uint32_t w = copro_hist[i];
        int op = w >> 27, a = (w >> 22) & 31, b = (w >> 17) & 31, c = (w >> 12) & 31;
        switch (op) {
        case 1:  sprintf(s, "LI r%d, %d", a, (int16_t)(w & 0xFFFF)); break;
        case 7:  sprintf(s, "WAITV"); break;
        case 8:  sprintf(s, "SET_TILE %d, %d, %d", a, (w >> 16) & 63, w & 0xFF); break;
        case 9:  sprintf(s, "SET_SCROLL r%d, r%d", b, c); break;
        case 16: sprintf(s, "POLY_VTX %d, %d, r%d, r%d", a, w & 3, b, c); break;
        case 17: sprintf(s, "POLY_CFG %d, %s, 0x%02X", a, tipos[(w >> 8) & 3], w & 0xFF); break;
        case 18: sprintf(s, "POLY_MOVE %d, r%d, r%d", a, b, c); break;
        case 24: sprintf(s, "SPR_POS %d, r%d, r%d", a, b, c); break;
        case 25: sprintf(s, "SPR_ATTR %d, %d%s%s%s%s", a, w & 0xFF, (w & 0x100) ? ", EN" : "",
                         (w & 0x200) ? ", FX" : "", (w & 0x400) ? ", FY" : "", (w & 0x800) ? ", BACK" : "");
                 break;
        case 26: sprintf(s, "SPR_MOVE %d, r%d, r%d", a, b, c); break;
        default: sprintf(s, "(opcode %d)", op); break;
        }
        if (i == 0) printf("  Instrucoes enviadas:\n");
        printf("     %-28s 0x%08X\n", s, w);
    }
    copro_hist_n = 0;
}

static void erro(void)
{
    printf("  ERRO: o coprocessador nao respondeu (status = 0x%08X).\n", copro_status());
}

/* ---------------- 1 - FUNDO ---------------- */
static void menu_fundo(void)
{
    int l, c, t, x, y, r = 0;
    printf("\n--- FUNDO ---\n 1 - Trocar um tile\n 2 - Scroll\n 0 - Voltar\n");
    switch (le_int("opcao", 0, 2)) {
    case 0: return;
    case 1:
        l = le_int("linha", 0, 29); c = le_int("coluna", 0, 39);
        t = le_int("tile (160-169 digitos, 170-195 letras, 208-223 materiais)", 0, 255);
        r = copro_tile(l, c, t);
        break;
    case 2:
        x = le_int("scroll x", 0, 319); y = le_int("scroll y", 0, 239);
        r = copro_scroll(x, y);
        break;
    }
    if (r) erro();
}

/* ---------------- 2 - POLIGONOS ---------------- */
static void menu_poligonos(void)
{
    int s, x[3], y[3], i, r = 0;
    printf("\n--- POLIGONOS (4 slots; slot 0 na frente, slot 3 atras) ---\n"
           " 1 - Desenhar triangulo\n 2 - Desenhar retangulo\n 3 - Mover\n 4 - Desligar\n 0 - Voltar\n");
    int op = le_int("opcao", 0, 4);
    if (op == 0) return;
    s = le_int("slot", 0, 3);
    switch (op) {
    case 1:
        for (i = 0; i < 3; i++) {
            printf("  Vertice %d:\n", i);
            x[i] = le_int("x", 0, 319); y[i] = le_int("y", 0, 239);
        }
        r = copro_vertice(s, 0, x[0], y[0]) | copro_vertice(s, 1, x[1], y[1]) |
            copro_vertice(s, 2, x[2], y[2]) | copro_poligono(s, COPRO_TRI, le_cor());
        break;
    case 2:
        printf("  Canto superior esquerdo:\n");
        x[0] = le_int("x", 0, 318); y[0] = le_int("y", 0, 238);
        printf("  Canto inferior direito:\n");
        x[1] = le_int("x", x[0] + 1, 319); y[1] = le_int("y", y[0] + 1, 239);
        r = copro_vertice(s, 0, x[0], y[0]) | copro_vertice(s, 1, x[1], y[1]) |
            copro_poligono(s, COPRO_RECT, le_cor());
        break;
    case 3:
        x[0] = le_int("deslocamento x", -319, 319); y[0] = le_int("deslocamento y", -239, 239);
        r = copro_move_poligono(s, x[0], y[0]);
        break;
    case 4:
        r = copro_poligono(s, COPRO_OFF, 0);
        break;
    }
    if (r) erro();
}

/* ---------------- 3 - SPRITES ---------------- */
static void menu_sprites(void)
{
    int n, d, f, dx, dy, q, r = 0;
    printf("\n--- SPRITES (o de menor numero fica na frente) ---\n"
           " 1 - Configurar (posicao, desenho, espelho, prioridade)\n 2 - Mover\n"
           " 3 - Animar (1 passo por quadro, quica nas bordas)\n 4 - Desligar\n 0 - Voltar\n");
    int op = le_int("opcao", 0, 4);
    if (op == 0) return;
    n = le_int("sprite", 0, 31);
    switch (op) {
    case 1:
        spr_x[n] = le_int("x", 0, 304); spr_y[n] = le_int("y", 0, 224);
        d = le_int("desenho (ver catalogo_sprites.png)", 0, 31);
        f = COPRO_EN;
        printf("  Espelho: 0-nenhum 1-horizontal 2-vertical 3-os dois\n");
        q = le_int("espelho", 0, 3);
        if (q & 1) f |= COPRO_FX;
        if (q & 2) f |= COPRO_FY;
        printf("  Prioridade: 0-na frente dos poligonos 1-atras dos poligonos\n");
        if (le_int("prioridade", 0, 1)) f |= COPRO_BACK;
        r = copro_sprite_pos(n, spr_x[n], spr_y[n]) | copro_sprite_attr(n, d * 4, f);
        break;
    case 2:
        dx = le_int("deslocamento x", -304, 304); dy = le_int("deslocamento y", -224, 224);
        r = copro_move_sprite(n, dx, dy);
        spr_x[n] += dx; spr_y[n] += dy;
        break;
    case 3:
        dx = le_int("passo x por quadro", -8, 8); dy = le_int("passo y por quadro", -8, 8);
        q = le_int("quadros (60 = 1 segundo)", 1, 3600);
        for (; q > 0 && !r; q--) {
            /* o ARM decide quando quicar; o coprocessador faz a conta (SPR_MOVE) */
            if (spr_x[n] + dx < 0 || spr_x[n] + dx > 304) dx = -dx;
            if (spr_y[n] + dy < 0 || spr_y[n] + dy > 224) dy = -dy;
            r = copro_espera_quadro() | copro_move_sprite(n, dx, dy);   /* WAITV + SPR_MOVE */
            spr_x[n] += dx; spr_y[n] += dy;
            if (q > 1) copro_hist_n = 0;       /* mostra so as instrucoes do ultimo quadro */
        }
        copro_espera_fim();
        break;
    case 4:
        r = copro_sprite_attr(n, 0, 0);
        break;
    }
    if (r) erro();
}

/* ---------------- 6 - TESTE DA BUSCA ASSINCRONA ----------------
 * Monta uma cena com 8 sprites e 4 poligonos e manda, DE UMA VEZ, uma rajada
 * de 786 instrucoes (a fila so tem 32):
 *   6 x LI (passos +2 -2 +1 -1 +3 -3 em r3..r8)
 *   60 quadros x (WAITV + 8 SPR_MOVE + 4 POLY_MOVE)
 * Nos 30 primeiros quadros tudo anda para um lado; nos 30 ultimos volta.
 * Cada WAITV segura a UC ate o proximo quadro, entao o coprocessador leva ~1 s,
 * enquanto o ARM envia muito mais rapido. O teste mede o tempo e le o contador
 * da fila (status[21:16]) para mostrar:
 *   1. a fila enchendo enquanto a UC esta parada no WAITV;
 *   2. o ARM esperando quando a fila fica cheia (so manda quando abre espaco);
 *   3. o ARM terminando de enviar com a fila ainda cheia de instrucoes;
 *   4. o coprocessador esvaziando a fila SOZINHO, no ritmo dele.          */
static double agora_ms(void)
{
    struct timeval t;
    gettimeofday(&t, NULL);
    return t.tv_sec * 1000.0 + t.tv_usec / 1000.0;
}

/* registrador do coprocessador que guarda cada passo (r0 = 0) */
static int reg_passo(int v)
{
    switch (v) {
    case 2:  return 3;  case -2: return 4;
    case 1:  return 5;  case -1: return 6;
    case 3:  return 7;  case -3: return 8;
    default: return 0;
    }
}

/* sprites: posicao inicial, desenho, passo (dx, dy) na ida */
static const int SP[8][5] = {
        { 40,  40, 20,  2,  0}, {260,  40, 21, -2,  0}, {100,  30, 22,  0,  2}, {200, 190, 23,  0, -2},
        { 60, 110, 25,  2,  2}, {240, 100, 29, -2,  2}, {120, 150, 28,  3, -1}, {190, 140,  1, -3, -1},
};
/* poligonos: passo (dx, dy) na ida */
static const int PP[4][2] = {{1, 0}, {0, 1}, {-1, 0}, {0, -1}};
#define QUADROS_CICLO 60          /* 30 quadros de ida + 30 de volta */

/* envia o quadro q do ciclo: WAITV + 8 SPR_MOVE + 4 POLY_MOVE (13 instrucoes) */
static int envia_quadro(int q)
{
    int k, r, sinal = (q % QUADROS_CICLO < QUADROS_CICLO / 2) ? 1 : -1;   /* ida / volta */
    r = copro_espera_quadro();                                            /* WAITV */
    for (k = 0; k < 8; k++) {                                             /* SPR_MOVE k, rdx, rdy */
        r |= copro_envia(ISA_SPR_MOVE(k, reg_passo(sinal * SP[k][3]), reg_passo(sinal * SP[k][4])));
        spr_x[k] += sinal * SP[k][3];
        spr_y[k] += sinal * SP[k][4];
    }
    for (k = 0; k < 4; k++)                                               /* POLY_MOVE k, rdx, rdy */
        r |= copro_envia(ISA_POLY_MOVE(k, reg_passo(sinal * PP[k][0]), reg_passo(sinal * PP[k][1])));
    copro_hist_n = 0;
    return r;
}

/* 1 se o usuario apertou Enter (sem travar esperando) */
static int enter_apertado(void)
{
    fd_set fds;
    struct timeval zero = {0, 0};
    FD_ZERO(&fds);
    FD_SET(0, &fds);
    return select(1, &fds, NULL, NULL, &zero) > 0;
}

static void teste_assincrono(void)
{
    const int QUADROS = QUADROS_CICLO;
    char buf[64];
    int i, k, q, enviadas, fila, ja_cheia = 0, r = 0;
    double t0, t;
    uint32_t st;

    printf("\n--- TESTE DA BUSCA ASSINCRONA (FIFO de 32 instrucoes) ---\n"
           "  Montando a cena: 8 sprites e 4 poligonos...\n");
    copro_reinicia();
    for (k = 0; k < 8; k++) {
        spr_x[k] = SP[k][0]; spr_y[k] = SP[k][1];
        r |= copro_sprite_pos(k, SP[k][0], SP[k][1]) | copro_sprite_attr(k, SP[k][2] * 4, COPRO_EN);
    }
    r |= copro_vertice(0, 0, 30, 165) | copro_vertice(0, 1, 10, 205) | copro_vertice(0, 2, 50, 205)
       | copro_poligono(0, COPRO_TRI, 0xE0);                                       /* triangulo vermelho */
    r |= copro_vertice(1, 0, 130, 55) | copro_vertice(1, 1, 190, 95) | copro_poligono(1, COPRO_RECT, 0x03);
    r |= copro_vertice(2, 0, 290, 165) | copro_vertice(2, 1, 270, 205) | copro_vertice(2, 2, 310, 205)
       | copro_poligono(2, COPRO_TRI, 0x1C);                                       /* triangulo verde    */
    r |= copro_vertice(3, 0, 130, 200) | copro_vertice(3, 1, 190, 230) | copro_poligono(3, COPRO_RECT, 0xFC);
    r |= copro_espera_fim();
    copro_hist_n = 0;
    if (r) { erro(); return; }

    printf("  Agora o ARM manda DE UMA VEZ %d instrucoes (a fila so tem 32):\n"
           "  6 x LI + %d quadros x (WAITV + 8 SPR_MOVE + 4 POLY_MOVE)\n"
           "  -> tudo anda por meio segundo e volta (~1 s no total)\n\n", 6 + 13 * QUADROS, QUADROS);

    printf("  ARM ENVIANDO:\n");
    t0 = agora_ms();
    r |= copro_li(3, 2) | copro_li(4, -2) | copro_li(5, 1) | copro_li(6, -1) | copro_li(7, 3) | copro_li(8, -3);
    enviadas = 6;
    for (q = 0; q < QUADROS && !r; q++) {
        r |= envia_quadro(q);
        enviadas += 13;
        st = copro_status();
        fila = COPRO_FILA(st);
        t = agora_ms() - t0;
        if (q < 2 || (fila >= 30 && !ja_cheia) || q % 10 == 9)
            printf("     t = %6.1f ms   enviadas %3d   na fila %2d%s\n", t, enviadas, fila,
                   (fila >= 30 && !ja_cheia) ? "   <- fila cheia: o ARM passa a esperar abrir espaco" : "");
        if (fila >= 30) ja_cheia = 1;
    }
    copro_hist_n = 0;
    if (r) { erro(); return; }

    st = copro_status();
    printf("\n  O ARM TERMINOU de enviar em %.1f ms, mas a fila ainda tem %d instrucoes\n"
           "  esperando: o coprocessador vai executa-las sozinho, sem o ARM.\n\n"
           "  COPROCESSADOR EXECUTANDO (o ARM so observa o status):\n", agora_ms() - t0, COPRO_FILA(st));
    for (i = 0; i < 400; i++) {
        st = copro_status();
        if (i % 2 == 0 || (st & COPRO_ST_DONE))
            printf("     t = %6.1f ms   na fila %2d   busy %d   done %d\n", agora_ms() - t0,
                   COPRO_FILA(st), !!(st & COPRO_ST_BUSY), !!(st & COPRO_ST_DONE));
        if (st & COPRO_ST_DONE) break;
        usleep(10000);
    }
    printf("\n  Conclusao: o ARM e a unidade de controle trabalham em ritmos diferentes.\n"
           "  A FIFO guarda as instrucoes; a UC busca a proxima quando termina a anterior\n"
           "  (busca ASSINCRONA). Com a fila cheia, o ARM espera (bit full do status).\n");

    /* ---- continua em loop ate apertar Enter ---- */
    printf("\n  Agora a cena fica em movimento. Aperte Enter para parar.\n");
    fflush(stdout);
    for (q = 0; !r; q++) {
        if (q % QUADROS_CICLO == 0 && enter_apertado()) break;   /* para no fim de um ciclo */
        r |= envia_quadro(q);
    }
    if (r) { erro(); return; }
    le_linha(buf, sizeof buf);                                    /* consome o Enter */
    copro_espera_fim();
    printf("  Parado (%d ciclos de ida e volta).\n", q / QUADROS_CICLO);
}

/* ---------------- MAIN ---------------- */
int main(void)
{
    char buf[64], *fim;
    int r = copro_abre();
    if (r == -1) { printf("ERRO: nao abriu /dev/mem (rode com sudo)\n"); return 1; }
    if (r != 0)  { printf("ERRO: mmap da ponte falhou\n"); return 1; }

    for (;;) {
        uint32_t st = copro_status();
        printf("\n===== COPROCESSADOR GRAFICO - PBL2 =====  status 0x%08X%s\n", st,
               (st & COPRO_ST_ERR) ? "  (err = 1: recebeu opcode invalido)" : "");
        printf(" 1 - Fundo\n 2 - Poligonos\n 3 - Sprites\n 4 - Reiniciar coprocessador\n"
               " 5 - Enviar instrucao em hexadecimal\n 6 - Teste da busca assincrona (encher a fila)\n"
               " 0 - Sair\n");
        switch (le_int("opcao", 0, 6)) {
        case 0:
            copro_fecha();
            return 0;
        case 1: menu_fundo(); break;
        case 2: menu_poligonos(); break;
        case 3: menu_sprites(); break;
        case 4:
            copro_reinicia();
            printf("  Reiniciado: sprites e poligonos desligados, scroll 0, fundo original.\n");
            break;
        case 5:
            printf("  palavra de 32 bits em hex (ex.: C014B000): ");
            fflush(stdout);
            le_linha(buf, sizeof buf);
            {
                unsigned long w = strtoul(buf, &fim, 16);
                if (fim == buf || *fim) { printf("    valor invalido.\n"); break; }
                if (copro_envia((uint32_t)w)) erro();
                copro_espera_fim();
            }
            break;
        case 6:
            teste_assincrono();
            break;
        }
        mostra_enviadas();
    }
}
