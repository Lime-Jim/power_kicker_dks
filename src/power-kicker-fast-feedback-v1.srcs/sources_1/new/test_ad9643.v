`timescale 1ns / 1ps

module test_ad9643(
    
    input adc_clk_p,
    input adc_clk_n,
    output adc_clk_oeb,
    output adc_clk_pwn,        
    
    output      adc_clk,
    output reg [13:0] adc_data_a_out,
    output reg [13:0] adc_data_b_out,
    input [13:0]adc_data_p,
    input [13:0]adc_data_n
   
);
//////////////////////////////////////////////////////////////////////////////////// 
wire                            adc_clk_ibuf;
wire[13:0]                      adc_data;
wire[13:0]                      adc_data_a;
wire[13:0]                      adc_data_b;
(* MARK_DEBUG="true" *)reg[13:0] adc_data_a_d0;
(* MARK_DEBUG="true" *)reg[13:0] adc_data_b_d0;

assign adc_clk_oeb=0;
assign adc_clk_pwn=0;    
//////////////////////////////////////////////////////////////////////////////////// 
IBUFDS IBUFDS_adc_clk (
	.O   (adc_clk_ibuf),  // Buffer output
	.I   (adc_clk_p),  // Diff_p buffer input (connect directly to top-level port)
	.IB  (adc_clk_n) // Diff_n buffer input (connect directly to top-level port)
);

BUFG CLK_B0(.I(adc_clk_ibuf),.O(adc_clk));


genvar i;
generate
	for (i = 0; i < 14; i = i + 1)
	 begin:ad_data
	
		  IBUFDS #(
           .DIFF_TERM("FALSE"),       // Differential Termination
           .IBUF_LOW_PWR("TRUE"),     // Low power="TRUE", Highest performance="FALSE" 
           .IOSTANDARD("DEFAULT")     // Specify the input I/O standard
		  ) adc_data1 (
           .O(adc_data[i]),  // Buffer output
           .I(adc_data_p[i]),  // Diff_p buffer input (connect directly to top-level port)
           .IB(adc_data_n[i]) // Diff_n buffer input (connect directly to top-level port)
        );
	

  IDDRE1 #(
          .DDR_CLK_EDGE("SAME_EDGE_PIPELINED"), // IDDRE1 mode (OPPOSITE_EDGE, SAME_EDGE, SAME_EDGE_PIPELINED)
          .IS_CB_INVERTED(1'b0),          // Optional inversion for CB
          .IS_C_INVERTED(1'b0)            // Optional inversion for C
       )
       IDDRE1_inst (
           .Q1(adc_data_a[i]), // 1-bit output for positive edge of clock 
           .Q2(adc_data_b[i]), // 1-bit output for negative edge of clock
           .C(adc_clk),   // 1-bit clock input
           .CB(!adc_clk), // 1-bit input: Inversion of High-speed clock C
           .D(adc_data[i]),   // 1-bit DDR data input
           .R(1'b0)    // 1-bit reset
       );		
		
	end
endgenerate

always@(posedge adc_clk)
begin
	adc_data_a_d0 <= adc_data_a;
	adc_data_b_d0 <= adc_data_b;
	adc_data_a_out <= adc_data_a;
	adc_data_b_out <= adc_data_b;
end
  
endmodule
