// ============================================================================
// clock_divider.v
// Divisor de clock por 2 (toggle flip-flop): 50 MHz -> 25 MHz.
// ============================================================================
module clock_divider (
	input  wire clk_in,   // 50 MHz
	input  wire reset,    // ativo alto
	output reg  clk_out   // 25 MHz
	);

	always @(posedge clk_in or posedge reset) begin
		if (reset)
			clk_out <= 1'b0;
		else
			clk_out <= ~clk_out;
	end

endmodule