`timescale 1ns / 1ps

module pd_adc_capture #(
    // Kept for top-level compatibility. This now controls raw-sample decimation,
    // not averaging or low-pass filtering.
    parameter integer AVG_BITS = 10,
    parameter integer ADC_LEFT_SHIFT = 2
)(
    input  wire        adc_clk,
    input  wire        logic_clk,
    input  wire        rst_n,
    input  wire [13:0] adc_raw,

    output reg  signed [15:0] pd_sample,
    output reg                pd_sample_tick,
    output reg  signed [15:0] pd_adc_debug
);

    reg [AVG_BITS-1:0] sample_cnt = {AVG_BITS{1'b0}};
    reg signed [15:0]  pd_sample_adc = 16'sd0;
    reg                pd_toggle_adc = 1'b0;

    wire signed [15:0] adc_signed_16 =
        ($signed({{2{adc_raw[13]}}, adc_raw}) <<< ADC_LEFT_SHIFT);

    wire adc_rst_n;
    wire logic_rst_n;
    reset_sync u_adc_reset (.clk(adc_clk), .arst_n(rst_n), .rst_n(adc_rst_n));
    reset_sync u_logic_reset (.clk(logic_clk), .arst_n(rst_n), .rst_n(logic_rst_n));

    always @(posedge adc_clk or negedge adc_rst_n) begin
        if (!adc_rst_n) begin
            sample_cnt    <= {AVG_BITS{1'b0}};
            pd_sample_adc <= 16'sd0;
            pd_toggle_adc <= 1'b0;
            pd_adc_debug  <= 16'sd0;
        end else if (sample_cnt == {AVG_BITS{1'b1}}) begin
            sample_cnt    <= {AVG_BITS{1'b0}};
            pd_sample_adc <= adc_signed_16;
            pd_adc_debug  <= adc_signed_16;
            pd_toggle_adc <= ~pd_toggle_adc;
        end else begin
            sample_cnt <= sample_cnt + 1'b1;
        end
    end

    (* ASYNC_REG = "TRUE" *) reg [2:0] pd_toggle_sync = 3'b000;
    reg        pd_toggle_seen = 1'b0;
    reg [2:0]  load_wait = 3'd0;

    always @(posedge logic_clk or negedge logic_rst_n) begin
        if (!logic_rst_n) begin
            pd_toggle_sync <= 3'b000;
            pd_toggle_seen <= 1'b0;
            load_wait      <= 3'd0;
            pd_sample      <= 16'sd0;
            pd_sample_tick <= 1'b0;
        end else begin
            pd_sample_tick <= 1'b0;
            pd_toggle_sync <= {pd_toggle_sync[1:0], pd_toggle_adc};

            if (pd_toggle_sync[2] != pd_toggle_seen) begin
                pd_toggle_seen <= pd_toggle_sync[2];
                load_wait      <= 3'd4;
            end else if (load_wait != 3'd0) begin
                load_wait <= load_wait - 1'b1;
                if (load_wait == 3'd1) begin
                    pd_sample      <= pd_sample_adc;
                    pd_sample_tick <= 1'b1;
                end
            end
        end
    end

endmodule
