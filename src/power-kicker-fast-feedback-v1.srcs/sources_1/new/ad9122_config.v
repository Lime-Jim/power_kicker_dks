`timescale 1ns / 1ps

module ad9122_config(
    input[9:0]             lut_index,   //Look-up table address
	output reg[15:0]       lut_data     //reg address reg data
);

always@(*)
begin
	case(lut_index)			  
		10'd   0: lut_data <= {1'h0,7'h00,8'hA0};  //80
		10'd   1: lut_data <= {1'h0,7'h00,8'h80};  //80		
		10'd   2: lut_data <= {1'h0,7'h03,8'h00};  
		10'd   3: lut_data <= {1'h0,7'h04,8'h00};  
		10'd   4: lut_data <= {1'h0,7'h05,8'h00};   
		10'd   5: lut_data <= {1'h0,7'h08,8'hA0};  
		10'd   6: lut_data <= {1'h0,7'h0A,8'h00};  
		10'd   7: lut_data <= {1'h0,7'h0C,8'h00};  
		10'd   8: lut_data <= {1'h0,7'h0D,8'h00};  
		10'd   9: lut_data <= {1'h0,7'h10,8'h00};  
		10'd  10: lut_data <= {1'h0,7'h11,8'h00};  
		10'd  11: lut_data <= {1'h0,7'h16,8'h00};  
		10'd  12: lut_data <= {1'h0,7'h1B,8'hE4};  // bypass inverse sinc filter
		10'd  13: lut_data <= {1'h0,7'h1C,8'h01};  // bypass HB1 interpolation filter
		10'd  14: lut_data <= {1'h0,7'h1D,8'h01}; 
		10'd  15: lut_data <= {1'h0,7'h1E,8'h01}; 		
		10'd  16: lut_data <= {1'h0,7'h10,8'h48}; 	
		10'd  17: lut_data <= {1'h0,7'h17,8'h05}; 
		10'd  18: lut_data <= {1'h0,7'h18,8'h02}; 
		10'd  19: lut_data <= {1'h0,7'h18,8'h00};
		// AD9122 full-scale current adjust:
		// I/Q DAC gain code = 10'h3FF, about 31.7 mA max full-scale current.
		// Registers 0x40/0x41 control I DAC, 0x44/0x45 control Q DAC.
		10'd  20: lut_data <= {1'h0,7'h40,8'hFF};
		10'd  21: lut_data <= {1'h0,7'h41,8'h03};
		10'd  22: lut_data <= {1'h0,7'h44,8'hFF};
		10'd  23: lut_data <= {1'h0,7'h45,8'h03};					
		default:lut_data <= {8'hff,8'hff};
	endcase
end


endmodule 
