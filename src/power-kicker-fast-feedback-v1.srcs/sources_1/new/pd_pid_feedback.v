`timescale 1ns / 1ps

module pd_pid_feedback (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               pd_sample_tick,
    input  wire signed [15:0] pd_sample,
    input  wire               step_detect_arm,
    input  wire               pid_enable_after_step,
    input  wire               pid_force_enable,
    input  wire               pid_clear,
    input  wire               pid_hold,
    input  wire               nkt_pid_enable,
    input  wire signed [15:0] nkt_pd_target,
    input  wire signed [15:0] pd_window_code,
    input  wire [7:0]         step_confirm_samples,
    input  wire signed [15:0] nkt_kp,
    input  wire signed [15:0] nkt_ki,
    input  wire signed [15:0] nkt_kd,
    input  wire [15:0]        nkt_corr_limit,

    input  wire [15:0]        base_nkt,
    input  wire [15:0]        base_aom,

    output wire [15:0]        final_nkt,
    output wire [15:0]        final_aom,

    output reg                step_found,
    output wire               pid_active,
    output wire               feedback_locked,
    output wire signed [15:0] nkt_correction,
    output wire signed [15:0] aom_correction
);

    localparam integer STEP_COUNT_BITS = 8;

    reg [STEP_COUNT_BITS-1:0] step_count = {STEP_COUNT_BITS{1'b0}};
    wire [STEP_COUNT_BITS-1:0] step_confirm_count =
        (step_confirm_samples == 8'd0) ? 8'd1 : step_confirm_samples;

    wire signed [16:0] pd_target_ext = {nkt_pd_target[15], nkt_pd_target};
    wire signed [16:0] pd_sample_ext = {pd_sample[15], pd_sample};
    wire signed [16:0] pd_window_ext = {pd_window_code[15], pd_window_code};
    wire signed [16:0] pd_window_abs =
        pd_window_ext[16] ? -pd_window_ext : pd_window_ext;
    wire signed [16:0] pd_err_to_target = pd_target_ext - pd_sample_ext;

    wire pd_in_window =
        (pd_err_to_target <= pd_window_abs) &&
        (pd_err_to_target >= -pd_window_abs);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            step_count <= {STEP_COUNT_BITS{1'b0}};
            step_found <= 1'b0;
        end else if (pid_clear || !step_detect_arm) begin
            step_count <= {STEP_COUNT_BITS{1'b0}};
            step_found <= 1'b0;
        end else if (pd_sample_tick) begin
            if (pd_in_window) begin
                if (step_count < step_confirm_count)
                    step_count <= step_count + 1'b1;
                if (step_count + 1'b1 >= step_confirm_count)
                    step_found <= 1'b1;
            end else begin
                step_count <= {STEP_COUNT_BITS{1'b0}};
                step_found <= 1'b0;
            end
        end
    end

    assign pid_active = pid_force_enable | (pid_enable_after_step & step_found);

    wire nkt_saturated;
    wire signed [16:0] nkt_error;
    wire nkt_loop_active = pid_active & nkt_pid_enable;
    reg  nkt_correction_valid = 1'b0;
    reg  nkt_pid_enable_d = 1'b0;
    reg  frozen_correction_valid = 1'b0;
    reg  signed [15:0] frozen_correction = 16'sd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            nkt_correction_valid <= 1'b0;
            nkt_pid_enable_d <= 1'b0;
            frozen_correction_valid <= 1'b0;
            frozen_correction <= 16'sd0;
        end else begin
            nkt_pid_enable_d <= nkt_pid_enable;

            if (pid_clear) begin
                nkt_correction_valid <= 1'b0;
                frozen_correction_valid <= 1'b0;
                frozen_correction <= 16'sd0;
            end else if (nkt_pid_enable_d && !nkt_pid_enable && nkt_correction_valid) begin
                nkt_correction_valid <= 1'b0;
                frozen_correction_valid <= 1'b1;
                frozen_correction <= nkt_correction;
            end else if (nkt_loop_active) begin
                nkt_correction_valid <= 1'b1;
                frozen_correction_valid <= 1'b0;
            end else if (nkt_pid_enable) begin
                nkt_correction_valid <= 1'b0;
                frozen_correction_valid <= 1'b0;
            end
        end
    end

    wire use_live_correction = nkt_loop_active & nkt_correction_valid;
    wire use_frozen_correction = !nkt_pid_enable & frozen_correction_valid;
    assign feedback_locked = nkt_correction_valid | frozen_correction_valid;
    wire signed [15:0] applied_correction =
        use_frozen_correction ? frozen_correction : nkt_correction;

    wire signed [15:0] nkt_limit_pos =
        (nkt_corr_limit[14:0] == 15'd0) ? 16'sd0 : {1'b0, nkt_corr_limit[14:0]};
    wire signed [15:0] nkt_limit_neg = -nkt_limit_pos;

    pid_core_signed u_nkt_pid (
        .clk         (clk),
        .rst_n       (rst_n),
        .sample_tick (pd_sample_tick),
        .enable      (nkt_loop_active),
        .clear       (pid_clear),
        .hold        (pid_hold),
        .setpoint    (nkt_pd_target),
        .measured    (pd_sample),
        .kp          (nkt_kp),
        .ki          (nkt_ki),
        .kd          (nkt_kd),
        .out_min     (nkt_limit_neg),
        .out_max     (nkt_limit_pos),
        .correction  (nkt_correction),
        .error       (nkt_error),
        .saturated   (nkt_saturated)
    );

    function [15:0] sat_add_s16;
        input [15:0] base_value;
        input signed [15:0] corr_value;
        input use_corr;
        reg signed [31:0] sum_value;
        begin
            sum_value =
                {{16{base_value[15]}}, base_value} +
                (use_corr ? {{16{corr_value[15]}}, corr_value} : 32'sd0);

            if (sum_value > 32'sd32767)
                sat_add_s16 = 16'h7fff;
            else if (sum_value < -32'sd32767)
                sat_add_s16 = 16'h8001;
            else
                sat_add_s16 = sum_value[15:0];
        end
    endfunction

    assign final_nkt = sat_add_s16(base_nkt, applied_correction, use_live_correction | use_frozen_correction);
    assign final_aom = base_aom;
    assign aom_correction = 16'sd0;

endmodule
