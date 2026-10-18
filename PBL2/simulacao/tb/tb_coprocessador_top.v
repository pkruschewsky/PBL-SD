// ============================================================================
// tb_coprocessador_top.v
// Testbench de INTEGRACAO do coprocessador completo:
//   ARM simulado -> PIOs -> nucleo -> motores -> compositor -> VGA
//
// Como funciona:
//   1. Um "ARM" envia programas na ISA pelo handshake real (valid/ack).
//   2. O testbench CAPTURA o quadro que sai para o monitor (640x480 pixels
//      fisicos, olhando a saida do compositor alinhada com a coordenada).
//   3. Um MODELO DE REFERENCIA, escrito de forma independente, calcula qual
//      deveria ser a cor de cada pixel (fundo pelas ROMs, triangulos pela
//      funcao de aresta, sprites pela ROM de sprites, prioridades).
//   4. Compara pixel a pixel. Qualquer diferenca (camada desalinhada,
//      prioridade errada, sprite fora do lugar) aparece como erro.
//   5. Salva cada quadro em quadro_N.ppm (imagem) para inspecao visual.
//
// Rodar (na pasta simulacao, com os .hex de sim_modelos/ copiados para ela):
//   comando completo na secao 10.4 do README.
// ============================================================================
`timescale 1ns/1ps
module tb_coprocessador_top;

    reg CLOCK_50 = 0;
    always #10 CLOCK_50 = ~CLOCK_50;          // 50 MHz (o PIO tambem roda nesse clock)

    reg         reset_externo = 1;
    reg  [31:0] pio_instr = 0;
    reg  [1:0]  pio_ctrl = 0;
    wire [31:0] pio_status;
    wire [7:0]  R, G, B;
    wire        HS, VS, VCLK, SYNC_N, BLANK_N;
    wire [31:0] dbg_ir;
    wire [15:0] dbg_quadros;

    coprocessador_top dut (
        .CLOCK_50(CLOCK_50), .reset_externo(reset_externo),
        .pio_instr(pio_instr), .pio_ctrl(pio_ctrl), .pio_status(pio_status),
        .VGA_R(R), .VGA_G(G), .VGA_B(B), .VGA_HS(HS), .VGA_VS(VS),
        .VGA_CLK(VCLK), .VGA_SYNC_N(SYNC_N), .VGA_BLANK_N(BLANK_N),
        .dbg_ir(dbg_ir), .dbg_quadros(dbg_quadros)
    );

    // ======================================================================
    // Mini-montador (mesma codificacao da ISA)
    // ======================================================================
    function [31:0] R_(input [4:0] op, input [4:0] a, input [4:0] b, input [4:0] c); R_ = {op, a, b, c, 12'd0}; endfunction
    function [31:0] LI(input [4:0] rd, input [15:0] imm); LI = {5'd1, rd, 6'd0, imm}; endfunction
    function [31:0] ADD(input [4:0] rd, input [4:0] rs, input [4:0] rt); ADD = R_(5'd2, rd, rs, rt); endfunction
    localparam [31:0] WAITV = 32'h38000000;
    function [31:0] SET_TILE(input [4:0] l, input [5:0] c, input [7:0] t); SET_TILE = {5'd8, l, c, 8'd0, t}; endfunction
    function [31:0] SET_SCROLL(input [4:0] rs, input [4:0] rt); SET_SCROLL = R_(5'd9, 5'd0, rs, rt); endfunction
    function [31:0] POLY_VTX(input [4:0] s, input [1:0] v, input [4:0] rs, input [4:0] rt); POLY_VTX = {5'd16, s, rs, rt, 10'd0, v}; endfunction
    function [31:0] POLY_CFG(input [4:0] s, input [1:0] tp, input [7:0] c); POLY_CFG = {5'd17, s, 12'd0, tp, c}; endfunction
    function [31:0] POLY_MOVE(input [4:0] s, input [4:0] rs, input [4:0] rt); POLY_MOVE = R_(5'd18, s, rs, rt); endfunction
    function [31:0] SPR_POS(input [4:0] n, input [4:0] rs, input [4:0] rt); SPR_POS = R_(5'd24, n, rs, rt); endfunction
    function [31:0] SPR_ATTR(input [4:0] n, input [7:0] t, input en, input fx, input fy, input bk);
        SPR_ATTR = {5'd25, n, 10'd0, bk, fy, fx, en, t};
    endfunction
    function [31:0] SPR_MOVE(input [4:0] n, input [4:0] rs, input [4:0] rt); SPR_MOVE = R_(5'd26, n, rs, rt); endfunction

    // "ARM": handshake de 4 fases pelos PIOs
    task envia(input [31:0] p);
        begin
            @(posedge CLOCK_50); while (pio_status[2] || pio_status[4]) @(posedge CLOCK_50);
            pio_instr = p;
            @(posedge CLOCK_50); pio_ctrl[0] = 1;
            @(posedge CLOCK_50); while (!pio_status[4]) @(posedge CLOCK_50);
            pio_ctrl[0] = 0;
            @(posedge CLOCK_50); while (pio_status[4]) @(posedge CLOCK_50);
        end
    endtask
    task espera_done;
        begin repeat (4) @(posedge CLOCK_50); while (!pio_status[1]) @(posedge CLOCK_50); end
    endtask

    // ======================================================================
    // Modelo de referencia (independente do RTL)
    // ======================================================================
    reg [7:0] rom_bg  [0:16383];
    reg [7:0] rom_spr [0:8191];
    reg [7:0] tmap    [0:2047];
    initial begin
        $readmemh("bg_tiles.hex", rom_bg);
        $readmemh("sprites_rom.hex", rom_spr);
        $readmemh("mapa_inicial.hex", tmap, 0, 1199);
    end

    // estado esperado da cena (atualizado pelo proprio teste)
    integer e_sx = 0, e_sy = 0;                              // scroll
    integer e_tipo [0:1], e_cor [0:1];
    integer e_vx [0:1][0:2], e_vy [0:1][0:2];
    integer e_spx [0:31], e_spy [0:31], e_tile [0:31];
    reg     e_en [0:31], e_fx [0:31], e_fy [0:31], e_bk [0:31];
    integer i;
    initial begin
        for (i = 0; i < 2; i = i + 1) begin e_tipo[i] = 0; e_cor[i] = 0; end
        for (i = 0; i < 32; i = i + 1) begin
            e_spx[i] = 0; e_spy[i] = 0; e_tile[i] = 0;
            e_en[i] = 0; e_fx[i] = 0; e_fy[i] = 0; e_bk[i] = 0;
        end
    end

    function [7:0] ref_fundo(input integer x, input integer y);
        integer xs, ys, t;
        begin
            xs = x + e_sx; if (xs >= 320) xs = xs - 320;
            ys = y + e_sy; if (ys >= 240) ys = ys - 240;
            t = tmap[(ys / 8) * 40 + (xs / 8)];
            ref_fundo = rom_bg[t * 64 + (ys % 8) * 8 + (xs % 8)];
        end
    endfunction

    function dentro_poly(input integer s, input integer px, input integer py);
        integer e01, e12, e20;
        begin
            dentro_poly = 0;
            if (e_tipo[s] == 1)
                dentro_poly = (px >= e_vx[s][0]) && (px < e_vx[s][1]) && (py >= e_vy[s][0]) && (py < e_vy[s][1]);
            else if (e_tipo[s] == 2) begin
                e01 = (e_vx[s][1] - e_vx[s][0]) * (py - e_vy[s][0]) - (e_vy[s][1] - e_vy[s][0]) * (px - e_vx[s][0]);
                e12 = (e_vx[s][2] - e_vx[s][1]) * (py - e_vy[s][1]) - (e_vy[s][2] - e_vy[s][1]) * (px - e_vx[s][1]);
                e20 = (e_vx[s][0] - e_vx[s][2]) * (py - e_vy[s][2]) - (e_vy[s][0] - e_vy[s][2]) * (px - e_vx[s][2]);
                dentro_poly = (e01 >= 0 && e12 >= 0 && e20 >= 0) || (e01 <= 0 && e12 <= 0 && e20 <= 0);
            end
        end
    endfunction

    function [7:0] ref_pixel(input integer x, input integer y);
        integer n, venc, lx, ly, t, v;
        reg poly, spr;
        reg [7:0] cpoly, cspr;
        begin
            // sprites: o de MENOR indice que cobre o pixel vence
            venc = -1;
            for (n = 31; n >= 0; n = n - 1)
                if (e_en[n] && x >= e_spx[n] && x < e_spx[n] + 16 && y >= e_spy[n] && y < e_spy[n] + 16)
                    venc = n;
            spr = 0; cspr = 0;
            if (venc >= 0) begin
                lx = x - e_spx[venc]; ly = y - e_spy[venc];
                if (e_fx[venc]) lx = 15 - lx;
                if (e_fy[venc]) ly = 15 - ly;
                t = (e_tile[venc] + (ly / 8) * 2 + (lx / 8)) % 128;
                v = rom_spr[t * 64 + (ly % 8) * 8 + (lx % 8)];
                spr = (v != 0); cspr = v;
            end
            // poligonos: slot 0 na frente do slot 1
            poly = 0; cpoly = 0;
            if (dentro_poly(1, x, y) && e_cor[1] != 0) begin poly = 1; cpoly = e_cor[1]; end
            if (dentro_poly(0, x, y) && e_cor[0] != 0) begin poly = 1; cpoly = e_cor[0]; end
            // compositor
            if (spr && !e_bk[venc])  ref_pixel = cspr;
            else if (poly)           ref_pixel = cpoly;
            else if (spr)            ref_pixel = cspr;
            else                     ref_pixel = ref_fundo(x, y);
        end
    endfunction

    // ======================================================================
    // Captura do quadro (saida do compositor alinhada com a coordenada)
    // ======================================================================
    reg [7:0] quadro [0:479][0:639];
    reg [9:0] x1, x2, x3, y1, y2, y3;
    reg       a1, a2, a3;
    wire ativo = (dut.u_vga.h_state == 0) && (dut.u_vga.v_state == 0);
    always @(posedge dut.clk25) begin
        x1 <= dut.next_x; y1 <= dut.next_y; a1 <= ativo;
        x2 <= x1; y2 <= y1; a2 <= a1;
        x3 <= x2; y3 <= y2; a3 <= a2;
        if (a3) quadro[y3][x3] <= dut.cor_final;   // compositor recebe as camadas com 3 ciclos
    end

    task captura_quadro;                            // um quadro completo
        begin
            @(posedge dut.inicio_vblank);
            @(posedge dut.inicio_vblank);
            repeat (4) @(posedge dut.clk25);
        end
    endtask

    integer erros = 0, ea = 0, num_quadro = 0;
    task checa(input c, input [8*72-1:0] m);
        begin if (!c) begin erros = erros + 1; $display("  ERRO @%0t: %0s", $time, m); end end
    endtask
    task inicio(input [8*64-1:0] n); begin ea = erros; $display("Teste: %0s", n); end endtask
    task fim; begin if (erros == ea) $display("  PASSOU"); else $display("  FALHOU (%0d erros)", erros - ea); end endtask

    // Compara o quadro capturado com o modelo, pixel fisico a pixel fisico
    task compara_quadro(output integer difs);
        integer px, py, mostrados;
        reg [7:0] esp;
        begin
            difs = 0; mostrados = 0;
            for (py = 0; py < 480; py = py + 1)
                for (px = 0; px < 640; px = px + 1) begin
                    esp = ref_pixel(px / 2, py / 2);
                    if (quadro[py][px] !== esp) begin
                        difs = difs + 1;
                        if (mostrados < 5) begin
                            $display("    pixel fisico (%0d,%0d) logico (%0d,%0d): saiu %h, esperado %h",
                                     px, py, px / 2, py / 2, quadro[py][px], esp);
                            mostrados = mostrados + 1;
                        end
                    end
                end
        end
    endtask

    task salva_ppm;                                 // imagem 320x240 (pixel logico)
        integer f, px, py;
        reg [7:0] c;
        reg [8*32-1:0] nome;
        begin
            num_quadro = num_quadro + 1;
            $sformat(nome, "quadro_%0d.ppm", num_quadro);
            f = $fopen(nome, "w");
            $fwrite(f, "P3\n320 240\n255\n");
            for (py = 0; py < 240; py = py + 1) begin
                for (px = 0; px < 320; px = px + 1) begin
                    c = quadro[py * 2][px * 2];
                    $fwrite(f, "%0d %0d %0d ", c[7:5] * 255 / 7, c[4:2] * 255 / 7, c[1:0] * 255 / 3);
                end
                $fwrite(f, "\n");
            end
            $fclose(f);
            $display("  imagem salva: %0s", nome);
        end
    endtask

    integer difs, cont;
    task conta_pixels(input [7:0] cor, output integer n);
        integer px, py;
        begin n = 0;
            for (py = 0; py < 480; py = py + 2) for (px = 0; px < 640; px = px + 2)
                if (quadro[py][px] == cor) n = n + 1;
        end
    endtask

    initial begin
        #500_000_000;
        $display("ERRO: tempo limite"); $display("RESULTADO: FALHOU POR TIMEOUT"); $finish;
    end

    // ======================================================================
    // Testes
    // ======================================================================
    initial begin
        repeat (10) @(posedge CLOCK_50);
        reset_externo = 0;
        repeat (10) @(posedge CLOCK_50);

        // ------------------------------------------------------------ 1
        inicio("1. Tela inicial: so o fundo (nenhum sprite/poligono ligado)");
        captura_quadro;
        compara_quadro(difs);
        $display("  pixels diferentes do modelo: %0d de 307200", difs);
        checa(difs == 0, "quadro inicial diferente do modelo");
        salva_ppm;
        fim;

        // ------------------------------------------------------------ 2
        inicio("2. Programa de exemplo da ISA (fundo + triangulo + sprite)");
        envia(32'h40000003); envia(32'h48000000); envia(32'h084000A0); envia(32'h08800028);
        envia(32'h80022000); envia(32'h08400078); envia(32'h08800078); envia(32'h80022001);
        envia(32'h084000C8); envia(32'h80022002); envia(32'h880002E0); envia(32'h0A800064);
        envia(32'h0AC00050); envia(32'h0B000002); envia(32'hC014B000); envia(32'hC8000104);
        espera_done;
        tmap[0] = 3;
        e_tipo[0] = 2; e_cor[0] = 224;
        e_vx[0][0] = 160; e_vy[0][0] = 40; e_vx[0][1] = 120; e_vy[0][1] = 120; e_vx[0][2] = 200; e_vy[0][2] = 120;
        e_spx[0] = 100; e_spy[0] = 80; e_tile[0] = 4; e_en[0] = 1;
        captura_quadro;
        compara_quadro(difs);
        $display("  pixels diferentes do modelo: %0d de 307200", difs);
        checa(difs == 0, "quadro diferente do modelo");
        conta_pixels(8'd224, cont);
        $display("  pixels vermelhos (triangulo): %0d", cont);
        checa(cont > 2000, "o triangulo deveria aparecer");
        salva_ppm;
        fim;

        // ------------------------------------------------------------ 3
        inicio("3. Animacao: 3x (WAITV, ADD r10, SPR_POS) -> sprite anda 6 px");
        repeat (3) begin envia(WAITV); envia(32'h1294C000); envia(32'hC014B000); end
        espera_done;
        e_spx[0] = 106;
        captura_quadro;
        compara_quadro(difs);
        $display("  pixels diferentes do modelo: %0d", difs);
        checa(difs == 0, "sprite deveria estar em x=106");
        salva_ppm;
        fim;

        // ------------------------------------------------------------ 4
        inicio("4. Prioridades, espelho, 2o poligono, POLY_MOVE e scroll");
        // sprite 1 ATRAS do triangulo (BACK), espelhado
        envia(LI(1, 150)); envia(LI(2, 95));
        envia(SPR_POS(1, 1, 2)); envia(SPR_ATTR(1, 8'd8, 1, 1, 0, 1));
        e_spx[1] = 150; e_spy[1] = 95; e_tile[1] = 8; e_en[1] = 1; e_fx[1] = 1; e_bk[1] = 1;
        // sprite 2 NA FRENTE do triangulo, espelhado na vertical
        envia(LI(1, 165)); envia(LI(2, 100));
        envia(SPR_POS(2, 1, 2)); envia(SPR_ATTR(2, 8'd12, 1, 0, 1, 0));
        e_spx[2] = 165; e_spy[2] = 100; e_tile[2] = 12; e_en[2] = 1; e_fy[2] = 1;
        // slot 1: retangulo azul atras do triangulo, depois movido
        envia(LI(1, 20)); envia(LI(2, 150)); envia(POLY_VTX(1, 0, 1, 2));
        envia(LI(1, 140)); envia(LI(2, 200)); envia(POLY_VTX(1, 1, 1, 2));
        envia(POLY_CFG(1, 2'd1, 8'h03));
        envia(LI(3, 30)); envia(LI(4, 16'hFFF6));   // dx = +30, dy = -10
        envia(POLY_MOVE(1, 3, 4));
        e_tipo[1] = 1; e_cor[1] = 8'h03;
        e_vx[1][0] = 50; e_vy[1][0] = 140; e_vx[1][1] = 170; e_vy[1][1] = 190;
        // mais tiles e scroll de (16, 8)
        envia(SET_TILE(1, 2, 8'd5)); envia(SET_TILE(2, 1, 8'd7)); envia(SET_TILE(29, 39, 8'd9));
        tmap[1 * 40 + 2] = 5; tmap[2 * 40 + 1] = 7; tmap[29 * 40 + 39] = 9;
        envia(LI(5, 16)); envia(LI(6, 8)); envia(SET_SCROLL(5, 6));
        e_sx = 16; e_sy = 8;
        espera_done;
        captura_quadro;
        compara_quadro(difs);
        $display("  pixels diferentes do modelo: %0d", difs);
        checa(difs == 0, "quadro com prioridades/scroll diferente do modelo");
        salva_ppm;
        fim;

        // ------------------------------------------------------------ 5
        inicio("5. SPR_MOVE e desligar sprite (EN = 0)");
        envia(LI(7, 16'hFFFC)); envia(LI(8, 16'd3));     // dx = -4, dy = +3
        envia(SPR_MOVE(0, 7, 8));
        envia(SPR_ATTR(2, 8'd12, 0, 0, 1, 0));            // sprite 2 desligado
        espera_done;
        e_spx[0] = 102; e_spy[0] = 83; e_en[2] = 0;
        captura_quadro;
        compara_quadro(difs);
        $display("  pixels diferentes do modelo: %0d", difs);
        checa(difs == 0, "SPR_MOVE/EN diferente do modelo");
        salva_ppm;
        fim;

        // ------------------------------------------------------------ 6
        inicio("6. Reset (pio_ctrl[1]): tiles alterados voltam ao mapa inicial");
        // neste ponto ha 4 tiles alterados, scroll, 2 poligonos e 2 sprites na tela
        pio_ctrl[1] = 1;
        repeat (20) @(posedge CLOCK_50);
        pio_ctrl[1] = 0;
        repeat (20) @(posedge CLOCK_50);
        checa(pio_status[0] == 1'b1, "busy deveria ficar em 1 durante a restauracao");
        cont = 0;
        while (pio_status[0]) begin @(posedge CLOCK_50); cont = cont + 1; end
        $display("  restauracao levou %0d ciclos de 50 MHz (~%0d us)", cont, cont / 50);
        checa(cont > 2000 && cont < 3000, "restauracao deveria levar ~1200 ciclos de 25 MHz");
        checa(pio_status[1] == 1'b1, "depois do reset o coprocessador deveria estar done");
        // modelo: mapa original, tudo desligado, scroll 0
        $readmemh("mapa_inicial.hex", tmap, 0, 1199);
        e_sx = 0; e_sy = 0;
        for (i = 0; i < 2; i = i + 1) begin e_tipo[i] = 0; e_cor[i] = 0; end
        for (i = 0; i < 32; i = i + 1) begin
            e_spx[i] = 0; e_spy[i] = 0; e_tile[i] = 0;
            e_en[i] = 0; e_fx[i] = 0; e_fy[i] = 0; e_bk[i] = 0;
        end
        captura_quadro;
        compara_quadro(difs);
        $display("  pixels diferentes do mapa inicial: %0d", difs);
        checa(difs == 0, "depois do reset a tela deveria ser a cena inicial");
        salva_ppm;
        fim;

        // ------------------------------------------------------------ 7
        inicio("7. Depois do reset o SET_TILE volta a funcionar");
        envia(SET_TILE(5, 5, 8'd170)); envia(SET_TILE(5, 6, 8'd171));   // letras 'A' 'B'
        espera_done;
        tmap[5 * 40 + 5] = 170; tmap[5 * 40 + 6] = 171;
        captura_quadro;
        compara_quadro(difs);
        $display("  pixels diferentes do modelo: %0d", difs);
        checa(difs == 0, "SET_TILE depois do reset diferente do modelo");
        fim;

        $display("--------------------------------------------");
        if (erros == 0) $display("RESULTADO: TODOS OS TESTES PASSARAM");
        else            $display("RESULTADO: %0d ERRO(S)", erros);
        $display("--------------------------------------------");
        $finish;
    end

endmodule
