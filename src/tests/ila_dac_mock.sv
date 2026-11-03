`timescale 1ns / 1ps

// Only the passive debug IP is replaced; DAC I/O primitives use unisims_ver.
module ila_1 (
    input wire clk,
    input wire [15:0] probe0,
    input wire [15:0] probe1,
    input wire [31:0] probe2,
    input wire [15:0] probe3
);
endmodule
