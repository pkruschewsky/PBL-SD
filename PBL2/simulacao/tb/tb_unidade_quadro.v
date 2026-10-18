// ============================================================================
// tb_unidade_quadro.v - testbench auto-verificavel da unidade de quadro
// Usa o vga_driver real (saida v_ativo) para gerar quadros.
// Rodar (na pasta simulacao):
//   iverilog -o sim tb/tb_unidade_quadro.v ../quartus/rtl/unidade_quadro.v ../quartus/rtl/vga_driver.v && vvp sim
// ============================================================================
`timescale 1ns/1ps
module tb_unidade_quadro;
    reg clk = 0, reset = 1;
    always #20 clk = ~clk;                   // 25 MHz

    wire [9:0] nx, ny;
    wire hs, vs, sy, ck, bl, v_ativo;
    wire [7:0] r, g, b;
    vga_driver vga (.clock(clk), .reset(reset), .color_in(8'd0), .next_x(nx), .next_y(ny),
                    .hsync(hs), .vsync(vs), .red(r), .green(g), .blue(b), .sync(sy),
                    .clk(ck), .blank(bl), .v_ativo(v_ativo));

    wire vblank, inicio;
    wire [15:0] quadros;
    unidade_quadro dut (.clk(clk), .reset(reset), .v_ativo(v_ativo),
                        .vblank(vblank), .inicio_vblank(inicio), .contador_quadros(quadros));

    integer erros = 0, pulsos = 0, largura = 0, ciclos_vblank = 0, ciclos = 0;
    real t0, t1;

    always @(posedge clk) if (!reset) begin
        ciclos = ciclos + 1;
        if (inicio) begin
            pulsos = pulsos + 1;
            if (pulsos == 2) t0 = $realtime;
            if (pulsos == 3) t1 = $realtime;
        end
    end

    initial begin
        $dumpfile("tb_unidade_quadro.vcd"); $dumpvars(0, tb_unidade_quadro);
        repeat (3) @(negedge clk); reset = 0;

        // 3 quadros completos + folga (800 x 525 ciclos por quadro)
        repeat (800 * 525 * 3 + 1000) @(posedge clk);

        $display("Teste: 1. Um pulso de inicio_vblank por quadro");
        if (pulsos >= 3 && quadros == pulsos) $display("  PASSOU (%0d quadros)", pulsos);
        else begin erros = erros + 1; $display("  FALHOU: pulsos=%0d contador=%0d", pulsos, quadros); end

        $display("Teste: 2. Intervalo entre pulsos = 1 quadro (800 x 525 ciclos = 16,8 ms)");
        if ((t1 - t0) == 800.0 * 525.0 * 40.0) $display("  PASSOU (%0.3f ms)", (t1 - t0) / 1e6);
        else begin erros = erros + 1; $display("  FALHOU: %0.0f ns", t1 - t0); end

        $display("Teste: 3. vblank dura 45 linhas (36000 ciclos) por quadro");
        @(posedge inicio); ciclos_vblank = 0;
        while (vblank) begin @(posedge clk); ciclos_vblank = ciclos_vblank + 1; end
        if (ciclos_vblank >= 35990 && ciclos_vblank <= 36010) $display("  PASSOU (%0d ciclos)", ciclos_vblank);
        else begin erros = erros + 1; $display("  FALHOU: %0d ciclos", ciclos_vblank); end

        $display("Teste: 4. Pulso dura exatamente 1 ciclo");
        @(posedge inicio); @(posedge clk); #1;
        if (inicio == 0) $display("  PASSOU");
        else begin erros = erros + 1; $display("  FALHOU"); end

        $display("--------------------------------------------");
        if (erros == 0) $display("RESULTADO: TODOS OS TESTES PASSARAM");
        else $display("RESULTADO: %0d ERRO(S)", erros);
        $display("--------------------------------------------");
        $finish;
    end
endmodule
