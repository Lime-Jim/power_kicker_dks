`timescale 1ns/1ps
// Exercise the actual VIO -> controller -> PD qualification -> PID wiring.
module tb_pid_delay_regression;
    reg clk=0;
    always #20 clk=~clk;
    integer checks=0;
    top_power_kicker dut(
        .sys_clk_p(clk), .sys_clk_n(~clk), .fpga_clk_p(1'b0), .fpga_clk_n(1'b1),
        .adc_clk_p(1'b0), .adc_clk_n(1'b1), .adc_data_p1(14'd0), .adc_data_n1(14'd0),
        .key1_rst(1'b1), .key2_start(1'b1), .ext_reset(1'b0), .uart_rx(1'b1));
    task tick;
        @(posedge clk); #1;
    endtask
    task check(input bit pass, input string label);
        checks++;
        if (!pass) $fatal(1,"FAIL PID delay: %s at %0t",label,$time);
    endtask
    task setup(input integer fall_ns, input reg [31:0] delay_ns,
               input integer stop_ns, input bit in_window);
        @(negedge clk);
        force dut.btn_reset_level=1'b1;
        force dut.btn_start_level=1'b0;
        dut.u_vio_control.probe_out0=0;
        dut.u_vio_control.probe_out2=1000;
        dut.u_vio_control.probe_out3=500;
        dut.u_vio_control.probe_out4=fall_ns;
        dut.u_vio_control.probe_out5=80;
        dut.u_vio_control.probe_out6=0;
        dut.u_vio_control.probe_out7=10;
        dut.u_vio_control.probe_out8=1;
        dut.u_vio_control.probe_out9=1;
        dut.u_vio_control.probe_out10=1000;
        dut.u_vio_control.probe_out11=stop_ns;
        dut.u_vio_pid.probe_out0=1;
        dut.u_vio_pid.probe_out3=0;
        dut.u_vio_pid.probe_out7=1;
        dut.u_vio_pid.probe_out9=delay_ns;
        dut.u_vio_pid.probe_out10=1;
        dut.u_hardware.pd_adc_sample_tick=1;
        dut.u_hardware.pd_adc_sample=in_window ? 16'sd5761 : 16'sd0;
        repeat(2) tick();
        check(!dut.w_pid_delay_done && !dut.w_pid_active,"reset clears timer and PID");
        check(dut.w_capture_phase==0 && !dut.w_captured_seen,"reset clears supervisory status and history");
        @(negedge clk); force dut.btn_reset_level=1'b0;
        tick();
    endtask
    task start_sequence;
        @(negedge clk); force dut.btn_start_level=1'b1;
        tick();
        check(dut.u_logic.state==1,"accepted sequence start");
        check(dut.w_capture_phase==1,"real start event enters scan phase");
        @(negedge clk); force dut.btn_start_level=1'b0;
    endtask
    task wait_kick;
        integer n;
        n=0;
        while(!dut.w_kick_sig && n<100) begin tick(); n++; end
        check(dut.w_kick_sig,"kick starts within timeout");
    endtask
    task recover_sequence;
        integer n;
        n=0;
        while(!dut.w_pid_restart_scan && n<8) begin tick(); n++; end
        check(dut.w_pid_restart_scan,"loss requests a fresh scan within bounded latency");
        check(!dut.w_pid_active,"pending recovery blocks same-position PID re-entry");
        tick();
        check(dut.u_logic.state==1 && dut.w_nkt_data==0 && !dut.w_pid_delay_done,
              "recovery returns to configured scan start and resets kick delay");
        check(dut.w_capture_phase==1 && dut.w_captured_seen,"real loss rescans while preserving capture history");
        check(!dut.w_pid_active && dut.w_pid_nkt_corr==0 &&
              dut.u_pd_pid_feedback.u_nkt_pid.i_accum==0 && !dut.vio_pid_locked,
              "new attempt clears PID correction, integral and valid state");
    endtask
    task delay_case(input integer fall_ns, input integer delay_ns,
                    input integer expected_ticks);
        setup(fall_ns,delay_ns,0,1);
        start_sequence(); wait_kick();
        check(dut.w_pid_delay_done==(expected_ticks==0),"zero delay qualifies at kick edge");
        for(integer n=1;n<=expected_ticks;n++) begin
            tick();
            check(dut.w_pid_delay_done==(n==expected_ticks),"exact independently timed eligibility");
            check(!dut.w_pid_active,"no PID before eligibility is sampled");
        end
        if(expected_ticks*40<fall_ns)
            check(!dut.w_kick_fall_done,"PID timing can expire before fall completes");
        tick();
        check(dut.w_pd_step_found && dut.w_pid_active,"in-window sample activates PID after delay");
        tick();
        check(dut.w_pid_nkt_corr!=0,"PID computes correction on subsequent sample");
        repeat(30) tick();
        check(dut.w_pid_delay_done,"timer remains done without wrapping");
        check(dut.w_capture_phase==3 && dut.w_capture_valid && dut.w_captured_seen,
              "stable real PID loop reports confirmed feedback phase");
    endtask
    initial begin
        #2; dut.u_hardware.clocks_locked=1;
        repeat(270) tick();
        delay_case(800,0,0);
        delay_case(800,1,1);
        delay_case(800,40,1);
        delay_case(800,41,2);
        delay_case(80,200,5); // Timer keeps running after full kick completes.
        delay_case(800,200,5); // Same PID timing with tenfold fall duration.

        setup(80,80,400,1); start_sequence(); wait_kick();
        repeat(2) tick();
        check(dut.w_pid_delay_done && !dut.w_scan_stopped && !dut.w_pid_active,
              "delay expiration cannot bypass forward scan stop");
        repeat(8) tick();
        check(dut.w_scan_stopped && !dut.w_pid_active,"scan stops at positive offset");
        tick(); check(dut.w_pid_active,"PID starts once both gates qualify");

        setup(80,80,0,0); start_sequence(); wait_kick();
        repeat(10) tick();
        check(dut.w_pid_delay_done && !dut.w_pid_active,"delay alone cannot bypass PD window");
        @(negedge clk);
        dut.u_vio_pid.probe_out7=3;
        dut.u_hardware.pd_adc_sample=5761;
        tick(); check(!dut.w_pid_active,"confirmation sample 1");
        tick(); check(!dut.w_pid_active,"confirmation sample 2");
        tick(); check(dut.w_pid_active,"confirmation sample 3");
        tick();
        @(negedge clk); dut.u_hardware.pd_adc_sample=0;
        tick();
        check(!dut.w_pd_step_found && !dut.w_pid_active && dut.w_pid_nkt_data==dut.w_nkt_data,
              "required-window mode: single outlier exits PID and removes correction");
        recover_sequence();
        @(negedge clk); dut.u_hardware.pd_adc_sample=5761;
        wait_kick();
        tick(); check(!dut.w_pid_active,"recovery repeats full independent kick delay");
        tick(); check(dut.w_pid_delay_done && !dut.w_pid_active,"recovery delay completes before qualification");
        tick(); check(!dut.w_pid_active,"reacquisition sample 1");
        tick(); check(!dut.w_pid_active,"reacquisition sample 2");
        tick(); check(dut.w_pid_active,"reacquisition after new scan, kick, delay and 3 samples");
        repeat(2) tick();
        @(negedge clk); dut.u_hardware.pd_adc_sample=0;
        tick(); recover_sequence(); // A second loss must repeat the same loop.
        @(negedge clk); dut.u_vio_pid.probe_out0=0;
        tick(); check(!dut.w_pid_active,"feedback enable is still required");

        setup(800,200,0,1); start_sequence();
        dut.u_vio_pid.probe_out9=40; // Edit during scan, before kick.
        wait_kick(); repeat(4) tick();
        check(!dut.w_pid_delay_done,"in-flight VIO edit cannot shorten captured delay");
        tick(); check(dut.w_pid_delay_done,"captured delay expires at original 200 ns");
        setup(800,40,0,1); start_sequence(); wait_kick();
        tick(); check(dut.w_pid_delay_done,"next sequence captures new delay");

        setup(80,32'hffffffff,0,1); start_sequence(); wait_kick();
        check(dut.u_logic.pid_delay_remaining==32'd107374183,"max unsigned delay rounds without overflow");
        repeat(20) tick();
        check(!dut.w_pid_delay_done,"large delay does not become immediate");
        @(negedge clk); force dut.btn_reset_level=1'b1;
        tick(); check(!dut.w_pid_delay_done && !dut.u_logic.pid_delay_running,"button reset cancels countdown");

        setup(80,0,0,1);
        dut.u_vio_control.probe_out8=20; // Trigger outside [0,10] mV.
        start_sequence(); repeat(260) tick();
        check(!dut.w_pid_delay_done && !dut.w_pid_active,"no kick means no PID delay event");

        setup(80,50000,0,1);
        @(negedge clk);
        dut.u_vio_control.probe_out1=62500;
        dut.u_vio_control.probe_out0=1;
        tick(); wait_kick();
        repeat(380) begin
            tick();
            check(!dut.w_pid_delay_done,"long delay cannot leak across auto cycles");
        end
        wait_kick();
        check(dut.u_logic.pid_delay_remaining==1250,"automatic next kick restarts full countdown");

        // Window bypass must never become an unrestricted force-enable.
        setup(800,200,0,0);
        @(negedge clk); dut.u_vio_pid.probe_out10=0;
        tick(); check(!dut.w_pid_active,"bypass cannot start PID before kick");
        start_sequence(); wait_kick();
        repeat(4) begin tick(); check(!dut.w_pid_active,"bypass respects kick delay"); end
        tick();
        check(dut.w_pid_active && !dut.w_pd_step_found && !dut.w_kick_fall_done,
              "bypass starts outside window at independent delay, before fall finishes");
        tick();
        check(dut.w_pid_nkt_corr==1000 && dut.w_pid_nkt_data!=dut.w_nkt_data,
              "bypass corrects large error subject to existing output limit");
        repeat(8) begin tick(); check(dut.w_pid_active,"out-of-window samples cannot exit bypass mode"); end
        check(dut.w_capture_phase==2 && !dut.w_capture_valid && !dut.w_captured_seen,
              "bypass correction outside window stays in capture phase");
        @(negedge clk); dut.u_vio_pid.probe_out6=1;
        tick(); check(!dut.w_pid_active && dut.w_pid_nkt_data==dut.w_nkt_data && dut.w_pid_nkt_corr==0,
                      "clear inhibits bypass and clears correction");
        @(negedge clk); dut.u_vio_pid.probe_out6=0;
        tick(); check(dut.w_pid_active,"bypass resumes after clear without restarting kick delay");
        @(negedge clk); dut.u_vio_pid.probe_out10=1;
        tick(); check(!dut.w_pid_active,"live switch to required mode restores window gate");
        @(negedge clk); dut.u_vio_pid.probe_out10=0;
        tick(); check(dut.w_pid_active,"live switch back to bypass permits PID outside window");
        @(negedge clk); dut.u_hardware.pd_adc_sample=5761;
        repeat(3) tick();
        check(dut.pid_window_confirmed,"bypass mode arms loss monitor after actual acquisition");
        @(negedge clk); dut.u_hardware.pd_adc_sample=0;
        tick(); recover_sequence();
        @(negedge clk); dut.u_vio_pid.probe_out0=0;
        tick(); check(!dut.w_pid_active,"bypass respects master feedback disable");

        setup(80,80,400,0);
        dut.u_vio_pid.probe_out10=0;
        start_sequence(); wait_kick(); repeat(2) tick();
        check(dut.w_pid_delay_done && !dut.w_scan_stopped && !dut.w_pid_active,
              "bypass still waits for scan-stop");
        check(dut.w_capture_phase==2,"kick/capture overlaps continuing positive-offset scan");
        repeat(8) tick();
        check(dut.w_scan_stopped && dut.w_pid_active && !dut.w_pd_step_found,
              "bypass activates when scan-stop arrives with PD outside window");
        @(negedge clk); force dut.btn_reset_level=1'b1;
        tick(); check(!dut.w_pid_active && !dut.w_pid_delay_done,"button reset inhibits bypass");

        setup(80,0,0,0); dut.u_vio_pid.probe_out10=0;
        dut.u_vio_control.probe_out8=20;
        start_sequence(); repeat(260) tick();
        check(!dut.w_pid_active,"bypass cannot activate on a sequence without kick");

        // Periodic auto sweep must not interrupt a healthy feedback loop.
        setup(80,80,0,1);
        @(negedge clk);
        dut.u_vio_control.probe_out1=62500;
        dut.u_vio_control.probe_out0=1;
        tick(); wait_kick(); repeat(6) tick();
        check(dut.w_pid_active,"automatic sequence captures PID");
        repeat(850) begin
            tick();
            check(dut.w_pid_active && dut.u_logic.state==4 && !dut.w_sequence_start,
                  "healthy PID suppresses periodic return and next auto sweep");
        end
        @(negedge clk); dut.u_hardware.pd_adc_sample=0;
        tick(); recover_sequence();

        // A late delay must not engage bypass while an unsuccessful automatic
        // attempt is already returning DAC1 to the start value.
        setup(80,14000,0,0);
        dut.u_vio_pid.probe_out10=0;
        @(negedge clk);
        dut.u_vio_control.probe_out1=62500;
        dut.u_vio_control.probe_out0=1;
        tick(); wait_kick();
        repeat(375) begin
            tick();
            check(!dut.w_pid_active,"PID cannot start while automatic return moves the baseline");
        end
        check(dut.w_pid_delay_done && !dut.w_scan_stopped,"late delay is held off during return");

        setup(80,0,0,0); dut.u_vio_pid.probe_out10=0;
        start_sequence(); wait_kick(); tick();
        check(dut.w_pid_active,"bypass active before clock loss test");
        @(negedge clk); dut.u_hardware.clocks_locked=0; #1;
        check(!dut.w_pid_delay_done && !dut.w_pid_active,"clock-loss reset cancels PID delay");
        $display("PASS: tb_pid_delay_regression checks=%0d",checks);
        $finish;
    end
    initial begin #1000000; $fatal(1,"PID delay watchdog"); end
endmodule
