// ============================================================================
// mef_demonstracao.v
// ============================================================================
module mef_demonstracao (
    input  wire [1:0] estado_sel,   // SW[9:8]
    input  wire       btn_update,   // KEY[1] 
    input  wire       btn_dir,      // KEY[2] 
    input  wire       btn_esq,      // KEY[3] 
    input  wire [7:0] chaves_dados, // SW[7:0]

    output reg        bg_update,
    output reg  [7:0] bg_dados,

    output reg        poly_update,
    output reg  [7:0] poly_dados,
    output reg        poly_mov_dir,
    output reg        poly_mov_esq,

    output reg        sprite_update,
    output reg  [7:0] sprite_dados,
    output reg        sprite_mov_dir,
    output reg        sprite_mov_esq
);

    always @(*) begin
        // Valores padrão (Prevenção de latches indesejados e Estado 00)
        bg_update      = 1'b0; 
        bg_dados       = 8'd0;

        poly_update    = 1'b0; 
        poly_dados     = 8'd0;
        poly_mov_dir   = 1'b0;  
        poly_mov_esq   = 1'b0;

        sprite_update  = 1'b0; 
        sprite_dados   = 8'd0;
        sprite_mov_dir = 1'b0; 
        sprite_mov_esq = 1'b0;

        // Roteamento baseado no Estado
        case (estado_sel)
            2'b00: begin
                // IDLE: Tudo zerado (valores padrão mantidos)
            end
            
            2'b01: begin
                // BACKGROUND
                bg_update = btn_update;
                bg_dados  = chaves_dados;
            end
            
            2'b10: begin
                // RASTERIZADOR (Polígonos)
                poly_update  = btn_update;
                poly_dados   = chaves_dados;
                poly_mov_dir = btn_dir;
                poly_mov_esq = btn_esq;
            end
            
            2'b11: begin
                // SPRITES
                sprite_update  = btn_update;
                sprite_dados   = chaves_dados;
                sprite_mov_dir = btn_dir;
                sprite_mov_esq = btn_esq;
            end
        endcase
    end
endmodule