`timescale 1ns / 1ps

// Read-only supervisory FSM. It observes the waveform/PID controllers and does
// not drive either controller. All inputs are synchronous to the logic clock.
module capture_phase_status (
    input wire clk,
    input wire rst_n,
    input wire button_reset,
    input wire pid_clear,
    input wire feedback_enable,
    input wire [2:0] controller_state,
    input wire sequence_start,
    input wire restart_scan,
    input wire kick,
    input wire pid_active,
    input wire window_found,
    input wire window_confirmed,
    output reg [1:0] phase = 2'd0,
    output wire capture_valid,
    output reg capture_event = 1'b0,
    output reg captured_seen = 1'b0,
    output reg phase_change = 1'b0
);
    localparam [1:0] PH_IDLE=2'd0, PH_SCAN=2'd1,
                     PH_CAPTURE=2'd2, PH_PID=2'd3;
    // Same codes as dks_power_kicker.state_debug.
    localparam [2:0] CTRL_IDLE=3'd0, CTRL_SCAN=3'd1, CTRL_DONE=3'd4,
                     CTRL_RETURN=3'd5;
    reg kick_seen = 1'b0;
    reg [1:0] next_phase;

    assign capture_valid = rst_n && !button_reset && !pid_clear &&
        !sequence_start && !restart_scan && feedback_enable &&
        pid_active && window_found && window_confirmed;
    wire loss_pending = feedback_enable && !pid_clear &&
                        window_confirmed && !window_found;
    wire acquisition_pending = kick || (kick_seen && feedback_enable);

    always @* begin
        next_phase = phase;
        if (button_reset)
            next_phase = PH_IDLE;
        else if (sequence_start || restart_scan || loss_pending ||
                 controller_state == CTRL_SCAN || controller_state == CTRL_RETURN)
            next_phase = PH_SCAN;
        else if (controller_state == CTRL_IDLE)
            next_phase = PH_IDLE;
        else begin
            case (phase)
                PH_IDLE, PH_SCAN: begin
                    if (capture_valid) next_phase = PH_PID;
                    else if (acquisition_pending) next_phase = PH_CAPTURE;
                    else next_phase = PH_IDLE;
                end
                PH_CAPTURE: begin
                    if (capture_valid) next_phase = PH_PID;
                    else if (!acquisition_pending && controller_state == CTRL_DONE)
                        next_phase = PH_IDLE;
                end
                PH_PID: begin
                    if (!capture_valid)
                        next_phase = acquisition_pending ? PH_CAPTURE : PH_IDLE;
                end
                default: next_phase = PH_IDLE;
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= PH_IDLE;
            kick_seen <= 1'b0;
            capture_event <= 1'b0;
            captured_seen <= 1'b0;
            phase_change <= 1'b0;
        end else if (button_reset) begin
            phase <= PH_IDLE;
            kick_seen <= 1'b0;
            capture_event <= 1'b0;
            captured_seen <= 1'b0;
            phase_change <= 1'b0;
        end else begin
            phase <= next_phase;
            phase_change <= (next_phase != phase);
            capture_event <= (next_phase == PH_PID && phase != PH_PID);
            if (sequence_start || controller_state == CTRL_IDLE ||
                controller_state == CTRL_RETURN)
                kick_seen <= 1'b0;
            else if (kick)
                kick_seen <= 1'b1;
            // Keep history across loss/rescan, clear explicitly with PID clear.
            if (pid_clear) captured_seen <= 1'b0;
            else if (next_phase == PH_PID) captured_seen <= 1'b1;
        end
    end
endmodule
