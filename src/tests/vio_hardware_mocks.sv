`timescale 1ns/1ps
// Behavioral replacements used ONLY by tb_vio_uart_regression, never XPR.
module vio_0(input clk,
    output reg probe_out0=0,
    output reg [15:0] probe_out1=50, probe_out2=1000, probe_out3=800,
    output reg [15:0] probe_out4=10000, probe_out5=100, probe_out6=100,
    output reg [15:0] probe_out7=1500, probe_out8=700,
    output reg [31:0] probe_out9=10000,
    output reg [15:0] probe_out10=1000,
    output reg signed [31:0] probe_out11=0);
endmodule
module vio_pid(input clk,
    input [15:0] probe_in0, input probe_in1, probe_in2,
    input [15:0] probe_in3, probe_in4, probe_in5, probe_in6, input probe_in7,
    input [1:0] probe_in8, input probe_in9,
    output reg probe_out0=0,
    output reg [15:0] probe_out1=133, probe_out2=10, probe_out3=8,
    output reg [15:0] probe_out4=0, probe_out5=256,
    output reg probe_out6=0,
    output reg [7:0] probe_out7=3,
    output reg [15:0] probe_out8=1000,
    output reg [31:0] probe_out9=200,
    output reg probe_out10=1);
endmodule
module ila_capture(input clk,
    input [1:0] probe0, input [2:0] probe1, input [15:0] probe2,
    input probe3, input [15:0] probe4, probe5, probe6,
    input probe7, probe8, probe9, probe10, probe11, probe12, probe13, probe14,
    input [15:0] probe15, probe16,
    input probe17, probe18, probe19, probe20, probe21, probe22);
endmodule
module top_test(input clk_p, clk_n, fpga_clk_p, fpga_clk_n, adc_clk_p, adc_clk_n,
    input [15:0] data_in_nkt, data_in_aom,
    input [13:0] adc_data_p1, adc_data_n1,
    output clk_out_sync, output reg clocks_locked=0,
    output reg signed [15:0] pd_adc_sample=0, output reg pd_adc_sample_tick=0,
    output dac_frame_p, dac_frame_n, dac_dci_p, dac_dci_n,
    output [15:0] dac_data_p, dac_data_n,
    input key1, key2,
    output dac_spi_ce, adc_spi_ce, clk_spi_ce, spi_clk, inout spi_io);
    assign clk_out_sync=clk_p; // Testbench supplies the 25 MHz logic clock.
    assign {dac_frame_p,dac_frame_n,dac_dci_p,dac_dci_n}=0;
    assign dac_data_p=data_in_nkt;
    assign dac_data_n=data_in_aom;
    assign {dac_spi_ce,adc_spi_ce,clk_spi_ce,spi_clk}=0;
    assign spi_io=1'bz;
endmodule
