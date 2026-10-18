// ============================================================================
// tb_nucleo_coprocessador.v
// Testbench auto-verificavel do NUCLEO do coprocessador
// (unidade de busca + unidade de controle + datapath).
//
// - "ARM" simulado (clock proprio de 50 MHz) envia instrucoes pelo handshake
//   valid/ack, exatamente como o programa real faz pelos PIOs.
// - Modelos simples dos motores (tabela de sprites e tilemap) recebem o
//   barramento grafico, para conferirmos o efeito de cada instrucao.
// - As instrucoes sao montadas por funcoes (mini-montador) com a mesma
//   codificacao da ISA.
//
// Rodar (na pasta simulacao): comando completo na secao 10.4 do README
//   (nucleo_coprocessador, unidade_controle, caminho_dados, banco_registradores,
//    ula, unidade_busca e fifo_instr, todos em ../quartus/rtl/).
// ============================================================================
`timescale 1ns/1ps
module tb_nucleo_coprocessador;

    // ---------------- clocks ----------------
    reg clk = 0, clk_arm = 0;
    always #20 clk = ~clk;                                   // 25 MHz
    initial begin #7; forever #10 clk_arm = ~clk_arm; end    // 50 MHz

    // ---------------- DUT ----------------
    reg         reset = 1;
    reg  [31:0] pio_instr = 0;
    reg         pio_valid = 0;
    wire [31:0] status;
    reg         vblank = 0, inicio_vblank = 0;

    wire        tm_wr_en;   wire [10:0] tm_wr_addr;  wire [7:0] tm_wr_data;
    wire [8:0]  scroll_x;   wire [7:0]  scroll_y;
    wire [8:0]  p0_x0, p0_x1, p0_x2, p1_x0, p1_x1, p1_x2;
    wire [7:0]  p0_y0, p0_y1, p0_y2, p1_y0, p1_y1, p1_y2;
    wire [1:0]  p0_tipo, p1_tipo;  wire [7:0] p0_cor, p1_cor;
    wire        spr_wr_pos, spr_wr_attr;  wire [4:0] spr_idx;
    wire [8:0]  spr_x;  wire [7:0] spr_y;  wire [11:0] spr_attr;
    wire [8:0]  spr_cur_x;  wire [7:0] spr_cur_y;
    wire [31:0] ir_atual;

    nucleo_coprocessador dut (
        .clk(clk), .reset(reset),
        .pio_instr(pio_instr), .pio_valid(pio_valid), .status(status),
        .vblank(vblank), .inicio_vblank(inicio_vblank),
        .tm_wr_en(tm_wr_en), .tm_wr_addr(tm_wr_addr), .tm_wr_data(tm_wr_data),
        .scroll_x(scroll_x), .scroll_y(scroll_y),
        .p0_x0(p0_x0), .p0_x1(p0_x1), .p0_x2(p0_x2), .p0_y0(p0_y0), .p0_y1(p0_y1), .p0_y2(p0_y2),
        .p0_tipo(p0_tipo), .p0_cor(p0_cor),
        .p1_x0(p1_x0), .p1_x1(p1_x1), .p1_x2(p1_x2), .p1_y0(p1_y0), .p1_y1(p1_y1), .p1_y2(p1_y2),
        .p1_tipo(p1_tipo), .p1_cor(p1_cor),
        .spr_wr_pos(spr_wr_pos), .spr_wr_attr(spr_wr_attr), .spr_idx(spr_idx),
        .spr_x(spr_x), .spr_y(spr_y), .spr_attr(spr_attr),
        .spr_cur_x(spr_cur_x), .spr_cur_y(spr_cur_y),
        .ir_atual(ir_atual)
    );

    // ---------------- modelos dos motores ----------------
    reg [8:0]  m_sx [0:31];
    reg [7:0]  m_sy [0:31];
    reg [11:0] m_sa [0:31];
    reg [7:0]  m_tilemap [0:1199];
    integer i;
    initial begin
        for (i = 0; i < 32; i = i + 1) begin m_sx[i] = 0; m_sy[i] = 0; m_sa[i] = 0; end
        for (i = 0; i < 1200; i = i + 1) m_tilemap[i] = 0;
    end
    always @(posedge clk) begin
        if (spr_wr_pos)  begin m_sx[spr_idx] <= spr_x; m_sy[spr_idx] <= spr_y; end
        if (spr_wr_attr) m_sa[spr_idx] <= spr_attr;
        if (tm_wr_en)    m_tilemap[tm_wr_addr] <= tm_wr_data;
    end
    assign spr_cur_x = m_sx[spr_idx];
    assign spr_cur_y = m_sy[spr_idx];

    // ---------------- mini-montador (mesma codificacao da ISA) ----------------
    function [31:0] R(input [4:0] op, input [4:0] a, input [4:0] b, input [4:0] c);
        R = {op, a, b, c, 12'd0};
    endfunction
    function [31:0] LI(input [4:0] rd, input [15:0] imm);  LI = {5'd1, rd, 6'd0, imm}; endfunction
    function [31:0] ADD(input [4:0] rd, input [4:0] rs, input [4:0] rt); ADD = R(5'd2, rd, rs, rt); endfunction
    function [31:0] SUB(input [4:0] rd, input [4:0] rs, input [4:0] rt); SUB = R(5'd3, rd, rs, rt); endfunction
    function [31:0] ADDI(input [4:0] rd, input [4:0] rs, input [16:0] imm); ADDI = {5'd4, rd, rs, imm}; endfunction
    function [31:0] AND_(input [4:0] rd, input [4:0] rs, input [4:0] rt); AND_ = R(5'd5, rd, rs, rt); endfunction
    function [31:0] OR_(input [4:0] rd, input [4:0] rs, input [4:0] rt);  OR_  = R(5'd6, rd, rs, rt); endfunction
    localparam [31:0] NOP = 32'h00000000, WAITV = 32'h38000000;
    function [31:0] SET_TILE(input [4:0] lin, input [5:0] col, input [7:0] t); SET_TILE = {5'd8, lin, col, 8'd0, t}; endfunction
    function [31:0] SET_SCROLL(input [4:0] rs, input [4:0] rt); SET_SCROLL = R(5'd9, 5'd0, rs, rt); endfunction
    function [31:0] POLY_VTX(input [4:0] sl, input [1:0] v, input [4:0] rs, input [4:0] rt);
        POLY_VTX = {5'd16, sl, rs, rt, 10'd0, v};
    endfunction
    function [31:0] POLY_CFG(input [4:0] sl, input [1:0] tp, input [7:0] c); POLY_CFG = {5'd17, sl, 12'd0, tp, c}; endfunction
    function [31:0] POLY_MOVE(input [4:0] sl, input [4:0] rs, input [4:0] rt); POLY_MOVE = R(5'd18, sl, rs, rt); endfunction
    function [31:0] SPR_POS(input [4:0] n, input [4:0] rs, input [4:0] rt); SPR_POS = R(5'd24, n, rs, rt); endfunction
    function [31:0] SPR_ATTR(input [4:0] n, input [7:0] t, input en, input fx, input fy, input bk);
        SPR_ATTR = {5'd25, n, 10'd0, bk, fy, fx, en, t};
    endfunction
    function [31:0] SPR_MOVE(input [4:0] n, input [4:0] rs, input [4:0] rt); SPR_MOVE = R(5'd26, n, rs, rt); endfunction
    localparam OFF = 2'd0, RECT = 2'd1, TRI = 2'd2;

    // ---------------- utilitarios ----------------
    integer erros = 0, ea = 0;
    task checa(input c, input [8*72-1:0] m);
        begin if (!c) begin erros = erros + 1; $display("  ERRO @%0t: %0s", $time, m); end end
    endtask
    task inicio(input [8*64-1:0] n); begin ea = erros; $display("Teste: %0s", n); end endtask
    task fim; begin if (erros == ea) $display("  PASSOU"); else $display("  FALHOU (%0d erros)", erros - ea); end endtask

    function [15:0] reg_(input [4:0] n);       // le o banco de registradores por dentro
        reg_ = (n == 0) ? 16'd0 : dut.u_dp.u_banco.regs[n];
    endfunction

    // "ARM": envia 1 palavra pelo handshake de 4 fases
    task envia(input [31:0] p);
        begin
            @(posedge clk_arm); while (status[2] || status[4]) @(posedge clk_arm);  // fila cheia / ack anterior
            pio_instr = p;
            @(posedge clk_arm); pio_valid = 1;
            @(posedge clk_arm); while (!status[4]) @(posedge clk_arm);
            pio_valid = 0;
            @(posedge clk_arm); while (status[4]) @(posedge clk_arm);
        end
    endtask

    task espera_done;                            // o que o ARM faz no fim do programa
        begin
            repeat (2) @(posedge clk);
            while (!status[1]) @(posedge clk);
            #1;
        end
    endtask

    task pulso_vblank;
        begin
            @(negedge clk); inicio_vblank = 1; vblank = 1;
            @(negedge clk); inicio_vblank = 0;
            repeat (5) @(negedge clk); vblank = 0;
        end
    endtask

    task aplica_reset;
        begin
            @(negedge clk); reset = 1; pio_valid = 0;
            repeat (2) @(negedge clk); reset = 0;
        end
    endtask

    // Watchdog
    initial begin
        #20_000_000;
        $display("ERRO: tempo limite (UC travada?) estado=%0d status=%h", dut.u_uc.estado, status);
        $display("RESULTADO: FALHOU POR TIMEOUT");
        $finish;
    end

    // Programa de exemplo da ISA (19 palavras, aba Codificador)
    reg [31:0] prog [0:18];
    initial begin
        prog[0]=32'h40000003; prog[1]=32'h48000000; prog[2]=32'h084000A0; prog[3]=32'h08800028;
        prog[4]=32'h80022000; prog[5]=32'h08400078; prog[6]=32'h08800078; prog[7]=32'h80022001;
        prog[8]=32'h084000C8; prog[9]=32'h80022002; prog[10]=32'h880002E0; prog[11]=32'h0A800064;
        prog[12]=32'h0AC00050; prog[13]=32'h0B000002; prog[14]=32'hC014B000; prog[15]=32'hC8000104;
        prog[16]=32'h38000000; prog[17]=32'h1294C000; prog[18]=32'hC014B000;
    end

    integer k, ciclos, t_ini;
    reg vblank_auto = 0;
    always @(posedge clk) if (vblank_auto && dut.u_uc.estado == 3'd5) begin
        // gera o vblank automaticamente quando a UC esta esperando (teste 12)
        inicio_vblank <= 1;
    end else inicio_vblank <= (vblank_auto ? 1'b0 : inicio_vblank);

    initial begin
        $dumpfile("tb_nucleo_coprocessador.vcd");
        $dumpvars(0, tb_nucleo_coprocessador);
        aplica_reset;

        // ------------------------------------------------------------ 1
        inicio("1. Estado apos reset (status = done + fila vazia)");
        #1;
        checa(status == 32'h0000000A, "status deveria ser 0x0000000A");
        checa(ir_atual == 32'd0, "IR deveria ser 0 (NOP)");
        fim;

        // ------------------------------------------------------------ 2
        inicio("2. LI, r0 sempre zero, NOP");
        envia(LI(1, 100));
        envia(LI(2, 16'hFFFE));               // -2
        envia(LI(0, 555));                    // ignorado
        envia(NOP);
        espera_done;
        checa(reg_(1) == 100,      "r1 deveria ser 100");
        checa(reg_(2) == 16'hFFFE, "r2 deveria ser 0xFFFE (-2)");
        checa(reg_(0) == 0,        "r0 deveria continuar 0");
        checa(status[11:8] == 4'b0000, "LI/NOP nao mexem nas flags");
        fim;

        // ------------------------------------------------------------ 3
        inicio("3. ULA: ADD, SUB, ADDI, AND, OR e flags NZCV");
        envia(ADD(3, 1, 2));    espera_done;  // 100 + (-2) = 98, com vai-um
        checa(reg_(3) == 98, "ADD: r3 deveria ser 98");
        checa(status[11:8] == 4'b0010, "ADD 100+0xFFFE: flags deveriam ser N0 Z0 C1 V0");
        envia(SUB(4, 1, 1));    espera_done;  // 0
        checa(reg_(4) == 0 && status[11:8] == 4'b0110, "SUB r1-r1: 0 com Z=1 C=1");
        envia(ADDI(5, 1, -17'sd200)); espera_done;   // 100 - 200 = -100
        checa(reg_(5) == 16'hFF9C, "ADDI: r5 deveria ser -100 (0xFF9C)");
        checa(status[11:8] == 4'b1000, "ADDI negativo: N=1 Z0 C0 V0");
        envia(LI(6, 16'h00F0)); envia(LI(7, 16'h0F0F));
        envia(SUB(8, 4, 1));    espera_done;  // 0 - 100: N=1, C=0 (emprestimo)
        checa(reg_(8) == 16'hFF9C && status[11:8] == 4'b1000, "SUB 0-100: N=1 C=0 (emprestimo)");
        envia(ADD(8, 1, 2));    espera_done;  // deixa C=1 antes do AND
        envia(AND_(9, 6, 7));   espera_done;  // 0x0000 -> Z=1, C=1 preservado
        checa(reg_(9) == 16'h0000 && status[11:8] == 4'b0110, "AND: 0 com Z=1 e C preservado (=1)");
        envia(OR_(10, 6, 7));   espera_done;  // 0x0FFF
        checa(reg_(10) == 16'h0FFF && status[11:8] == 4'b0010, "OR: 0x0FFF, N0 Z0, C preservado");
        envia(LI(11, 16'h7FFF)); envia(ADDI(11, 11, 1)); espera_done;
        checa(reg_(11) == 16'h8000 && status[11:8] == 4'b1001, "ADDI 0x7FFF+1: overflow N=1 V=1");
        fim;

        // ------------------------------------------------------------ 4
        inicio("4. SET_TILE (endereco lin*40 + col)");
        envia(SET_TILE(0, 0, 8'd3));
        envia(SET_TILE(29, 39, 8'hAB));       // ultima posicao: 1199
        envia(SET_TILE(7, 13, 8'd200));       // 7*40+13 = 293
        espera_done; @(posedge clk); #1;
        checa(m_tilemap[0] == 3,       "tilemap[0] deveria ser 3");
        checa(m_tilemap[1199] == 8'hAB, "tilemap[1199] deveria ser 0xAB");
        checa(m_tilemap[293] == 200,   "tilemap[293] deveria ser 200");
        fim;

        // ------------------------------------------------------------ 5
        inicio("5. SET_SCROLL a partir de registradores");
        envia(LI(12, 50));
        envia(SET_SCROLL(1, 12));             // (100, 50)
        espera_done;
        checa(scroll_x == 100 && scroll_y == 50, "scroll deveria ser (100, 50)");
        envia(SET_SCROLL(0, 0)); espera_done;
        checa(scroll_x == 0 && scroll_y == 0, "SET_SCROLL r0, r0 deveria zerar");
        fim;

        // ------------------------------------------------------------ 6
        inicio("6. POLY_VTX e POLY_CFG (triangulo no slot 0, retangulo no 1)");
        envia(LI(1, 160)); envia(LI(2, 40));  envia(POLY_VTX(0, 0, 1, 2));
        envia(LI(1, 120)); envia(LI(2, 120)); envia(POLY_VTX(0, 1, 1, 2));
        envia(LI(1, 200));                    envia(POLY_VTX(0, 2, 1, 2));
        envia(POLY_CFG(0, TRI, 8'd224));
        envia(LI(1, 10));  envia(LI(2, 20));  envia(POLY_VTX(1, 0, 1, 2));
        envia(LI(1, 90));  envia(LI(2, 60));  envia(POLY_VTX(1, 1, 1, 2));
        envia(POLY_CFG(1, RECT, 8'h1C));
        envia(POLY_CFG(5, TRI, 8'hFF));       // slot inexistente: ignorado
        espera_done;
        checa(p0_x0 == 160 && p0_y0 == 40 && p0_x1 == 120 && p0_y1 == 120 && p0_x2 == 200 && p0_y2 == 120,
              "vertices do slot 0 errados");
        checa(p0_tipo == TRI && p0_cor == 224, "slot 0 deveria ser TRI cor 224");
        checa(p1_x0 == 10 && p1_y0 == 20 && p1_x1 == 90 && p1_y1 == 60, "vertices do slot 1 errados");
        checa(p1_tipo == RECT && p1_cor == 8'h1C, "slot 1 deveria ser RECT cor 0x1C (e nao mudar pelo slot 5)");
        fim;

        // ------------------------------------------------------------ 7
        inicio("7. POLY_MOVE: soma (dx, dy) aos 3 vertices pela ULA");
        envia(LI(13, 10)); envia(LI(14, 16'hFFFB));   // dx = 10, dy = -5
        envia(POLY_MOVE(0, 13, 14));
        espera_done;
        checa(p0_x0 == 170 && p0_y0 == 35 && p0_x1 == 130 && p0_y1 == 115 && p0_x2 == 210 && p0_y2 == 115,
              "POLY_MOVE: vertices deveriam andar (+10, -5)");
        checa(p1_x0 == 10 && p1_y0 == 20, "POLY_MOVE no slot 0 nao pode mexer no slot 1");
        fim;

        // ------------------------------------------------------------ 8
        inicio("8. SPR_POS e SPR_ATTR");
        envia(LI(1, 100)); envia(LI(2, 50));
        envia(SPR_POS(3, 1, 2));
        envia(SPR_ATTR(3, 8'd4, 1, 1, 0, 1));         // tile 4, EN, FX, BACK
        envia(LI(1, 319)); envia(LI(2, 239));
        envia(SPR_POS(31, 1, 2));                     // ultimo sprite, canto da tela
        espera_done; @(posedge clk); #1;
        checa(m_sx[3] == 100 && m_sy[3] == 50, "sprite 3 deveria estar em (100, 50)");
        checa(m_sa[3] == 12'hB04, "atributos do sprite 3 deveriam ser 0xB04");
        checa(m_sx[31] == 319 && m_sy[31] == 239, "sprite 31 deveria estar em (319, 239)");
        fim;

        // ------------------------------------------------------------ 9
        inicio("9. SPR_MOVE: soma (dx, dy) a posicao atual pela ULA");
        envia(LI(15, 2)); envia(LI(16, 16'hFFFE));    // dx = +2, dy = -2
        envia(SPR_MOVE(3, 15, 16));
        envia(SPR_MOVE(3, 15, 16));
        espera_done; @(posedge clk); #1;
        checa(m_sx[3] == 104 && m_sy[3] == 46, "sprite 3 deveria estar em (104, 46) apos 2 SPR_MOVE");
        checa(m_sa[3] == 12'hB04, "SPR_MOVE nao pode mexer nos atributos");
        fim;

        // ------------------------------------------------------------ 10
        inicio("10. WAITV: UC espera o vblank; fila acumula enquanto isso");
        envia(WAITV);
        for (k = 0; k < 10; k = k + 1) envia(LI(20 + k, 16'd7 + k));
        repeat (20) @(posedge clk); #1;
        checa(status[0] == 1, "busy deveria ser 1 durante o WAITV");
        checa(status[21:16] == 10, "as 10 instrucoes deveriam estar esperando na fila");
        checa(reg_(20) == 0, "nada pode executar antes do vblank");
        @(negedge clk); inicio_vblank = 1; @(negedge clk); inicio_vblank = 0;
        t_ini = $time;
        espera_done;
        ciclos = ($time - t_ini) / 40;
        checa(reg_(20) == 7 && reg_(29) == 16, "apos o vblank as 10 LI deveriam executar");
        $display("  10 instrucoes executadas em %0d ciclos (~3 ciclos por instrucao)", ciclos);
        checa(ciclos >= 30 && ciclos <= 34, "deveria levar ~3 ciclos por instrucao");
        fim;

        // ------------------------------------------------------------ 11
        inicio("11. Opcode invalido: liga err e continua executando");
        checa(status[6] == 0, "err deveria comecar em 0");
        envia(32'h58000000);                  // opcode 11 (reservado)
        envia(LI(30, 16'h1234));
        espera_done;
        checa(status[6] == 1, "err deveria ligar");
        checa(reg_(30) == 16'h1234, "a instrucao seguinte deveria executar normalmente");
        fim;

        // ------------------------------------------------------------ 12
        inicio("12. Programa de exemplo da ISA (19 palavras) do inicio ao fim");
        aplica_reset;
        for (i = 0; i < 32; i = i + 1) begin m_sx[i] = 0; m_sy[i] = 0; m_sa[i] = 0; end
        vblank_auto = 1;
        for (k = 0; k < 19; k = k + 1) envia(prog[k]);
        espera_done; @(posedge clk); #1;
        vblank_auto = 0;
        checa(m_tilemap[0] == 3, "SET_TILE 0,0,3");
        checa(p0_tipo == TRI && p0_cor == 224, "triangulo vermelho no slot 0");
        checa(p0_x0 == 160 && p0_y0 == 40 && p0_x1 == 120 && p0_y1 == 120 && p0_x2 == 200 && p0_y2 == 120,
              "vertices do triangulo");
        checa(reg_(10) == 102 && reg_(11) == 80 && reg_(12) == 2, "r10=102, r11=80, r12=2");
        checa(m_sx[0] == 102 && m_sy[0] == 80, "sprite 0 deveria terminar em (102, 80)");
        checa(m_sa[0] == 12'h104, "sprite 0: tile 4, EN");
        checa(status[6] == 0, "nenhum erro");
        fim;

        // ------------------------------------------------------------ 13
        inicio("13. Reset no meio da execucao");
        envia(WAITV); envia(LI(1, 1));
        repeat (10) @(posedge clk);
        aplica_reset; #1;
        checa(status == 32'h0000000A, "reset deveria voltar ao estado inicial");
        checa(reg_(10) == 0, "reset deveria zerar os registradores");
        envia(LI(1, 42)); espera_done;
        checa(reg_(1) == 42, "apos o reset deveria voltar a funcionar");
        fim;

        // ------------------------------------------------------------
        $display("--------------------------------------------");
        if (erros == 0) $display("RESULTADO: TODOS OS TESTES PASSARAM");
        else            $display("RESULTADO: %0d ERRO(S)", erros);
        $display("--------------------------------------------");
        $finish;
    end

endmodule
