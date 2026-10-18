// ============================================================================
// tb_fifo_instr.v
// Testbench auto-verificavel da fila de instrucoes.
//
// Um modelo de referencia (vetor 'modelo' + contadores) guarda o que a fila
// DEVERIA conter. A cada leitura, 'dout' e comparado com o modelo.
// Ao final imprime o total de erros: 0 erros = todos os testes passaram.
//
// Rodar (na pasta simulacao):
//   iverilog -o sim tb/tb_fifo_instr.v ../quartus/rtl/fifo_instr.v && vvp sim
// Formas de onda: tb_fifo_instr.vcd (GTKWave).
// ============================================================================
`timescale 1ns/1ps

module tb_fifo_instr;

    localparam WIDTH = 32, DEPTH = 32, AW = 5;

    reg              clk = 0;
    reg              reset = 1;
    reg              wr_en = 0, rd_en = 0;
    reg  [WIDTH-1:0] din = 0;
    wire [WIDTH-1:0] dout;
    wire             empty, full;
    wire [AW:0]      count;

    fifo_instr #(.WIDTH(WIDTH), .DEPTH(DEPTH), .AW(AW)) dut (
        .clk(clk), .reset(reset),
        .wr_en(wr_en), .din(din),
        .rd_en(rd_en), .dout(dout),
        .empty(empty), .full(full), .count(count)
    );

    always #20 clk = ~clk;              // 25 MHz (periodo de 40 ns)

    // ---------------- modelo de referencia ----------------
    reg [WIDTH-1:0] modelo [0:1023];
    integer m_wr = 0, m_rd = 0;         // indices de escrita/leitura do modelo
    integer erros = 0, erros_antes = 0;

    // ---------------- utilitarios ----------------
    task checa(input cond, input [8*64-1:0] msg);
        begin
            if (!cond) begin
                erros = erros + 1;
                $display("  ERRO @%0t: %0s (count=%0d empty=%b full=%b dout=%h)",
                         $time, msg, count, empty, full, dout);
            end
        end
    endtask

    task inicio_teste(input [8*64-1:0] nome);
        begin
            erros_antes = erros;
            $display("Teste: %0s", nome);
        end
    endtask

    task fim_teste;
        begin
            if (erros == erros_antes) $display("  PASSOU");
            else                      $display("  FALHOU (%0d erros)", erros - erros_antes);
        end
    endtask

    // Um ciclo de clock com wr/rd escolhidos. As entradas mudam na borda de
    // descida para nao disputar com a borda de subida (onde a fila amostra).
    task ciclo(input w, input r, input [WIDTH-1:0] dado);
        reg aceita_w, aceita_r;
        begin
            @(negedge clk);
            wr_en = w; rd_en = r; din = dado;
            aceita_w = w && !full;
            aceita_r = r && !empty;
            if (aceita_r) begin
                checa(dout === modelo[m_rd % 1024], "dout diferente do esperado na leitura");
                m_rd = m_rd + 1;
            end
            if (aceita_w) begin
                modelo[m_wr % 1024] = dado;
                m_wr = m_wr + 1;
            end
            @(posedge clk); #1;
            wr_en = 0; rd_en = 0;
            checa(count == (m_wr - m_rd), "count diferente do modelo");
            checa(empty == (m_wr == m_rd), "empty incorreto");
            checa(full  == ((m_wr - m_rd) == DEPTH), "full incorreto");
            if (m_wr != m_rd)
                checa(dout === modelo[m_rd % 1024], "dout nao mostra a instrucao mais antiga");
        end
    endtask

    task aplica_reset;
        begin
            @(negedge clk); reset = 1;
            @(negedge clk); reset = 0;
            m_wr = 0; m_rd = 0;
        end
    endtask

    integer i, n;
    reg w, r;

    // Watchdog: se algum laco travar (ex.: 'full' nunca liga), encerra com erro
    initial begin
        #2_000_000;
        $display("ERRO: tempo limite da simulacao estourado (algum laco travou)");
        $display("RESULTADO: FALHOU POR TIMEOUT");
        $finish;
    end

    initial begin
        $dumpfile("tb_fifo_instr.vcd");
        $dumpvars(0, tb_fifo_instr);

        // ---------------------------------------------------------- 1
        inicio_teste("1. Estado apos reset");
        aplica_reset;
        #1;
        checa(empty == 1, "deveria estar vazia");
        checa(full  == 0, "nao deveria estar cheia");
        checa(count == 0, "count deveria ser 0");
        fim_teste;

        // ---------------------------------------------------------- 2
        inicio_teste("2. Escrita unica aparece direto em dout");
        ciclo(1, 0, 32'hC014B000);          // SPR_POS 0, r10, r11
        checa(dout == 32'hC014B000, "dout deveria mostrar a palavra escrita");
        fim_teste;

        // ---------------------------------------------------------- 3
        inicio_teste("3. Leitura esvazia a fila");
        ciclo(0, 1, 0);
        checa(empty == 1, "deveria voltar a ficar vazia");
        fim_teste;

        // ---------------------------------------------------------- 4
        inicio_teste("4. Encher as 32 posicoes e tentar a 33a");
        for (i = 0; i < DEPTH; i = i + 1)
            ciclo(1, 0, 32'hA0000000 + i);
        checa(full == 1 && count == DEPTH, "deveria estar cheia com 32");
        ciclo(1, 0, 32'hDEADBEEF);          // deve ser ignorada
        checa(count == DEPTH, "escrita com fila cheia nao pode entrar");
        fim_teste;

        // ---------------------------------------------------------- 5
        inicio_teste("5. Esvaziar e conferir a ordem (FIFO)");
        for (i = 0; i < DEPTH; i = i + 1)
            ciclo(0, 1, 0);
        checa(empty == 1, "deveria estar vazia apos 32 leituras");
        fim_teste;

        // ---------------------------------------------------------- 6
        inicio_teste("6. Leitura com fila vazia e ignorada");
        ciclo(0, 1, 0);
        ciclo(0, 1, 0);
        checa(count == 0 && empty == 1, "leitura vazia nao pode mexer nos ponteiros");
        ciclo(1, 0, 32'h38000000);          // WAITV
        checa(dout == 32'h38000000, "depois de leituras vazias a escrita deve funcionar");
        ciclo(0, 1, 0);
        fim_teste;

        // ---------------------------------------------------------- 7
        inicio_teste("7. Escrita e leitura no mesmo ciclo");
        ciclo(1, 0, 32'h11111111);
        ciclo(1, 0, 32'h22222222);
        ciclo(1, 0, 32'h33333333);
        for (i = 0; i < 10; i = i + 1)
            ciclo(1, 1, 32'hB0000000 + i);  // count deve continuar em 3
        checa(count == 3, "count deveria ficar constante em 3");
        fim_teste;

        // ---------------------------------------------------------- 8
        inicio_teste("8. Cheia + escrita e leitura juntas");
        while (!full) ciclo(1, 0, 32'hC0000000 + m_wr);
        ciclo(1, 1, 32'hFFFFFFFF);          // le 1; a escrita e ignorada (estava cheia)
        checa(count == DEPTH - 1, "com fila cheia so a leitura deve acontecer");
        while (!empty) ciclo(0, 1, 0);
        fim_teste;

        // ---------------------------------------------------------- 9
        inicio_teste("9. Trafego aleatorio (2000 ciclos, varias voltas)");
        n = 0;
        for (i = 0; i < 2000; i = i + 1) begin
            w = ($random & 3) != 0;         // ~75% de chance de escrever
            r = ($random & 1);              // ~50% de chance de ler
            ciclo(w, r, $random);
        end
        $display("  palavras escritas: %0d, lidas: %0d", m_wr, m_rd);
        while (!empty) ciclo(0, 1, 0);
        fim_teste;

        // ---------------------------------------------------------- 10
        inicio_teste("10. Reset no meio da operacao");
        for (i = 0; i < 5; i = i + 1) ciclo(1, 0, i);
        aplica_reset;
        #1;
        checa(empty == 1 && count == 0, "reset deve esvaziar a fila");
        fim_teste;

        // ----------------------------------------------------------
        $display("--------------------------------------------");
        if (erros == 0) $display("RESULTADO: TODOS OS TESTES PASSARAM");
        else            $display("RESULTADO: %0d ERRO(S)", erros);
        $display("--------------------------------------------");
        $finish;
    end

endmodule
