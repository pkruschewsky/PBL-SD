// ============================================================================
// tb_restaura_tilemap.v - testa o restaura_tilemap sozinho
//
//   1. Depois do reset, faz exatamente 1200 escritas, uma em cada endereco
//      0..1199, com o valor do mapa inicial daquele endereco
//   2. "ocupado" fica em 1 do reset ate a ultima escrita, e cai logo depois
//   3. Nao escreve nada enquanto o reset esta ativo
//   4. Reset no MEIO da copia: recomeca do zero e termina certo
//   5. Fora do reset, fica parado (nenhuma escrita extra)
//
// Rodar (na pasta simulacao, com os .hex de sim_modelos/ copiados para ela):
//   iverilog -o sim tb/tb_restaura_tilemap.v ../quartus/rtl/restaura_tilemap.v sim_modelos/modelos_memorias.v && vvp sim
// ============================================================================
`timescale 1ns/1ps
module tb_restaura_tilemap;
    reg clk = 0;
    always #20 clk = ~clk;                       // 25 MHz
    reg reset = 1;

    wire [10:0] rom_addr;  wire [7:0] rom_data;
    wire        we;        wire [10:0] wr_addr; wire [7:0] wr_data;
    wire        ocupado;

    rom_mapa_inicial u_rom (.address(rom_addr), .clock(clk), .rden(1'b1), .q(rom_data));
    restaura_tilemap dut (
        .clk(clk), .reset(reset), .rom_addr(rom_addr), .rom_data(rom_data),
        .we(we), .wr_addr(wr_addr), .wr_data(wr_data), .ocupado(ocupado)
    );

    reg [7:0] esperado [0:2047];
    reg [7:0] ram [0:2047];
    integer escritas = 0, fora_ordem = 0, errados = 0, durante_reset = 0, prox = 0;
    integer i, ciclos;
    initial $readmemh("mapa_inicial.hex", esperado, 0, 1199);

    always @(posedge clk) begin
        if (we) begin
            ram[wr_addr] <= wr_data;
            escritas = escritas + 1;
            if (reset) durante_reset = durante_reset + 1;
            if (wr_addr != prox) fora_ordem = fora_ordem + 1;
            if (wr_data !== esperado[wr_addr]) errados = errados + 1;
            prox = wr_addr + 1;
        end
    end

    integer erros = 0, ea = 0;
    task checa(input c, input [8*64-1:0] m);
        begin if (!c) begin erros = erros + 1; $display("  ERRO: %0s", m); end end
    endtask
    task inicio(input [8*64-1:0] n); begin ea = erros; $display("Teste: %0s", n); end endtask
    task fim; begin if (erros == ea) $display("  PASSOU"); else $display("  FALHOU"); end endtask
    task zera; begin escritas = 0; fora_ordem = 0; errados = 0; durante_reset = 0; prox = 0; end endtask

    initial begin
        for (i = 0; i < 2048; i = i + 1) ram[i] = 8'hEE;   // lixo: tudo tem que ser sobrescrito

        inicio("1-3. Copia completa apos o reset");
        repeat (5) @(posedge clk);
        checa(ocupado == 1, "ocupado deveria ser 1 durante o reset");
        checa(escritas == 0, "nao pode escrever durante o reset");
        @(negedge clk) reset = 0;
        ciclos = 0;
        while (ocupado) begin @(posedge clk); #1; ciclos = ciclos + 1; end
        $display("  %0d escritas, %0d ciclos ocupado, %0d fora de ordem, %0d com valor errado",
                 escritas, ciclos, fora_ordem, errados);
        checa(escritas == 1200, "deveria fazer 1200 escritas");
        checa(fora_ordem == 0, "enderecos deveriam ser 0,1,2...1199");
        checa(errados == 0, "valores deveriam ser os do mapa inicial");
        checa(ciclos >= 1200 && ciclos <= 1204, "ocupado deveria durar ~1202 ciclos");
        errados = 0;
        for (i = 0; i < 1200; i = i + 1) if (ram[i] !== esperado[i]) errados = errados + 1;
        checa(errados == 0, "RAM final diferente do mapa inicial");
        fim;

        inicio("4. Reset no meio da copia recomeca do zero");
        @(negedge clk) reset = 1;
        repeat (3) @(posedge clk);
        @(negedge clk) reset = 0;
        repeat (500) @(posedge clk);                 // copia pela metade
        @(negedge clk) reset = 1;
        for (i = 0; i < 2048; i = i + 1) ram[i] = 8'hEE;
        zera;
        repeat (3) @(posedge clk);
        @(negedge clk) reset = 0;
        while (ocupado) @(posedge clk);
        repeat (2) @(posedge clk);
        errados = 0;
        for (i = 0; i < 1200; i = i + 1) if (ram[i] !== esperado[i]) errados = errados + 1;
        $display("  %0d escritas apos o 2o reset, %0d posicoes erradas", escritas, errados);
        checa(escritas == 1200 && fora_ordem == 0 && errados == 0, "copia apos reset no meio falhou");
        checa(durante_reset == 0, "escreveu durante o reset");
        fim;

        inicio("5. Parado depois de terminar");
        zera;
        repeat (3000) @(posedge clk);
        checa(escritas == 0 && ocupado == 0, "nao deveria escrever nem ficar ocupado");
        fim;

        if (erros == 0) $display("RESULTADO: TODOS OS TESTES PASSARAM");
        else            $display("RESULTADO: %0d ERRO(S)", erros);
        $finish;
    end
endmodule
