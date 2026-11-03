`timescale 1ns / 1ps

// Reserved legacy UART shadow register bank. ACK echoes the address only;
// it does NOT acknowledge applying a value to the DAC or PID. The active
// top-level has VIO as its only parameter source. Legacy *_ms units are kept
// for wire compatibility; future activation requires explicit unit conversion.
module uart_power_kick_params #(
    parameter CLK_FRE = 25
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        uart_rx_pin,
    output wire        uart_tx_pin,

    output reg  [15:0] dac1_start_code,
    output reg  [15:0] dac1_kick_code,
    output reg  [31:0] dac1_scan_ms,
    output reg  [15:0] dac2_base_code,
    output reg  [15:0] dac2_min_code,
    output reg  [15:0] dac2_fall_ms,
    output reg  [15:0] dac2_rise_ms,

    output reg         pid_enable,
    output reg  signed [15:0] pid_target_code,
    output reg  signed [15:0] pid_window_code,
    output reg  signed [15:0] pid_kp,
    output reg  signed [15:0] pid_ki,
    output reg  signed [15:0] pid_kd,
    output reg  [15:0]        pid_corr_limit,

    output reg  [7:0]  last_addr,
    output reg         update_tick
);

    localparam [7:0] FRAME_HEAD = 8'hA5;

    localparam [7:0] ADDR_DAC1_START = 8'h00;
    localparam [7:0] ADDR_DAC1_KICK  = 8'h01;
    localparam [7:0] ADDR_SCAN_MS    = 8'h02;
    localparam [7:0] ADDR_DAC2_BASE  = 8'h03;
    localparam [7:0] ADDR_DAC2_MIN   = 8'h04;
    localparam [7:0] ADDR_FALL_MS    = 8'h05;
    localparam [7:0] ADDR_RISE_MS    = 8'h06;
    localparam [7:0] ADDR_PID_EN     = 8'h10;
    localparam [7:0] ADDR_PID_TARGET = 8'h11;
    localparam [7:0] ADDR_PID_WINDOW = 8'h12;
    localparam [7:0] ADDR_PID_KP     = 8'h13;
    localparam [7:0] ADDR_PID_KI     = 8'h14;
    localparam [7:0] ADDR_PID_KD     = 8'h15;
    localparam [7:0] ADDR_PID_LIMIT  = 8'h16;

    localparam S_WAIT_HEAD = 3'd0;
    localparam S_ADDR      = 3'd1;
    localparam S_D3        = 3'd2;
    localparam S_D2        = 3'd3;
    localparam S_D1        = 3'd4;
    localparam S_D0        = 3'd5;
    localparam S_ACK       = 3'd6;

    wire [7:0] rx_data;
    wire       rx_data_valid;

    uart_rx #(.CLK_FRE(CLK_FRE), .BAUD_RATE(115200)) u_rx (
        .clk           (clk),
        .rst_n         (rst_n),
        .rx_data       (rx_data),
        .rx_data_valid (rx_data_valid),
        .rx_data_ready (1'b1),
        .rx_pin        (uart_rx_pin)
    );

    reg [7:0] tx_data;
    reg       tx_data_valid;
    wire      tx_data_ready;

    uart_tx #(.CLK_FRE(CLK_FRE), .BAUD_RATE(115200)) u_tx (
        .clk           (clk),
        .rst_n         (rst_n),
        .tx_data       (tx_data),
        .tx_data_valid (tx_data_valid),
        .tx_data_ready (tx_data_ready),
        .tx_pin        (uart_tx_pin)
    );

    reg [2:0]  state;
    reg [31:0] data_word;

    task apply_param;
        input [7:0]  addr;
        input [31:0] value;
        begin
            case (addr)
                ADDR_DAC1_START: dac1_start_code <= value[15:0];
                ADDR_DAC1_KICK:  dac1_kick_code  <= value[15:0];
                ADDR_SCAN_MS:    dac1_scan_ms    <= (value == 32'd0) ? 32'd1 : value;
                ADDR_DAC2_BASE:  dac2_base_code  <= value[15:0];
                ADDR_DAC2_MIN:   dac2_min_code   <= value[15:0];
                ADDR_FALL_MS:    dac2_fall_ms    <= (value[15:0] == 16'd0) ? 16'd1 : value[15:0];
                ADDR_RISE_MS:    dac2_rise_ms    <= (value[15:0] == 16'd0) ? 16'd1 : value[15:0];
                ADDR_PID_EN:     pid_enable      <= value[0];
                ADDR_PID_TARGET: pid_target_code <= value[15:0];
                ADDR_PID_WINDOW: pid_window_code <= value[15:0];
                ADDR_PID_KP:     pid_kp          <= value[15:0];
                ADDR_PID_KI:     pid_ki          <= value[15:0];
                ADDR_PID_KD:     pid_kd          <= value[15:0];
                ADDR_PID_LIMIT:  pid_corr_limit  <= value[15:0];
                default: ;
            endcase
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= S_WAIT_HEAD;
            data_word       <= 32'd0;
            tx_data         <= 8'd0;
            tx_data_valid   <= 1'b0;
            last_addr       <= 8'd0;
            update_tick     <= 1'b0;

            dac1_start_code <= 16'd0;
            dac1_kick_code  <= 16'd32767;
            dac1_scan_ms    <= 32'd100;
            dac2_base_code  <= 16'd24823;
            dac2_min_code   <= 16'd12412;
            dac2_fall_ms    <= 16'd1;
            dac2_rise_ms    <= 16'd10;

            pid_enable      <= 1'b0;
            pid_target_code <= 16'sd4965;
            pid_window_code <= 16'sd248;
            pid_kp          <= 16'sd256;
            pid_ki          <= 16'sd8;
            pid_kd          <= 16'sd0;
            pid_corr_limit  <= 16'd512;
        end else begin
            update_tick <= 1'b0;

            if (tx_data_valid && tx_data_ready)
                tx_data_valid <= 1'b0;

            case (state)
                S_WAIT_HEAD: begin
                    if (rx_data_valid && rx_data == FRAME_HEAD)
                        state <= S_ADDR;
                end

                S_ADDR: begin
                    if (rx_data_valid) begin
                        last_addr <= rx_data;
                        state     <= S_D3;
                    end
                end

                S_D3: begin
                    if (rx_data_valid) begin
                        data_word[31:24] <= rx_data;
                        state <= S_D2;
                    end
                end

                S_D2: begin
                    if (rx_data_valid) begin
                        data_word[23:16] <= rx_data;
                        state <= S_D1;
                    end
                end

                S_D1: begin
                    if (rx_data_valid) begin
                        data_word[15:8] <= rx_data;
                        state <= S_D0;
                    end
                end

                S_D0: begin
                    if (rx_data_valid) begin
                        data_word[7:0] <= rx_data;
                        apply_param(last_addr, {data_word[31:8], rx_data});
                        update_tick <= 1'b1;
                        state <= S_ACK;
                    end
                end

                S_ACK: begin
                    if (tx_data_ready && !tx_data_valid) begin
                        tx_data       <= last_addr;
                        tx_data_valid <= 1'b1;
                        state         <= S_WAIT_HEAD;
                    end
                end

                default: state <= S_WAIT_HEAD;
            endcase
        end
    end

endmodule
