// ============================================================================
// motor_background.v
// Le a posicao logica do pixel, aplica scroll, consulta o tilemap e 
// envia o endereço para a ROM Dual-Port externa.
// ============================================================================
module motor_background (
    input  wire        clk,
    input  wire [9:0]  next_x,
    input  wire [9:0]  next_y,
    input  wire [8:0]  scroll_x,
    input  wire [7:0]  scroll_y,

    input  wire        tm_wr_en,
    input  wire [10:0] tm_wr_addr,
    input  wire [7:0]  tm_wr_data,

    // Conexão com a ROM Externa (Dual-Port)
    output wire [13:0] rom_addr, 
    input  wire [7:0]  rom_data, 

    output wire [7:0]  cor_pixel
);

    wire [8:0] logical_x = next_x[9:1];
    wire [7:0] logical_y = next_y[9:1];

    wire [9:0] scrolled_x_full = logical_x + scroll_x;
    wire [8:0] scrolled_y_full = logical_y + scroll_y;

    wire [8:0] scrolled_x = (scrolled_x_full >= 10'd320) ?
                             (scrolled_x_full - 10'd320) : scrolled_x_full[8:0];
    wire [7:0] scrolled_y = (scrolled_y_full >= 9'd240) ?
                             (scrolled_y_full - 9'd240) : scrolled_y_full[7:0];

    wire [5:0] tile_col = scrolled_x[8:3];
    wire [4:0] tile_row = scrolled_y[7:3];
    wire [2:0] pixel_x  = scrolled_x[2:0];
    wire [2:0] pixel_y  = scrolled_y[2:0];

    wire [10:0] tilemap_addr = (tile_row * 11'd40) + tile_col;
    wire [7:0] tile_id;

    motor_tilemap u_tilemap (
        .endereco_leitura (tilemap_addr),
        .endereco_escrita (tm_wr_addr),
        .dado_escrita     (tm_wr_data),
        .escreve          (tm_wr_en),
        .clk              (clk),
        .tile_id          (tile_id)
    );

    reg [2:0] pixel_x_r, pixel_y_r;
    always @(posedge clk) begin
        pixel_x_r <= pixel_x;
        pixel_y_r <= pixel_y;
    end

    // Manda o endereço para a Porta A da ROM lá no top_video
    assign rom_addr = {tile_id, pixel_y_r, pixel_x_r};

    // A cor final recebe o dado que voltou da ROM
    assign cor_pixel = rom_data;

endmodule