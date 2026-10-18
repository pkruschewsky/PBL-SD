// ============================================================================
// tb_ula.v - testbench auto-verificavel da ULA
// Compara resultado e flags com um modelo calculado de forma independente
// (aritmetica com inteiros de 32 bits).
// Rodar (na pasta simulacao):
//   iverilog -o sim tb/tb_ula.v ../quartus/rtl/ula.v && vvp sim
// ============================================================================
`timescale 1ns/1ps
module tb_ula;
    reg  [15:0] a, b;
    reg  [1:0]  op;
    wire [15:0] r;
    wire [3:0]  f;
    ula dut (.a(a), .b(b), .op(op), .resultado(r), .flags(f));

    integer erros = 0, ea = 0, k;
    reg [15:0] er; reg en, ez, ec, ev;
    integer sa, sb, sr;                       // valores com sinal

    task modelo;
        begin
            sa = a[15] ? a - 65536 : a;
            sb = b[15] ? b - 65536 : b;
            ec = 0; ev = 0;
            case (op)
                2'b00: begin er = a + b; ec = (a + b) > 65535;       sr = sa + sb; ev = (sr > 32767) || (sr < -32768); end
                2'b01: begin er = a - b; ec = (a >= b);              sr = sa - sb; ev = (sr > 32767) || (sr < -32768); end
                2'b10: er = a & b;
                2'b11: er = a | b;
            endcase
            en = er[15]; ez = (er == 0);
        end
    endtask

    task testa(input [15:0] xa, input [15:0] xb, input [1:0] xop);
        begin
            a = xa; b = xb; op = xop; #1; modelo;
            if (r !== er || f !== {en, ez, ec, ev}) begin
                erros = erros + 1;
                $display("  ERRO: op=%0d a=%h b=%h -> r=%h f=%b (esperado r=%h f=%b)",
                         op, a, b, r, f, er, {en, ez, ec, ev});
            end
        end
    endtask

    task inicio(input [8*60-1:0] n); begin ea = erros; $display("Teste: %0s", n); end endtask
    task fim; begin if (erros == ea) $display("  PASSOU"); else $display("  FALHOU (%0d)", erros - ea); end endtask

    initial begin
        inicio("1. ADD: casos de borda (zero, vai-um, overflow)");
        testa(16'd100, 16'd2, 0);            // 102 (x do sprite + passo)
        testa(16'hFFFF, 16'd1, 0);           // 0 com vai-um: Z=1 C=1
        testa(16'h7FFF, 16'd1, 0);           // overflow positivo: V=1 N=1
        testa(16'h8000, 16'h8000, 0);        // overflow negativo: V=1 C=1 Z=1
        testa(16'd319, 16'hFFFE, 0);         // 319 + (-2) = 317
        fim;

        inicio("2. SUB: casos de borda (zero, emprestimo, overflow)");
        testa(16'd5, 16'd5, 1);              // 0: Z=1 C=1
        testa(16'd3, 16'd5, 1);              // -2: N=1 C=0 (emprestimo)
        testa(16'h8000, 16'd1, 1);           // overflow: V=1
        testa(16'h7FFF, 16'hFFFF, 1);        // 32767 - (-1): overflow
        fim;

        inicio("3. AND e OR");
        testa(16'hF0F0, 16'h0FF0, 2);
        testa(16'hF0F0, 16'h0F0F, 2);        // 0: Z=1
        testa(16'hF0F0, 16'h0F0F, 3);        // FFFF: N=1
        testa(16'h0000, 16'h0000, 3);        // 0: Z=1
        fim;

        inicio("4. 20000 operacoes aleatorias contra o modelo");
        for (k = 0; k < 20000; k = k + 1) testa($random, $random, $random);
        fim;

        $display("--------------------------------------------");
        if (erros == 0) $display("RESULTADO: TODOS OS TESTES PASSARAM");
        else $display("RESULTADO: %0d ERRO(S)", erros);
        $display("--------------------------------------------");
        $finish;
    end
endmodule
