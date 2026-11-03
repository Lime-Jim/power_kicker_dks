`timescale 1ns / 1ps

module tb_feedback_regression;
    reg clk = 0;
    always #20 clk = ~clk;
    reg rst_n = 0;
    integer checks = 0;

    reg c_tick = 0, c_enable = 0, c_clear = 0, c_hold = 0;
    reg signed [15:0] c_target = 0, c_measured = 0;
    reg signed [15:0] c_kp = 0, c_ki = 0, c_kd = 0;
    reg signed [15:0] c_min = -32767, c_max = 32767;
    wire signed [15:0] c_correction;
    wire signed [16:0] c_error;
    wire c_saturated;
    pid_core_signed core (
        .clk(clk), .rst_n(rst_n), .sample_tick(c_tick), .enable(c_enable),
        .clear(c_clear), .hold(c_hold), .setpoint(c_target), .measured(c_measured),
        .kp(c_kp), .ki(c_ki), .kd(c_kd), .out_min(c_min), .out_max(c_max),
        .correction(c_correction), .error(c_error), .saturated(c_saturated)
    );

    reg f_tick = 0, f_arm = 0, f_after_step = 1, f_force = 0;
    reg f_clear = 0, f_hold = 0, f_enable = 0;
    reg signed [15:0] f_sample = 0, f_target = 100, f_window = 10;
    reg [7:0] f_confirm = 3;
    reg signed [15:0] f_kp = 256, f_ki = 0, f_kd = 0;
    reg [15:0] f_limit = 1000, f_base_nkt = 1000, f_base_aom = 2345;
    wire [15:0] f_nkt, f_aom;
    wire f_found, f_active, f_locked;
    wire signed [15:0] f_correction, f_aom_correction;
    pd_pid_feedback feedback (
        .clk(clk), .rst_n(rst_n), .pd_sample_tick(f_tick), .pd_sample(f_sample),
        .step_detect_arm(f_arm), .pid_enable_after_step(f_after_step),
        .pid_force_enable(f_force), .pid_clear(f_clear), .pid_hold(f_hold),
        .nkt_pid_enable(f_enable), .nkt_pd_target(f_target), .pd_window_code(f_window),
        .step_confirm_samples(f_confirm), .nkt_kp(f_kp), .nkt_ki(f_ki), .nkt_kd(f_kd),
        .nkt_corr_limit(f_limit), .base_nkt(f_base_nkt), .base_aom(f_base_aom),
        .final_nkt(f_nkt), .final_aom(f_aom), .step_found(f_found),
        .pid_active(f_active), .feedback_locked(f_locked),
        .nkt_correction(f_correction), .aom_correction(f_aom_correction)
    );

    task automatic check(input bit condition, input string label);
        begin
            checks = checks + 1;
            if (!condition) $fatal(1, "FAIL feedback/core: %s at %0t", label, $time);
        end
    endtask

    // Inputs are driven at the falling edge; compare registered results after NBA.
    task automatic core_step(input integer corr, input integer err,
                             input bit saturated, input string label);
        begin
            @(posedge clk); #1;
            if ($signed(c_correction) !== corr || $signed(c_error) !== err ||
                c_saturated !== saturated)
                $fatal(1, "FAIL core %s: corr=%0d/%0d error=%0d/%0d sat=%b/%b",
                       label, c_correction, corr, c_error, err, c_saturated, saturated);
            checks = checks + 1;
            @(negedge clk);
        end
    endtask

    task automatic clear_core;
        begin
            c_clear = 1; c_tick = 0;
            core_step(0, 0, 0, "clear independent of enable/tick");
            c_clear = 0; c_tick = 1; c_enable = 1; c_hold = 0;
        end
    endtask

    task automatic feedback_step(input integer sample, input bit tick,
                                 input bit found, input bit active,
                                 input integer corr, input integer nkt,
                                 input string label);
        begin
            f_sample = sample; f_tick = tick;
            @(posedge clk); #1;
            if (f_found !== found || f_active !== active ||
                $signed(f_correction) !== corr || $signed(f_nkt) !== nkt)
                $fatal(1, "FAIL feedback %s: found=%b/%b active=%b/%b corr=%0d/%0d nkt=%0d/%0d",
                       label, f_found, found, f_active, active,
                       f_correction, corr, $signed(f_nkt), nkt);
            check(f_aom === f_base_aom && f_aom_correction === 16'sd0,
                  {label, ": AOM must remain unchanged"});
            checks = checks + 1;
            @(negedge clk);
        end
    endtask

    initial begin
        #1;
        repeat (3) @(negedge clk);
        rst_n = 1;
        c_enable = 1; c_tick = 1; c_kp = 256; c_target = 100;
        core_step(100, 100, 0, "Q8 unity proportional gain");
        c_kp = 128;
        core_step(50, 100, 0, "Q8 half proportional gain");
        c_target = -3;
        core_step(-2, -3, 0, "negative fractional value rounds by arithmetic shift");
        c_target = 32767; c_measured = -32768; c_kp = 256;
        core_step(32767, 65535, 1, "17-bit positive error, positive output saturation");
        c_target = -32768; c_measured = 32767;
        core_step(-32767, -65535, 1, "17-bit negative error, negative output saturation");
        c_target = 200; c_measured = 0; c_min = -100; c_max = 80;
        core_step(80, 200, 1, "asymmetric upper clamp");
        c_target = -200;
        core_step(-100, -200, 1, "asymmetric lower clamp");
        c_target = 80;
        core_step(80, 80, 0, "exact clamp boundary does not assert saturation");

        clear_core(); c_min = -32767; c_max = 32767;
        c_kp = 0; c_ki = 0; c_kd = 256; c_target = 10;
        core_step(10, 10, 0, "derivative starts relative to zero");
        c_target = 7;
        core_step(-3, 7, 0, "negative derivative");
        c_hold = 1; c_target = 99;
        core_step(-3, 7, 0, "hold preserves correction and derivative history");
        c_hold = 0; c_target = 5;
        core_step(-2, 5, 0, "derivative resumes from last accepted sample");

        clear_core(); c_kd = 0; c_ki = 256; c_target = 2;
        core_step(2, 2, 0, "integral first sample");
        c_target = 3;
        core_step(5, 3, 0, "integral accumulates once per tick");
        c_enable = 0; c_target = 9;
        core_step(5, 3, 0, "disabled integral holds");
        c_enable = 1; c_tick = 0;
        core_step(5, 3, 0, "no sample tick holds");
        c_tick = 1; c_hold = 1;
        core_step(5, 3, 0, "hold blocks integral");
        c_enable = 0;
        clear_core(); c_ki = 32767; c_target = 32767;
        core_step(32767, 32767, 0, "integrator positive accumulator limit");
        c_target = -32767;
        core_step(-32767, -32767, 0, "integrator negative accumulator limit");

        clear_core(); c_kp = 128; c_ki = 64; c_kd = 256; c_target = 20;
        core_step(35, 20, 0, "combined P=10 I=5 D=20");
        c_target = 12;
        core_step(6, 12, 0, "combined P=6 I=8 D=-8");
        // Audit the existing windup behavior (not an anti-windup fix).
        clear_core(); c_kp = 0; c_ki = 256; c_kd = 0;
        c_min = -100; c_max = 100; c_target = 100;
        core_step(100, 100, 0, "audit: integral reaches output limit");
        core_step(100, 100, 1, "audit: integral continues behind saturated output");
        c_target = 0;
        core_step(100, 0, 1, "audit: zero error retains wound-up saturated output");
        c_enable = 0; c_tick = 0;

        f_enable = 1; f_arm = 1;
        feedback_step(90, 1, 0, 0, 0, 1000, "inclusive low window edge, count 1");
        feedback_step(110, 1, 0, 0, 0, 1000, "inclusive high window edge, count 2");
        feedback_step(89, 1, 0, 0, 0, 1000, "out-of-window sample resets consecutive count");
        feedback_step(95, 1, 0, 0, 0, 1000, "restarted count 1");
        feedback_step(500, 0, 0, 0, 0, 1000, "non-tick samples do not affect detector");
        feedback_step(95, 1, 0, 0, 0, 1000, "restarted count 2");
        feedback_step(95, 1, 1, 1, 0, 1000, "count 3 arms PID, correction waits next tick");
        feedback_step(95, 1, 1, 1, 5, 1005, "first PID correction on following sample");
        check(f_locked === 1'b1, "active feedback is marked valid");
        f_hold = 1;
        feedback_step(100, 1, 1, 1, 5, 1005, "feedback hold preserves correction");
        f_hold = 0; f_enable = 0;
        feedback_step(100, 1, 1, 1, 5, 1005, "disable freezes last correction");
        check(f_locked === 1'b1, "frozen feedback remains valid");
        f_base_nkt = 1200; f_base_aom = 5432;
        feedback_step(500, 1, 0, 0, 5, 1205, "frozen correction follows base after detector loses step");
        f_clear = 1;
        feedback_step(100, 0, 0, 0, 0, 1200, "clear removes frozen correction without sample tick");
        check(f_locked === 1'b0, "clear removes feedback-valid flag");
        f_clear = 0; f_enable = 1; f_confirm = 0; f_window = -10;
        feedback_step(90, 1, 1, 1, 0, 1200, "confirm zero means one, negative window uses absolute value");
        feedback_step(90, 1, 1, 1, 10, 1210, "PID follows single-sample detection");
        f_arm = 0;
        feedback_step(100, 0, 0, 0, 10, 1200, "disarm removes live correction");
        feedback_step(100, 0, 0, 0, 10, 1200, "disarm clears live-valid flag on next edge");
        check(f_locked === 1'b0, "no active or frozen correction after disarm");

        // Audit existing exit/re-entry semantics. A stale correction can be
        // applied between requalification and the first new PID sample tick.
        f_arm = 1;
        feedback_step(100, 1, 1, 1, 10, 1200, "audit: requalify with retained PID state");
        feedback_step(100, 0, 1, 1, 10, 1210, "audit: stale correction appears before a new PID tick");
        feedback_step(500, 1, 0, 0, -400, 1200, "audit: a single out-of-window sample removes correction");
        f_arm = 0;
        feedback_step(100, 0, 0, 0, -400, 1200, "audit: disarm leaves internal correction intact");

        f_force = 1; f_limit = 100; f_base_nkt = 32760;
        feedback_step(0, 1, 0, 1, 100, 32767, "forced PID and positive final DAC saturation");
        f_base_nkt = -32760;
        feedback_step(200, 1, 0, 1, -100, -32767, "negative final DAC saturation");
        f_limit = 0; f_base_nkt = 1000;
        feedback_step(0, 1, 0, 1, 0, 1000, "zero correction limit disables correction magnitude");

        #3 rst_n = 0; #1;
        check(c_correction === 16'sd0 && c_error === 17'sd0,
              "core reset asserts without clock edge");
        check(f_found === 1'b0 && f_locked === 1'b0 && f_correction === 16'sd0,
              "feedback reset clears detector and correction asynchronously");
        $display("PASS: tb_feedback_regression checks=%0d", checks);
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "FAIL feedback regression watchdog timeout");
    end
endmodule
