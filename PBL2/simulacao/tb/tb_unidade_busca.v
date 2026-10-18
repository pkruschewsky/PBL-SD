// ============================================================================
// tb_unidade_busca.v
// Testbench auto-verificavel da unidade de busca (receptor + FIFO + IR).
//
// - "ARM" simulado: roda num clock proprio de 50 MHz (como o PIO real) e
//   envia palavras com o handshake de 4 fases (valid / ack).
// - "UC" simulada: pulsa 'busca' e confere se o IR recebeu a palavra certa.
// - Um modelo de referencia guarda a ordem em que as palavras foram enviadas;
//   cada busca e comparada com ele (ordem, perda e duplicacao).
//
// Rodar (na pasta simulacao):
//   iverilog -o sim tb/tb_unidade_busca.v ../quartus/rtl/unidade_busca.v ../quartus/rtl/fifo_instr.v && vvp sim
// ============================================================================
`timescale 1ns/1ps

module tb_unidade_busca;

    // ---------------- clocks ----------------
    reg clk = 0;                         // nucleo: 25 MHz
    reg clk_arm = 0;                     // lado ARM/PIO: 50 MHz, fase deslocada
    always #20 clk = ~clk;
    initial begin #7; forever #10 clk_arm = ~clk_arm; end

    // ---------------- DUT ----------------
    reg         reset = 1;
    reg  [31:0] pio_instr = 0;
    reg         pio_valid = 0;
    wire        ack;
    reg         busca = 0;
    wire        instr_disponivel;
    wire [31:0] ir;
    wire        ir_valido;
    wire        fifo_full, fifo_empty;
    wire [5:0]  fifo_count;

    unidade_busca dut (
        .clk(clk), .reset(reset),
        .pio_instr(pio_instr), .pio_valid(pio_valid), .ack(ack),
        .busca(busca), .instr_disponivel(instr_disponivel),
        .ir(ir), .ir_valido(ir_valido),
        .fifo_full(fifo_full), .fifo_empty(fifo_empty), .fifo_count(fifo_count)
    );

    // ---------------- modelo de referencia ----------------
    reg [31:0] enviadas [0:4095];
    integer n_env = 0;                   // palavras entregues pelo "ARM"
    integer n_rec = 0;                   // palavras recebidas pela "UC"
    integer erros = 0, erros_antes = 0;

    task checa(input cond, input [8*72-1:0] msg);
        begin
            if (!cond) begin
                erros = erros + 1;
                $display("  ERRO @%0t: %0s (ack=%b count=%0d ir=%h)", $time, msg, ack, fifo_count, ir);
            end
        end
    endtask

    task inicio_teste(input [8*64-1:0] nome);
        begin erros_antes = erros; $display("Teste: %0s", nome); end
    endtask

    task fim_teste;
        begin
            if (erros == erros_antes) $display("  PASSOU");
            else                      $display("  FALHOU (%0d erros)", erros - erros_antes);
        end
    endtask

    // ---------------- "ARM": envia uma palavra (handshake de 4 fases) ----------------
    // 'segura' = ciclos extras com valid em 1 depois do ack (testa duplicacao)
    task arm_envia(input [31:0] palavra, input integer segura);
        integer k;
        begin
            @(posedge clk_arm); while (ack) @(posedge clk_arm);      // ack anterior baixou
            pio_instr = palavra;
            enviadas[n_env % 4096] = palavra;
            n_env = n_env + 1;
            @(posedge clk_arm); pio_valid = 1;                       // fase 1
            @(posedge clk_arm); while (!ack) @(posedge clk_arm);     // fase 2: espera ack
            for (k = 0; k < segura; k = k + 1) @(posedge clk_arm);
            pio_valid = 0;                                           // fase 3
            @(posedge clk_arm); while (ack) @(posedge clk_arm);      // fase 4: ack baixa
        end
    endtask

    // ---------------- "UC": busca uma instrucao e confere o IR ----------------
    task uc_busca;
        begin
            @(negedge clk);
            busca = 1;
            @(posedge clk); #1;
            busca = 0;
            checa(ir_valido == 1, "ir_valido deveria pulsar apos a busca");
            checa(ir === enviadas[n_rec % 4096], "IR diferente da palavra enviada (ordem/perda)");
            n_rec = n_rec + 1;
            @(posedge clk); #1;
            checa(ir_valido == 0, "ir_valido deve durar so 1 ciclo");
        end
    endtask

    task espera_disponivel;              // espera ate ter instrucao na fila
        begin
            while (!instr_disponivel) @(posedge clk);
            #1;
        end
    endtask

    task aplica_reset;
        begin
            @(negedge clk); reset = 1; pio_valid = 0; busca = 0;
            repeat (2) @(negedge clk); reset = 0;
            n_env = 0; n_rec = 0;
        end
    endtask

    // Watchdog
    initial begin
        #5_000_000;
        $display("ERRO: tempo limite estourado (handshake travou?) n_env=%0d n_rec=%0d ack=%b valid=%b estado=%b count=%0d disp=%b", n_env, n_rec, ack, pio_valid, dut.estado, fifo_count, instr_disponivel);
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

    integer i, c0, total;
    reg [31:0] ir_antes;

    initial begin
        $dumpfile("tb_unidade_busca.vcd");
        $dumpvars(0, tb_unidade_busca);

        // ------------------------------------------------------------ 1
        inicio_teste("1. Estado apos reset");
        aplica_reset; #1;
        checa(ack == 0, "ack deveria ser 0");
        checa(fifo_empty == 1 && instr_disponivel == 0, "fila deveria estar vazia");
        checa(ir == 32'd0, "IR deveria iniciar em 0 (NOP)");
        checa(ir_valido == 0, "ir_valido deveria ser 0");
        fim_teste;

        // ------------------------------------------------------------ 2
        inicio_teste("2. ARM envia 1 palavra, UC busca para o IR");
        arm_envia(32'hC014B000, 0);
        checa(fifo_count == 1, "a palavra deveria estar na fila");
        uc_busca;
        checa(fifo_empty == 1, "a fila deveria ficar vazia apos a busca");
        fim_teste;

        // ------------------------------------------------------------ 3
        inicio_teste("3. Programa de exemplo (19 palavras) na ordem");
        for (i = 0; i < 19; i = i + 1) arm_envia(prog[i], 0);
        checa(fifo_count == 19, "deveria haver 19 palavras na fila");
        for (i = 0; i < 19; i = i + 1) uc_busca;
        fim_teste;

        // ------------------------------------------------------------ 4
        inicio_teste("4. Valid segurado muito tempo nao duplica a palavra");
        c0 = fifo_count;
        arm_envia(32'h1294C000, 60);       // valid fica 60 ciclos em 1 apos o ack
        checa(fifo_count == c0 + 1, "a palavra entrou mais de uma vez");
        uc_busca;
        fim_teste;

        // ------------------------------------------------------------ 5
        inicio_teste("5. Busca com fila vazia nao altera o IR");
        ir_antes = ir;
        @(negedge clk); busca = 1;
        @(posedge clk); #1; busca = 0;
        checa(ir == ir_antes, "IR mudou numa busca com fila vazia");
        checa(ir_valido == 0, "ir_valido nao pode pulsar com fila vazia");
        fim_teste;

        // ------------------------------------------------------------ 6
        inicio_teste("6. Fila cheia: ack segura ate abrir espaco");
        for (i = 0; i < 32; i = i + 1) arm_envia(32'hA0000000 + i, 0);
        checa(fifo_full == 1, "a fila deveria estar cheia com 32");
        fork
            arm_envia(32'hBBBBBBBB, 0);    // 33a palavra: deve esperar
            begin
                repeat (40) @(posedge clk); #1;
                checa(ack == 0, "ack nao pode subir com a fila cheia");
                checa(fifo_count == 32, "a 33a palavra nao pode entrar ainda");
                uc_busca;                  // abre uma vaga
            end
        join
        checa(fifo_count == 32, "a 33a palavra deveria entrar apos abrir vaga");
        for (i = 0; i < 32; i = i + 1) uc_busca;   // inclui conferir a 33a no fim
        checa(fifo_empty == 1, "a fila deveria terminar vazia");
        fim_teste;

        // ------------------------------------------------------------ 7
        inicio_teste("7. ARM e UC ao mesmo tempo (300 palavras aleatorias)");
        total = 300;
        c0 = n_rec + total;                // alvo: 300 palavras novas recebidas
        fork
            for (i = 0; i < total; i = i + 1)
                arm_envia($random, $random & 3);
            while (n_rec < c0) begin
                if ($random & 1) begin espera_disponivel; uc_busca; end
                else @(posedge clk);
            end
        join
        $display("  enviadas: %0d, recebidas: %0d (acumulado desde o reset)", n_env, n_rec);
        checa(n_env == n_rec, "quantidade enviada diferente da recebida");
        checa(fifo_empty == 1, "a fila deveria terminar vazia");
        fim_teste;

        // ------------------------------------------------------------ 8
        inicio_teste("8. Reset no meio do handshake");
        fork
            begin
                pio_instr = 32'h12345678; @(posedge clk_arm); pio_valid = 1;
            end
            begin
                repeat (6) @(posedge clk);
                aplica_reset; pio_valid = 0;
            end
        join
        repeat (4) @(posedge clk); #1;
        checa(ack == 0 && fifo_empty == 1, "reset deve zerar ack e a fila");
        checa(ir == 32'd0, "reset deve zerar o IR");
        arm_envia(32'h38000000, 0);        // volta a funcionar normalmente
        uc_busca;
        fim_teste;

        // ------------------------------------------------------------
        $display("--------------------------------------------");
        if (erros == 0) $display("RESULTADO: TODOS OS TESTES PASSARAM");
        else            $display("RESULTADO: %0d ERRO(S)", erros);
        $display("--------------------------------------------");
        $finish;
    end

endmodule
