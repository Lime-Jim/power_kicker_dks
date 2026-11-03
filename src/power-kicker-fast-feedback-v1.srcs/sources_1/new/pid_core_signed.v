`timescale 1ns / 1ps

module pid_core_signed #(
    parameter integer GAIN_SHIFT = 8,
    parameter signed [39:0] I_ACCUM_MIN = -40'sd8388352,
    parameter signed [39:0] I_ACCUM_MAX =  40'sd8388352
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               sample_tick,
    input  wire               enable,
    input  wire               clear,
    input  wire               hold,

    input  wire signed [15:0] setpoint,
    input  wire signed [15:0] measured,

    input  wire signed [15:0] kp,
    input  wire signed [15:0] ki,
    input  wire signed [15:0] kd,
    input  wire signed [15:0] out_min,
    input  wire signed [15:0] out_max,

    output reg  signed [15:0] correction,
    output reg  signed [16:0] error,
    output reg                saturated
);

    reg signed [16:0] error_z1 = 17'sd0;
    reg signed [39:0] i_accum  = 40'sd0;

    wire signed [16:0] setpoint_ext = {setpoint[15], setpoint};
    wire signed [16:0] measured_ext = {measured[15], measured};
    wire signed [16:0] error_next   = setpoint_ext - measured_ext;

    wire signed [17:0] deriv_next =
        {error_next[16], error_next} - {error_z1[16], error_z1};

    wire signed [32:0] p_prod = error_next * kp;
    wire signed [32:0] i_prod = error_next * ki;
    wire signed [33:0] d_prod = deriv_next * kd;

    wire signed [39:0] p_q     = {{7{p_prod[32]}}, p_prod};
    wire signed [39:0] i_add_q = {{7{i_prod[32]}}, i_prod};
    wire signed [39:0] d_q     = {{6{d_prod[33]}}, d_prod};

    wire signed [39:0] i_accum_added = i_accum + i_add_q;
    wire signed [39:0] i_accum_limited =
        (i_accum_added > I_ACCUM_MAX) ? I_ACCUM_MAX :
        (i_accum_added < I_ACCUM_MIN) ? I_ACCUM_MIN :
                                        i_accum_added;

    wire signed [39:0] sum_q = p_q + i_accum_limited + d_q;
    wire signed [39:0] sum_code = sum_q >>> GAIN_SHIFT;
    wire signed [39:0] out_min_ext = {{24{out_min[15]}}, out_min};
    wire signed [39:0] out_max_ext = {{24{out_max[15]}}, out_max};

    wire sat_hi = (sum_code > out_max_ext);
    wire sat_lo = (sum_code < out_min_ext);
    wire signed [15:0] correction_next =
        sat_hi ? out_max :
        sat_lo ? out_min :
                 sum_code[15:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            correction <= 16'sd0;
            error      <= 17'sd0;
            error_z1   <= 17'sd0;
            i_accum    <= 40'sd0;
            saturated  <= 1'b0;
        end else if (clear) begin
            correction <= 16'sd0;
            error      <= 17'sd0;
            error_z1   <= 17'sd0;
            i_accum    <= 40'sd0;
            saturated  <= 1'b0;
        end else if (sample_tick && enable && !hold) begin
            correction <= correction_next;
            error      <= error_next;
            error_z1   <= error_next;
            i_accum    <= i_accum_limited;
            saturated  <= sat_hi | sat_lo;
        end
    end

endmodule
