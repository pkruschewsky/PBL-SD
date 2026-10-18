// ============================================================================
// modelos_memorias.v  -  SOMENTE PARA SIMULACAO (nao vai para o Quartus)
//
// O simulador nao tem os blocos de memoria da Intel (altsyncram). Estes
// modelos tem as MESMAS portas e a MESMA latencia das IPs de memoria do projeto Quartus:
//   ram_tilemap      : dual-port, endereco de leitura registrado,
//                      saida nao registrada        -> 1 ciclo de latencia
//   rom_cenario_tile : endereco e saida registrados -> 2 ciclos de latencia
//   rom_sprites      : endereco e saida registrados -> 2 ciclos de latencia
//   rom_mapa_inicial : endereco e saida registrados -> 2 ciclos de latencia
// O conteudo inicial vem dos mesmos .mif do projeto Quartus, convertidos
// para .hex (uma palavra por linha, formato lido pelo $readmemh).
// ============================================================================
`timescale 1ns/1ps

module ram_tilemap (
    input  wire        clock,
    input  wire [7:0]  data,
    input  wire [10:0] rdaddress,
    input  wire [10:0] wraddress,
    input  wire        wren,
    output wire [7:0]  q
);
    reg [7:0]  mem [0:2047];
    reg [10:0] rd_r;
    initial $readmemh("mapa_inicial.hex", mem, 0, 1199);
    always @(posedge clock) begin
        if (wren) mem[wraddress] <= data;
        rd_r <= rdaddress;
    end
    assign q = mem[rd_r];
endmodule

module rom_cenario_tile (
    input  wire [13:0] address,
    input  wire        clock,
    input  wire        rden,
    output reg  [7:0]  q
);
    reg [7:0]  mem [0:16383];
    reg [13:0] a_r;
    initial $readmemh("bg_tiles.hex", mem);
    always @(posedge clock) begin
        a_r <= address;
        q   <= mem[a_r];
    end
endmodule

module rom_sprites (
    input  wire [12:0] address,
    input  wire        clock,
    input  wire        rden,
    output reg  [7:0]  q
);
    reg [7:0]  mem [0:8191];
    reg [12:0] a_r;
    initial $readmemh("sprites_rom.hex", mem);
    always @(posedge clock) begin
        a_r <= address;
        q   <= mem[a_r];
    end
endmodule

module rom_mapa_inicial (
    input  wire [10:0] address,
    input  wire        clock,
    input  wire        rden,
    output reg  [7:0]  q
);
    reg [7:0]  mem [0:2047];
    reg [10:0] a_r;
    initial $readmemh("mapa_inicial.hex", mem, 0, 1199);
    always @(posedge clock) begin
        a_r <= address;
        q   <= mem[a_r];
    end
endmodule
