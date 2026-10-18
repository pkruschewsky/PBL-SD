// ============================================================================
// tb_programa_arm.v - roda no coprocessador (RTL) as palavras que o PROGRAMA
// EM ASSEMBLY DO ARM (software/arm/demo_arm.s) realmente enviou.
//
// De onde vem sim_modelos/palavras_demo_arm.hex:
//   sequencia de palavras que o demo_arm.s entregou pelo handshake
//   (cena + 12 blocos "quadro" + 4 blocos "scroll"), gravada a partir do
//   programa real.
//
// O testbench envia essas palavras pelo handshake valid/ack real, deixa o WAITV
// segurar a UC ate o vblank, e em 4 momentos da animacao CAPTURA a tela e
// compara pixel a pixel com o modelo de referencia (que executa as mesmas
// palavras num interpretador da ISA escrito aqui). Salva arm_quadro_N.ppm.
//
// Rodar (na pasta simulacao, com os .hex de sim_modelos/ copiados para ela):
//   mesmo comando do tb_coprocessador_top (secao 10.4 do README).
// ============================================================================
`timescale 1ns/1ps
module tb_programa_arm;

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
            $sformat(nome, "arm_quadro_%0d.ppm", num_quadro);
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


    // ======================================================================
    // Interpretador da ISA (atualiza o estado esperado e_* do modelo)
    // ======================================================================
    reg [15:0] rg [0:31];
    initial for (i = 0; i < 32; i = i + 1) rg[i] = 0;

    task modelo(input [31:0] w);
        reg [4:0] op, a, b, c;
        integer s, v;
        begin
            op = w[31:27]; a = w[26:22]; b = w[21:17]; c = w[16:12];
            s = a[0]; v = w[1:0];
            case (op)
                5'd1:  if (a != 0) rg[a] = w[15:0];
                5'd2:  if (a != 0) rg[a] = rg[b] + rg[c];
                5'd3:  if (a != 0) rg[a] = rg[b] - rg[c];
                5'd4:  if (a != 0) rg[a] = rg[b] + w[15:0];
                5'd5:  if (a != 0) rg[a] = rg[b] & rg[c];
                5'd6:  if (a != 0) rg[a] = rg[b] | rg[c];
                5'd8:  tmap[a * 40 + w[21:16]] = w[7:0];
                5'd9:  begin e_sx = rg[b][8:0]; e_sy = rg[c][7:0]; end
                5'd16: begin e_vx[s][v] = rg[b][8:0]; e_vy[s][v] = rg[c][7:0]; end
                5'd17: begin e_tipo[s] = w[9:8]; e_cor[s] = w[7:0]; end
                5'd18: for (v = 0; v < 3; v = v + 1) begin
                           e_vx[s][v] = (e_vx[s][v] + rg[b]) & 9'h1FF;
                           e_vy[s][v] = (e_vy[s][v] + rg[c]) & 8'hFF;
                       end
                5'd24: begin e_spx[a] = rg[b][8:0]; e_spy[a] = rg[c][7:0]; end
                5'd25: begin e_tile[a] = w[7:0]; e_en[a] = w[8]; e_fx[a] = w[9]; e_fy[a] = w[10]; e_bk[a] = w[11]; end
                5'd26: begin e_spx[a] = (e_spx[a] + rg[b]) & 9'h1FF; e_spy[a] = (e_spy[a] + rg[c]) & 8'hFF; end
                default: ;
            endcase
        end
    endtask

    // ======================================================================
    // Programa do ARM
    // ======================================================================
    reg [31:0] prog [0:4095];
    integer n_palavras, p, k, difs;
    integer quadros_enviados;                       // WAITV ja enviados
    integer arq, lidos;
    initial begin                                   // le uma palavra hex por linha
        n_palavras = 0;
        arq = $fopen("palavras_demo_arm.hex", "r");
        if (arq != 0) begin
            lidos = $fscanf(arq, "%h\n", prog[0]);
            while (lidos == 1 && n_palavras < 4095) begin
                n_palavras = n_palavras + 1;
                lidos = $fscanf(arq, "%h\n", prog[n_palavras]);
            end
            $fclose(arq);
        end
    end

    // momentos em que a tela e conferida (numero de quadros de animacao ja enviados)
    function confere(input integer q);
        confere = (q == 0) || (q == 1) || (q == 3) || (q == 12);
    endfunction

    task captura_e_compara(input integer q);
        begin
            espera_done;                            // UC terminou tudo que foi enviado
            captura_quadro;
            compara_quadro(difs);
            $display("Teste: tela apos a cena + %0d quadro(s) de animacao", q);
            $display("  sprite0=(%0d,%0d) sprite1=(%0d,%0d) retangulo y0=%0d scroll_x=%0d | pixels diferentes: %0d de 307200",
                     e_spx[0], e_spy[0], e_spx[1], e_spy[1], e_vy[1][0], e_sx, difs);
            checa(difs == 0, "tela diferente do modelo");
            checa(pio_status[6] == 0, "coprocessador acusou opcode invalido");
            salva_ppm;
            fim;
        end
    endtask

    initial begin
        #1_000_000_000;
        $display("ERRO: tempo limite"); $display("RESULTADO: FALHOU POR TIMEOUT"); $finish;
    end

    initial begin
        repeat (10) @(posedge CLOCK_50);
        reset_externo = 0;
        repeat (10) @(posedge CLOCK_50);
        #1;
        $display("Palavras enviadas pelo programa ARM: %0d", n_palavras);
        checa(n_palavras > 50, "arquivo palavras_demo_arm.hex vazio ou ausente");

        quadros_enviados = 0;
        for (p = 0; p < n_palavras; p = p + 1) begin
            if (prog[p] == 32'h38000000) begin          // proximo WAITV: confere a tela antes?
                if (confere(quadros_enviados)) captura_e_compara(quadros_enviados);
                quadros_enviados = quadros_enviados + 1;
            end
            envia(prog[p]);
            modelo(prog[p]);
        end
        captura_e_compara(quadros_enviados);           // estado final

        if (erros == 0) $display("RESULTADO: TODOS OS TESTES PASSARAM");
        else            $display("RESULTADO: %0d ERRO(S)", erros);
        $finish;
    end
endmodule
