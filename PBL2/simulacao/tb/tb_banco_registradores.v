// ============================================================================
// tb_banco_registradores.v - testbench auto-verificavel do banco de registradores
// Rodar (na pasta simulacao):
//   iverilog -o sim tb/tb_banco_registradores.v ../quartus/rtl/banco_registradores.v && vvp sim
// ============================================================================
`timescale 1ns/1ps
module tb_banco_registradores;
    reg clk = 0, reset = 1, we = 0;
    reg [4:0] ra1 = 0, ra2 = 0, wa = 0;
    reg [15:0] wd = 0;
    wire [15:0] rd1, rd2;

    banco_registradores dut (.clk(clk), .reset(reset), .ra1(ra1), .ra2(ra2),
                             .rd1(rd1), .rd2(rd2), .we(we), .wa(wa), .wd(wd));
    always #20 clk = ~clk;

    reg [15:0] modelo [0:31];
    integer erros = 0, ea = 0, i, k;

    task checa(input c, input [8*60-1:0] m);
        begin if (!c) begin erros = erros + 1; $display("  ERRO @%0t: %0s", $time, m); end end
    endtask
    task inicio(input [8*60-1:0] n); begin ea = erros; $display("Teste: %0s", n); end endtask
    task fim; begin if (erros == ea) $display("  PASSOU"); else $display("  FALHOU (%0d)", erros - ea); end endtask

    task escreve(input [4:0] a, input [15:0] d);
        begin
            @(negedge clk); we = 1; wa = a; wd = d;
            @(negedge clk); we = 0;
            if (a != 0) modelo[a] = d;
        end
    endtask

    initial begin
        $dumpfile("tb_banco_registradores.vcd"); $dumpvars(0, tb_banco_registradores);
        for (i = 0; i < 32; i = i + 1) modelo[i] = 0;
        repeat (2) @(negedge clk); reset = 0;

        inicio("1. Todos os registradores em 0 apos reset");
        for (i = 0; i < 32; i = i + 1) begin ra1 = i; #1; checa(rd1 == 0, "registrador nao zerou"); end
        fim;

        inicio("2. Escrever e ler cada registrador (r1..r31)");
        for (i = 1; i < 32; i = i + 1) escreve(i, 16'h1000 + i * 3);
        for (i = 1; i < 32; i = i + 1) begin
            ra1 = i; ra2 = 32 - i; #1;
            checa(rd1 == modelo[i], "porta 1 leu valor errado");
            checa(rd2 == modelo[32 - i], "porta 2 leu valor errado");
        end
        fim;

        inicio("3. r0 sempre 0 (escrita ignorada)");
        escreve(0, 16'hFFFF);
        ra1 = 0; ra2 = 0; #1;
        checa(rd1 == 0 && rd2 == 0, "r0 deveria continuar 0");
        fim;

        inicio("4. Sem 'we' nada e escrito");
        @(negedge clk); we = 0; wa = 5; wd = 16'hDEAD; @(negedge clk);
        ra1 = 5; #1; checa(rd1 == modelo[5], "escreveu sem we");
        fim;

        inicio("5. Leitura combinacional (valor novo apos a borda)");
        @(negedge clk); we = 1; wa = 7; wd = 16'h0140; ra1 = 7;
        #1; checa(rd1 == modelo[7], "antes da borda ainda deve ser o valor antigo");
        @(posedge clk); #1; checa(rd1 == 16'h0140, "apos a borda deve mostrar o valor novo");
        we = 0; modelo[7] = 16'h0140;
        fim;

        inicio("6. 500 escritas/leituras aleatorias");
        for (k = 0; k < 500; k = k + 1) begin
            escreve($random, $random);
            ra1 = $random; ra2 = $random; #1;
            checa(rd1 == modelo[ra1] && rd2 == modelo[ra2], "divergiu do modelo");
        end
        fim;

        inicio("7. Reset zera tudo");
        @(negedge clk); reset = 1; @(negedge clk); reset = 0;
        for (i = 0; i < 32; i = i + 1) begin ra1 = i; #1; checa(rd1 == 0, "reset nao zerou"); end
        fim;

        $display("--------------------------------------------");
        if (erros == 0) $display("RESULTADO: TODOS OS TESTES PASSARAM");
        else $display("RESULTADO: %0d ERRO(S)", erros);
        $display("--------------------------------------------");
        $finish;
    end
endmodule
