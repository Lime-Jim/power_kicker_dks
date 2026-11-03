`timescale 1ns / 1ps

module dks_power_kicker #(
    parameter integer CLK_HZ = 25_000_000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        btn_start,
    input  wire        btn_reset,
    input  wire        auto_sweep_enable,
    input  wire [15:0] auto_sweep_freq_Hz,

    input  wire [15:0] DAC1_START_VAL,
    input  wire [15:0] NKT_TARGET_VAL,
    input  wire [15:0] NKT_FINAL_VAL,
    input  wire [31:0] NKT_RAMP_DIV,
    // Relative to the rising edge of kick (start of the falling segment).
    // Negative: stop earlier. Positive: continue scanning after kick starts.
    // Nanoseconds, signed two's-complement; rounded away from zero to clk ticks.
    input  wire signed [31:0] SCAN_STOP_OFFSET_NS,
    input  wire [15:0] AOM_INIT_VAL,
    input  wire [15:0] AOM_KICK_VAL,
    input  wire [15:0] AOM_FULL_VAL,
    input  wire [15:0] AOM_DROP_STEP,
    input  wire [15:0] AOM_RISE_STEP,
    // Independent PID eligibility delay from the kick rising edge, in ns.
    input  wire [31:0] PID_START_DELAY_NS,
    input  wire        pid_loop_active,
    input  wire        pid_restart_scan,

    output reg  [15:0] signal_1_nkt,
    output reg  [15:0] signal_2_aom,
    output reg         kick,
    output reg         kick_done,
    output reg         kick_fall_done,
    // Forward scan has stopped and the automatic return is not moving DAC1.
    output reg         scan_stopped,
    output reg         pid_delay_done,
    output wire        sequence_start_pulse,
    output wire [2:0]  state_debug
);

    localparam S_IDLE      = 3'd0;
    localparam S_SCAN      = 3'd1;
    localparam S_KICK_FALL = 3'd2;
    localparam S_KICK_RISE = 3'd3;
    localparam S_DONE      = 3'd4;
    localparam S_RETURN    = 3'd5;
    localparam S_WAIT_STOP = 3'd6;

    localparam integer CLK_PER_US = CLK_HZ / 1000000;
    localparam integer CLK_PERIOD_NS = 1000000000 / CLK_HZ;
    localparam [31:0] START_LOCK_CYCLES = CLK_HZ / 50;
    localparam [15:0] DEFAULT_AUTO_SWEEP_FREQ_HZ = 16'd100;
    localparam integer AUTO_RETURN_PERIOD_DIV = 10;

    reg [2:0]  state;
    reg [31:0] scan_cnt;
    reg [31:0] kick_cnt;
    reg [31:0] kick_ramp_err;
    reg        btn_start_d;
    reg [31:0] start_lock_cnt;
    reg        auto_enable_d;
    reg [31:0] auto_cycle_cnt;
    reg        pending_auto_return;

    reg [15:0] cfg_dac1_start;
    reg [15:0] cfg_dac1_kick;
    reg [15:0] cfg_dac1_final;
    reg [31:0] cfg_scan_us;
    reg [15:0] cfg_aom_base;
    reg [15:0] cfg_aom_min;
    reg [15:0] cfg_aom_final;
    reg [15:0] cfg_fall_ns;
    reg [15:0] cfg_rise_ns;
    reg [31:0] return_start_delta;

    // Independent timebase: early freezing DAC1 must NOT prevent a later kick.
    // Tick 0 is the accepted start edge; the original kick edge is preserved.
    reg [63:0] sequence_ticks;
    reg [63:0] cfg_kick_start_tick;
    reg [63:0] cfg_scan_stop_tick;
    reg        cfg_kick_in_range;

    wire start_unlocked = (start_lock_cnt == 32'd0);
    wire btn_start_pulse = btn_start & ~btn_start_d & start_unlocked;
    wire [15:0] active_auto_sweep_freq_Hz =
        (auto_sweep_freq_Hz == 16'd0) ? DEFAULT_AUTO_SWEEP_FREQ_HZ : auto_sweep_freq_Hz;
    wire [31:0] auto_period_cycles = CLK_HZ / active_auto_sweep_freq_Hz;
    wire auto_cycle_ready = (auto_cycle_cnt >= auto_period_cycles);
    wire auto_start_pulse =
        auto_sweep_enable && !pid_loop_active &&
        ((state == S_IDLE) || (state == S_DONE)) &&
        (!pending_auto_return) &&
        ((!auto_enable_d) || auto_cycle_ready);

    function [31:0] abs_delta16;
        input [15:0] a;
        input [15:0] b;
        begin
            abs_delta16 = (a >= b) ? ({16'd0, a} - {16'd0, b}) :
                                     ({16'd0, b} - {16'd0, a});
        end
    endfunction

    function [31:0] us_to_ticks;
        input [31:0] us_value;
        reg [63:0] ticks_wide;
        begin
            ticks_wide = (us_value == 32'd0) ? 64'd1 :
                         ({32'd0, us_value} * CLK_PER_US);
            us_to_ticks = (ticks_wide > 64'hffff_ffff) ? 32'hffff_ffff :
                                                        ticks_wide[31:0];
        end
    endfunction

    function [31:0] ns_to_ticks;
        input [31:0] ns_value;
        reg [31:0] ticks_value;
        begin
            if (ns_value == 32'd0) begin
                ns_to_ticks = 32'd1;
            end else begin
                ticks_value = (ns_value + CLK_PERIOD_NS - 1) / CLK_PERIOD_NS;
                ns_to_ticks = (ticks_value == 32'd0) ? 32'd1 : ticks_value;
            end
        end
    endfunction

    function [31:0] step_div_from_us;
        input [31:0] us_value;
        input [31:0] delta_value;
        reg [31:0] ticks_value;
        begin
            ticks_value = us_to_ticks(us_value);
            if (delta_value == 32'd0)
                step_div_from_us = 32'd1;
            else if (ticks_value <= delta_value)
                step_div_from_us = 32'd1;
            else
                step_div_from_us = ticks_value / delta_value;
        end
    endfunction

    function [31:0] step_div_from_ticks;
        input [31:0] ticks_value;
        input [31:0] delta_value;
        begin
            if (delta_value == 32'd0)
                step_div_from_ticks = 32'd1;
            else if (ticks_value <= delta_value)
                step_div_from_ticks = 32'd1;
            else
                step_div_from_ticks = ticks_value / delta_value;
        end
    endfunction

    function trigger_in_range;
        input [15:0] start_value;
        input [15:0] trigger_value;
        input [15:0] final_value;
        begin
            trigger_in_range = (start_value <= final_value) ?
                ((trigger_value >= start_value) && (trigger_value <= final_value)) :
                ((trigger_value <= start_value) && (trigger_value >= final_value));
        end
    endfunction

    function [63:0] kick_tick_from_scan;
        input [15:0] start_value;
        input [15:0] trigger_value;
        input [15:0] final_value;
        input [31:0] scan_us_value;
        reg [31:0] trigger_delta;
        reg [31:0] step_ticks;
        begin
            trigger_delta = abs_delta16(start_value, trigger_value);
            step_ticks = step_div_from_us(scan_us_value,
                                          abs_delta16(start_value, final_value));
            // The old controller recognizes the trigger one clock after the
            // corresponding DAC code is reached. Keep exactly that kick edge.
            kick_tick_from_scan = {32'd0, trigger_delta} * {32'd0, step_ticks} + 64'd1;
        end
    endfunction

    function [63:0] stop_tick_from_offset;
        input [63:0] kick_tick;
        input signed [31:0] offset_ns;
        reg [32:0] magnitude_ns;
        reg [63:0] magnitude_ticks;
        begin
            // Widen BEFORE negation, including offset_ns = -2147483648.
            magnitude_ns = offset_ns[31] ?
                           ({1'b0, ~offset_ns} + 33'd1) : {1'b0, offset_ns};
            magnitude_ticks = ({31'd0, magnitude_ns} + CLK_PERIOD_NS - 1) /
                              CLK_PERIOD_NS;
            if (offset_ns[31])
                stop_tick_from_offset = (magnitude_ticks >= kick_tick) ? 64'd0 :
                                         kick_tick - magnitude_ticks;
            else
                stop_tick_from_offset = kick_tick + magnitude_ticks;
        end
    endfunction

    // These live values are captured only at IDLE/reset/start, like the other
    // waveform settings. Mid-cycle VIO edits apply to the NEXT sequence.
    wire live_kick_in_range = trigger_in_range(DAC1_START_VAL, NKT_TARGET_VAL,
                                               NKT_FINAL_VAL);
    wire [63:0] live_kick_start_tick = kick_tick_from_scan(
        DAC1_START_VAL, NKT_TARGET_VAL, NKT_FINAL_VAL,
        (NKT_RAMP_DIV == 32'd0) ? 32'd1 : NKT_RAMP_DIV);
    wire [63:0] live_scan_stop_tick = stop_tick_from_offset(
        live_kick_start_tick, SCAN_STOP_OFFSET_NS);

    wire forward_sequence_active = (state == S_SCAN) || (state == S_KICK_FALL) ||
                                   (state == S_KICK_RISE) || (state == S_WAIT_STOP);
    wire [63:0] next_sequence_tick = sequence_ticks + 64'd1;
    wire requested_stop_due = cfg_kick_in_range &&
                              (next_sequence_tick >= cfg_scan_stop_tick);
    // An excessive positive offset never scans past the original end code.
    wire scan_stop_now = scan_stopped || requested_stop_due ||
                         (signal_1_nkt == cfg_dac1_final);

    // Snapshot with the waveform, but count independently through FALL/RISE/DONE.
    // Widen before rounding so 32'hffffffff ns cannot wrap to a short delay.
    wire [63:0] live_pid_delay_ticks =
        ({32'd0, PID_START_DELAY_NS} + CLK_PERIOD_NS - 1) / CLK_PERIOD_NS;
    reg [31:0] cfg_pid_delay_ticks;
    reg [31:0] pid_delay_remaining;
    reg pid_delay_running;
    // Loss recovery starts a complete new sequence even in manual mode and
    // bypasses the human start-button debounce/retrigger lockout.
    wire sequence_start = pid_restart_scan ||
                          (btn_start_pulse && state == S_IDLE) || auto_start_pulse;
    assign sequence_start_pulse = sequence_start;
    wire kick_start_now = (state == S_SCAN) && cfg_kick_in_range &&
                          (next_sequence_tick >= cfg_kick_start_tick);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cfg_pid_delay_ticks <= 32'd0;
            pid_delay_remaining <= 32'd0;
            pid_delay_running <= 1'b0;
            pid_delay_done <= 1'b0;
        end else if (btn_reset || sequence_start || state == S_IDLE) begin
            cfg_pid_delay_ticks <= live_pid_delay_ticks[31:0];
            pid_delay_remaining <= 32'd0;
            pid_delay_running <= 1'b0;
            pid_delay_done <= 1'b0;
        end else if (kick_start_now) begin
            pid_delay_remaining <= cfg_pid_delay_ticks;
            pid_delay_running <= (cfg_pid_delay_ticks != 32'd0);
            pid_delay_done <= (cfg_pid_delay_ticks == 32'd0);
        end else if (pid_delay_running) begin
            if (pid_delay_remaining <= 32'd1) begin
                pid_delay_remaining <= 32'd0;
                pid_delay_running <= 1'b0;
                pid_delay_done <= 1'b1;
            end else begin
                pid_delay_remaining <= pid_delay_remaining - 1'b1;
            end
        end
    end

    wire [31:0] scan_delta = abs_delta16(cfg_dac1_start, cfg_dac1_final);
    wire [31:0] fall_delta = abs_delta16(cfg_aom_base, cfg_aom_min);
    wire [31:0] rise_delta = abs_delta16(cfg_aom_min, cfg_aom_final);

    wire [31:0] scan_step_div = step_div_from_us(cfg_scan_us, scan_delta);
    wire [31:0] return_total_ticks =
        (auto_period_cycles < AUTO_RETURN_PERIOD_DIV) ? 32'd1 :
                                                        (auto_period_cycles / AUTO_RETURN_PERIOD_DIV);
    wire [31:0] return_start_cycles =
        (auto_period_cycles <= return_total_ticks) ? 32'd0 :
                                                     (auto_period_cycles - return_total_ticks);
    wire [31:0] return_step_div = step_div_from_ticks(return_total_ticks, return_start_delta);
    wire [31:0] fall_total_ticks = ns_to_ticks({16'd0, cfg_fall_ns});
    wire [31:0] rise_total_ticks = ns_to_ticks({16'd0, cfg_rise_ns});

    wire scan_step_tick = (scan_cnt + 32'd1 >= scan_step_div);
    wire return_step_tick = (scan_cnt + 32'd1 >= return_step_div);

    wire [31:0] fall_step_int = fall_delta / fall_total_ticks;
    wire [31:0] fall_step_rem = fall_delta % fall_total_ticks;
    wire [32:0] fall_err_sum = {1'b0, kick_ramp_err} + {1'b0, fall_step_rem};
    wire        fall_extra_step = (fall_err_sum >= {1'b0, fall_total_ticks});
    wire [32:0] fall_err_reduced = fall_extra_step ? (fall_err_sum - {1'b0, fall_total_ticks}) :
                                                     fall_err_sum;
    wire [31:0] fall_ramp_step = fall_step_int + (fall_extra_step ? 32'd1 : 32'd0);

    wire [31:0] rise_step_int = rise_delta / rise_total_ticks;
    wire [31:0] rise_step_rem = rise_delta % rise_total_ticks;
    wire [32:0] rise_err_sum = {1'b0, kick_ramp_err} + {1'b0, rise_step_rem};
    wire        rise_extra_step = (rise_err_sum >= {1'b0, rise_total_ticks});
    wire [32:0] rise_err_reduced = rise_extra_step ? (rise_err_sum - {1'b0, rise_total_ticks}) :
                                                     rise_err_sum;
    wire [31:0] rise_ramp_step = rise_step_int + (rise_extra_step ? 32'd1 : 32'd0);

    assign state_debug = state;

    task advance_sweep;
        begin
            if (signal_1_nkt == cfg_dac1_final) begin
                scan_cnt <= 32'd0;
            end else if (scan_step_tick) begin
                scan_cnt <= 32'd0;
                if (cfg_dac1_start <= cfg_dac1_final) begin
                    if (signal_1_nkt + 16'd1 >= cfg_dac1_final)
                        signal_1_nkt <= cfg_dac1_final;
                    else
                        signal_1_nkt <= signal_1_nkt + 16'd1;
                end else begin
                    if (signal_1_nkt <= cfg_dac1_final + 16'd1)
                        signal_1_nkt <= cfg_dac1_final;
                    else
                        signal_1_nkt <= signal_1_nkt - 16'd1;
                end
            end else begin
                scan_cnt <= scan_cnt + 32'd1;
            end
        end
    endtask

    task advance_return;
        begin
            if (signal_1_nkt == cfg_dac1_start) begin
                scan_cnt <= 32'd0;
                pending_auto_return <= 1'b0;
                return_start_delta  <= 32'd0;
                state               <= S_DONE;
            end else if (return_step_tick) begin
                scan_cnt <= 32'd0;
                if (signal_1_nkt <= cfg_dac1_start) begin
                    if (signal_1_nkt + 16'd1 >= cfg_dac1_start)
                        signal_1_nkt <= cfg_dac1_start;
                    else
                        signal_1_nkt <= signal_1_nkt + 16'd1;
                end else begin
                    if (signal_1_nkt <= cfg_dac1_start + 16'd1)
                        signal_1_nkt <= cfg_dac1_start;
                    else
                        signal_1_nkt <= signal_1_nkt - 16'd1;
                end
            end else begin
                scan_cnt <= scan_cnt + 32'd1;
            end
        end
    endtask

    function [15:0] step_toward16;
        input [15:0] current_value;
        input [15:0] target_value;
        input [31:0] step_value;
        reg [31:0] next_value;
        begin
            if (current_value <= target_value) begin
                next_value = {16'd0, current_value} + step_value;
                step_toward16 = (next_value >= {16'd0, target_value}) ? target_value :
                                                                           next_value[15:0];
            end else begin
                if ({16'd0, current_value} <= ({16'd0, target_value} + step_value))
                    step_toward16 = target_value;
                else begin
                    next_value = {16'd0, current_value} - step_value;
                    step_toward16 = next_value[15:0];
                end
            end
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Asynchronous reset values must be constants. VIO settings are
            // sampled on a clock edge in IDLE, at start, or at button reset.
            state          <= S_IDLE;
            signal_1_nkt   <= 16'd0;
            signal_2_aom   <= 16'd0;
            kick           <= 1'b0;
            kick_done      <= 1'b0;
            kick_fall_done <= 1'b0;
            scan_cnt       <= 32'd0;
            kick_cnt       <= 32'd0;
            kick_ramp_err  <= 32'd0;
            start_lock_cnt <= 32'd0;
            btn_start_d    <= 1'b0;
            auto_enable_d  <= 1'b0;
            auto_cycle_cnt <= 32'd0;
            pending_auto_return <= 1'b0;
            cfg_dac1_start <= 16'd0;
            cfg_dac1_kick  <= 16'd0;
            cfg_dac1_final <= 16'd0;
            cfg_scan_us    <= 32'd1;
            cfg_aom_base   <= 16'd0;
            cfg_aom_min    <= 16'd0;
            cfg_aom_final  <= 16'd0;
            cfg_fall_ns    <= 16'd1;
            cfg_rise_ns    <= 16'd1;
            return_start_delta <= 32'd0;
            sequence_ticks <= 64'd0;
            cfg_kick_start_tick <= 64'd1;
            cfg_scan_stop_tick <= 64'd1;
            cfg_kick_in_range <= 1'b0;
            scan_stopped <= 1'b0;
        end else begin
            btn_start_d <= btn_start;
            auto_enable_d <= auto_sweep_enable;
            if (start_lock_cnt != 32'd0)
                start_lock_cnt <= start_lock_cnt - 1'b1;
            if (!auto_sweep_enable || btn_reset || sequence_start || pid_loop_active) begin
                auto_cycle_cnt <= 32'd0;
            end else if (auto_cycle_cnt < auto_period_cycles) begin
                auto_cycle_cnt <= auto_cycle_cnt + 32'd1;
            end

            if (btn_reset) begin
                state          <= S_IDLE;
                scan_stopped   <= 1'b0;
                signal_1_nkt   <= DAC1_START_VAL;
                signal_2_aom   <= AOM_INIT_VAL;
                kick           <= 1'b0;
                kick_done      <= 1'b0;
                kick_fall_done <= 1'b0;
                scan_cnt       <= 32'd0;
                kick_cnt       <= 32'd0;
                kick_ramp_err  <= 32'd0;
                start_lock_cnt <= 32'd0;
                auto_cycle_cnt <= 32'd0;
                pending_auto_return <= 1'b0;
                cfg_dac1_start <= DAC1_START_VAL;
                cfg_dac1_kick  <= NKT_TARGET_VAL;
                cfg_dac1_final <= NKT_FINAL_VAL;
                cfg_scan_us    <= (NKT_RAMP_DIV == 32'd0) ? 32'd1 : NKT_RAMP_DIV;
                cfg_aom_base   <= AOM_INIT_VAL;
                cfg_aom_min    <= AOM_KICK_VAL;
                cfg_aom_final  <= AOM_FULL_VAL;
                cfg_fall_ns    <= (AOM_DROP_STEP == 16'd0) ? 16'd1 : AOM_DROP_STEP;
                cfg_rise_ns    <= (AOM_RISE_STEP == 16'd0) ? 16'd1 : AOM_RISE_STEP;
                cfg_kick_start_tick <= live_kick_start_tick;
                cfg_scan_stop_tick  <= live_scan_stop_tick;
                cfg_kick_in_range   <= live_kick_in_range;
                sequence_ticks     <= 64'd0;
                return_start_delta <= 32'd0;
            end else if (sequence_start) begin
                state          <= S_SCAN;
                scan_stopped   <= live_kick_in_range && (live_scan_stop_tick == 64'd0);
                signal_1_nkt   <= DAC1_START_VAL;
                signal_2_aom   <= AOM_INIT_VAL;
                kick           <= 1'b0;
                kick_done      <= 1'b0;
                kick_fall_done <= 1'b0;
                scan_cnt       <= 32'd0;
                kick_cnt       <= 32'd0;
                kick_ramp_err  <= 32'd0;
                start_lock_cnt <= START_LOCK_CYCLES;
                pending_auto_return <= 1'b0;
                cfg_dac1_start <= DAC1_START_VAL;
                cfg_dac1_kick  <= NKT_TARGET_VAL;
                cfg_dac1_final <= NKT_FINAL_VAL;
                cfg_scan_us    <= (NKT_RAMP_DIV == 32'd0) ? 32'd1 : NKT_RAMP_DIV;
                cfg_aom_base   <= AOM_INIT_VAL;
                cfg_aom_min    <= AOM_KICK_VAL;
                cfg_aom_final  <= AOM_FULL_VAL;
                cfg_fall_ns    <= (AOM_DROP_STEP == 16'd0) ? 16'd1 : AOM_DROP_STEP;
                cfg_rise_ns    <= (AOM_RISE_STEP == 16'd0) ? 16'd1 : AOM_RISE_STEP;
                cfg_kick_start_tick <= live_kick_start_tick;
                cfg_scan_stop_tick  <= live_scan_stop_tick;
                cfg_kick_in_range   <= live_kick_in_range;
                sequence_ticks     <= 64'd0;
                return_start_delta <= 32'd0;
            end else begin
                if (forward_sequence_active) begin
                    sequence_ticks <= next_sequence_tick;
                    if (scan_stop_now) begin
                        scan_stopped <= 1'b1;
                        scan_cnt <= 32'd0;
                    end else begin
                        advance_sweep();
                    end
                end

                case (state)
                    S_IDLE: begin
                        scan_stopped <= 1'b0;
                        // Follow VIO only while idle. The start branch captures
                        // a complete snapshot held throughout scan/kick/return.
                        cfg_dac1_start <= DAC1_START_VAL;
                        cfg_dac1_kick  <= NKT_TARGET_VAL;
                        cfg_dac1_final <= NKT_FINAL_VAL;
                        cfg_scan_us    <= (NKT_RAMP_DIV == 32'd0) ? 32'd1 : NKT_RAMP_DIV;
                        cfg_aom_base   <= AOM_INIT_VAL;
                        cfg_aom_min    <= AOM_KICK_VAL;
                        cfg_aom_final  <= AOM_FULL_VAL;
                        cfg_fall_ns    <= (AOM_DROP_STEP == 16'd0) ? 16'd1 : AOM_DROP_STEP;
                        cfg_rise_ns    <= (AOM_RISE_STEP == 16'd0) ? 16'd1 : AOM_RISE_STEP;
                        cfg_kick_start_tick <= live_kick_start_tick;
                        cfg_scan_stop_tick  <= live_scan_stop_tick;
                        cfg_kick_in_range   <= live_kick_in_range;
                        sequence_ticks     <= 64'd0;
                        signal_1_nkt <= DAC1_START_VAL;
                        signal_2_aom <= AOM_INIT_VAL;
                        kick         <= 1'b0;
                        kick_done    <= 1'b0;
                        kick_fall_done <= 1'b0;
                        scan_cnt     <= 32'd0;
                        kick_cnt     <= 32'd0;
                        kick_ramp_err <= 32'd0;
                        pending_auto_return <= 1'b0;
                        return_start_delta <= 32'd0;
                    end

                    S_SCAN: begin
                        kick      <= 1'b0;
                        kick_done <= 1'b0;
                        signal_2_aom <= cfg_aom_base;

                        if (cfg_kick_in_range &&
                            (next_sequence_tick >= cfg_kick_start_tick)) begin
                            signal_2_aom <= cfg_aom_base;
                            kick         <= 1'b1;
                            kick_done    <= 1'b0;
                            kick_fall_done <= 1'b0;
                            kick_cnt     <= 32'd0;
                            kick_ramp_err <= 32'd0;
                            state        <= S_KICK_FALL;
                        end else if (!cfg_kick_in_range &&
                                     (signal_1_nkt == cfg_dac1_final)) begin
                            scan_cnt <= 32'd0;
                            return_start_delta <= abs_delta16(signal_1_nkt, cfg_dac1_start);
                            pending_auto_return <= auto_sweep_enable;
                            state    <= S_DONE;
                        end
                    end

                    S_KICK_FALL: begin
                        kick      <= 1'b1;
                        kick_done <= 1'b0;

                        if (kick_cnt + 32'd1 >= fall_total_ticks) begin
                            signal_2_aom  <= cfg_aom_min;
                            kick_cnt      <= 32'd0;
                            kick_ramp_err <= 32'd0;
                            kick_fall_done <= 1'b1;
                            state         <= S_KICK_RISE;
                        end else begin
                            signal_2_aom  <= step_toward16(signal_2_aom, cfg_aom_min, fall_ramp_step);
                            kick_cnt      <= kick_cnt + 32'd1;
                            kick_ramp_err <= fall_err_reduced[31:0];
                        end
                    end

                    S_KICK_RISE: begin
                        kick      <= 1'b1;
                        kick_done <= 1'b0;

                        if (kick_cnt + 32'd1 >= rise_total_ticks) begin
                            signal_2_aom <= cfg_aom_final;
                            kick         <= 1'b0;
                            kick_done    <= 1'b1;
                            kick_cnt     <= 32'd0;
                            kick_ramp_err <= 32'd0;
                            if (scan_stop_now) begin
                                scan_cnt <= 32'd0;
                                return_start_delta <= abs_delta16(signal_1_nkt, cfg_dac1_start);
                                pending_auto_return <= auto_sweep_enable;
                                state <= S_DONE;
                            end else begin
                                // Kick voltage is already at the unchanged final
                                // level; DAC1 may still be scanning independently.
                                state <= S_WAIT_STOP;
                            end
                        end else begin
                            signal_2_aom  <= step_toward16(signal_2_aom, cfg_aom_final, rise_ramp_step);
                            kick_cnt      <= kick_cnt + 32'd1;
                            kick_ramp_err <= rise_err_reduced[31:0];
                        end
                    end

                    S_WAIT_STOP: begin
                        signal_2_aom <= cfg_aom_final;
                        kick <= 1'b0;
                        kick_done <= 1'b1;
                        if (scan_stop_now) begin
                            scan_cnt <= 32'd0;
                            return_start_delta <= abs_delta16(signal_1_nkt, cfg_dac1_start);
                            pending_auto_return <= auto_sweep_enable;
                            state <= S_DONE;
                        end
                    end

                    S_RETURN: begin
                        signal_2_aom  <= cfg_aom_final;
                        kick          <= 1'b0;
                        kick_done     <= 1'b1;
                        kick_cnt      <= 32'd0;
                        kick_ramp_err <= 32'd0;
                        advance_return();
                    end

                    S_DONE: begin
                        signal_2_aom <= cfg_aom_final;
                        kick         <= 1'b0;
                        kick_done    <= 1'b1;
                        scan_cnt     <= 32'd0;
                        kick_cnt     <= 32'd0;
                        kick_ramp_err <= 32'd0;
                        if (pid_loop_active) begin
                            // A running feedback loop holds the captured scan
                            // base. Only loss recovery starts the next attempt.
                            pending_auto_return <= 1'b0;
                            return_start_delta <= 32'd0;
                        end else if (pending_auto_return && !auto_sweep_enable) begin
                            pending_auto_return <= 1'b0;
                            return_start_delta  <= 32'd0;
                        end else if (pending_auto_return && (auto_cycle_cnt >= return_start_cycles)) begin
                            scan_cnt <= 32'd0;
                            scan_stopped <= 1'b0;
                            state    <= S_RETURN;
                        end else if (!pending_auto_return) begin
                            return_start_delta <= 32'd0;
                        end
                    end

                    default: begin
                        state        <= S_IDLE;
                        sequence_ticks <= 64'd0;
                        scan_stopped <= 1'b0;
                        signal_1_nkt <= DAC1_START_VAL;
                        signal_2_aom <= AOM_INIT_VAL;
                        kick         <= 1'b0;
                        kick_done    <= 1'b0;
                        kick_fall_done <= 1'b0;
                        scan_cnt     <= 32'd0;
                        kick_cnt     <= 32'd0;
                        kick_ramp_err <= 32'd0;
                        pending_auto_return <= 1'b0;
                        return_start_delta <= 32'd0;
                    end
                endcase
            end
        end
    end

endmodule
