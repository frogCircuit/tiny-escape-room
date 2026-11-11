/*
 * Hardware idea: a combinational decoder from a digit to seven-segment
 * patterns. seg_out[6:0] = segments a..g (active high), seg_out[7] = decimal
 * point. Digit 4'hF shows the letter F (flag).
 */
`default_nettype none

module display (
    input  wire [3:0] digit,
    input  wire       dp,
    output wire [7:0] seg_out
);
  reg [6:0] seg;  // {g,f,e,d,c,b,a}

  always @* begin
    case (digit)
      4'd0:    seg = 7'b0111111;
      4'd1:    seg = 7'b0000110;
      4'd2:    seg = 7'b1011011;
      4'd3:    seg = 7'b1001111;
      4'd4:    seg = 7'b1100110;
      4'd5:    seg = 7'b1101101;
      4'd6:    seg = 7'b1111101;
      4'd7:    seg = 7'b0000111;
      4'd8:    seg = 7'b1111111;
      4'd9:    seg = 7'b1101111;
      4'hF:    seg = 7'b1110001;
      default: seg = 7'b0000000;
    endcase
  end

  assign seg_out = {dp, seg};
endmodule
