`timescale 1ns / 1ps

// Self-checking controller regression. Compile with control.v; no FPGA IP needed.
module tb_control_regression;
    localparam [2:0] IDLE = 0, SCAN = 1, FALL = 2, RISE = 3, DONE = 4, RETURN = 5;
    reg clk = 0;
    reg clock_running = 0;
    always #20 begin
        if (clock_running) clk = ~clk;
        else clk = 0;
    end

    reg rst_n = 1;
    reg btn_start = 0, btn_reset = 0;
    reg auto_enable = 0;
    reg [15:0] auto_freq = 62500;
    reg [15:0] nkt_start = 10, nkt_target = 12, nkt_final = 14;
    reg [31:0] scan_us = 0;
    reg [15:0] aom_base = 100, aom_min = 90, aom_final = 110;
    reg [15:0] fall_ns = 100, rise_ns = 41;
    wire [15:0] nkt, aom;
    wire kick, kick_done, fall_done;
    wire [2:0] state;
    integer ticks, checks = 0;
    reg saw_kick;

    dks_power_kicker dut (
        .clk(clk), .rst_n(rst_n), .btn_start(btn_start), .btn_reset(btn_reset),
        .auto_sweep_enable(auto_enable), .auto_sweep_freq_Hz(auto_freq),
        .DAC1_START_VAL(nkt_start), .NKT_TARGET_VAL(nkt_target),
        .NKT_FINAL_VAL(nkt_final), .NKT_RAMP_DIV(scan_us),
        .SCAN_STOP_OFFSET_NS(32'sd0), .PID_START_DELAY_NS(32'd200),
        .pid_loop_active(1'b0), .pid_restart_scan(1'b0),
        .AOM_INIT_VAL(aom_base), .AOM_KICK_VAL(aom_min),
        .AOM_FULL_VAL(aom_final), .AOM_DROP_STEP(fall_ns),
        .AOM_RISE_STEP(rise_ns), .signal_1_nkt(nkt), .signal_2_aom(aom),
        .kick(kick), .kick_done(kick_done), .kick_fall_done(fall_done),
        .state_debug(state)
    );

    task automatic check(input bit condition, input string description);
        begin
            checks = checks + 1;
            if (!condition) $fatal(1, "FAIL: %s at %0t", description, $time);
        end
    endtask

    task automatic tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task automatic sync_reset;
        begin
            @(negedge clk);
            btn_start = 0;
            btn_reset = 1;
            tick();
            check(state === IDLE && nkt === nkt_start && aom === aom_base,
                  "button reset synchronously loads the current VIO settings");
            check(!kick && !kick_done && !fall_done, "button reset clears status");
            @(negedge clk);
            btn_reset = 0;
        end
    endtask

    task automatic manual_start;
        begin
            @(negedge clk);
            btn_start = 1;
            tick();
            check(state === SCAN && nkt === nkt_start && aom === aom_base,
                  "manual edge starts scan at configured base values");
            @(negedge clk);
            btn_start = 0;
        end
    endtask

    task automatic wait_state(input [2:0] expected, input integer limit);
        integer elapsed;
        begin
            elapsed = 0;
            while (state !== expected && elapsed < limit) begin
                tick();
                elapsed = elapsed + 1;
            end
            check(state === expected, "state reached within bounded timeout");
        end
    endtask

    initial begin
        // With the clock halted, asserting reset must clear all outputs, and
        // moving VIO values must not act as asynchronous set/reset controls.
        #1 rst_n = 0;
        #1;
        check(state === IDLE && nkt === 16'd0 && aom === 16'd0,
              "asynchronous reset uses fixed zero outputs with no clock");
        check(!kick && !kick_done && !fall_done, "asynchronous status reset");
        nkt_start = 77;
        aom_base = 333;
        nkt_target = 78;
        nkt_final = 80;
        scan_us = 123;
        aom_min = 200;
        aom_final = 350;
        fall_ns = 321;
        rise_ns = 123;
        #80;
        check(nkt === 16'd0 && aom === 16'd0,
              "VIO changes under reset cannot change outputs without a clock");
        check(dut.cfg_dac1_start === 16'd0 && dut.cfg_aom_base === 16'd0 &&
              dut.cfg_scan_us === 32'd1 && dut.cfg_fall_ns === 16'd1,
              "configuration registers also have constant async reset values");
        rst_n = 1;
        #80;
        check(nkt === 16'd0 && aom === 16'd0,
              "reset release alone does not load dynamic VIO inputs");
        clock_running = 1;
        tick();
        check(state === IDLE && nkt === 16'd77 && aom === 16'd333,
              "first normal clock loads idle outputs");
        check(dut.cfg_dac1_start === 16'd77 && dut.cfg_scan_us === 32'd123,
              "first idle clock synchronously loads configuration");

        // A manual run snapshots waveform settings. Zero scan time keeps the
        // existing 1 us clamp: delta 4, 25 clocks / 4 = 6 clocks per DAC code.
        @(negedge clk);
        nkt_start = 10; nkt_target = 12; nkt_final = 14; scan_us = 0;
        aom_base = 100; aom_min = 90; aom_final = 110;
        fall_ns = 100; rise_ns = 41;
        sync_reset();
        manual_start();
        nkt_start = 44; nkt_target = 45; nkt_final = 50; scan_us = 100;
        aom_base = 900; aom_min = 800; aom_final = 950;
        fall_ns = 60000; rise_ns = 60000;
        ticks = 0;
        while (state === SCAN && ticks < 100) begin
            tick();
            ticks = ticks + 1;
            check(aom === 16'd100, "AOM holds captured base while scanning");
            if (ticks < 6) check(nkt === 16'd10, "scan divider holds initial code");
            if (ticks == 6) check(nkt === 16'd11, "first scan step after 6 clocks");
            if (ticks == 12) check(nkt === 16'd12, "second scan step reaches trigger");
        end
        check(state === FALL && ticks == 13 && kick,
              "captured NKT trigger starts fall on following scan clock");
        check(dut.cfg_dac1_start === 16'd10 && dut.cfg_dac1_kick === 16'd12 &&
              dut.cfg_aom_base === 16'd100 && dut.cfg_fall_ns === 16'd100,
              "mid-cycle VIO edits do not replace the waveform snapshot");
        tick();
        check(state === FALL && aom === 16'd97 && !fall_done,
              "100 ns fall uses 3 clocks: first distributed step");
        tick();
        check(state === FALL && aom === 16'd94 && !fall_done,
              "100 ns fall: second distributed step");
        tick();
        check(state === RISE && aom === 16'd90 && fall_done,
              "100 ns fall reaches exact minimum after 120 ns");
        tick();
        check(state === RISE && aom === 16'd100 && fall_done,
              "41 ns rise uses 2 clocks: midpoint");
        tick();
        check(state === DONE && aom === 16'd110 && nkt === 16'd12 &&
              kick_done && !kick && fall_done,
              "rise completes at 80 ns and NKT stays at its captured trigger");
        repeat (3) tick();
        check(nkt === 16'd12 && aom === 16'd110,
              "DONE continues holding captured values after VIO edits");

        // Descending scan with the trigger outside the scan range terminates
        // at the configured end without generating a kick.
        @(negedge clk);
        nkt_start = 15; nkt_target = 30; nkt_final = 10; scan_us = 1;
        aom_base = 100; aom_min = 90; aom_final = 100;
        fall_ns = 40; rise_ns = 40;
        sync_reset();
        manual_start();
        ticks = 0;
        saw_kick = 0;
        while (state === SCAN && ticks < 100) begin
            tick();
            ticks = ticks + 1;
            saw_kick = saw_kick | kick;
        end
        check(state === DONE && ticks == 26 && nkt === 16'd10 && !saw_kick,
              "descending scan terminates after five 5-clock steps plus endpoint check");
        tick();
        check(kick_done && !fall_done && aom === 16'd100,
              "no-trigger completion does not arm feedback");

        // Reversed AOM direction and zero durations exercise saturation and
        // the one-clock minimum duration independently of the nominal case.
        @(negedge clk);
        nkt_start = 15; nkt_target = 13; nkt_final = 10;
        aom_base = 10; aom_min = 20; aom_final = 5;
        fall_ns = 0; rise_ns = 0;
        sync_reset();
        manual_start();
        wait_state(FALL, 20);
        check(nkt === 16'd13, "descending trigger is reached exactly");
        tick();
        check(state === RISE && aom === 16'd20 && fall_done,
              "zero-duration reversed fall clamps to one clock");
        tick();
        check(state === DONE && aom === 16'd5 && kick_done,
              "zero-duration reversed rise clamps to one clock");

        // Auto mode must return NKT to the captured start before starting the
        // next cycle. A 62.5 kHz setting gives a short 400-clock test period.
        @(negedge clk);
        nkt_start = 20; nkt_target = 22; nkt_final = 24; scan_us = 0;
        aom_base = 100; aom_min = 90; aom_final = 100;
        fall_ns = 40; rise_ns = 40;
        sync_reset();
        auto_enable = 1;
        tick();
        check(state === SCAN, "rising auto enable starts an idle controller");
        wait_state(DONE, 40);
        wait_state(RETURN, 450);
        check(nkt === 16'd22 && dut.pending_auto_return,
              "automatic return starts from captured trigger");
        wait_state(DONE, 60);
        check(nkt === 16'd20 && !dut.pending_auto_return,
              "automatic return reaches start and clears pending flag");
        wait_state(SCAN, 450);
        check(nkt === 16'd20 && !kick_done && !fall_done,
              "next auto cycle resets waveform and feedback-arm status");

        // Synchronous button reset wins over an active auto cycle and captures
        // new parameters. Disabling auto leaves the controller idle.
        @(negedge clk);
        auto_enable = 0;
        nkt_start = 30; aom_base = 200;
        sync_reset();
        repeat (3) tick();
        check(state === IDLE && nkt === 16'd30 && aom === 16'd200,
              "button reset interrupts auto mode and holds new idle values");

        // Assert the hardware reset during an active waveform with no clock.
        nkt_target = 31; nkt_final = 34;
        manual_start();
        @(negedge clk);
        clock_running = 0;
        #1 rst_n = 0;
        #1;
        check(state === IDLE && nkt === 16'd0 && aom === 16'd0 &&
              !kick && !kick_done && !fall_done,
              "hardware reset interrupts an active waveform without a clock");
        nkt_start = 65535; aom_base = 65535;
        #80;
        check(nkt === 16'd0 && aom === 16'd0,
              "dynamic reset input changes cannot asynchronously set outputs");

        $display("PASS: tb_control_regression (%0d checks)", checks);
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "FAIL: controller regression watchdog timeout");
    end
endmodule
