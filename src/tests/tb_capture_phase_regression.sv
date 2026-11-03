`timescale 1ns/1ps
module tb_capture_phase_regression;
    reg clk=0;
    always #20 clk=~clk;
    reg rst_n=0, button_reset=0, pid_clear=0, feedback_enable=1;
    reg [2:0] controller_state=0;
    reg sequence_start=0, restart_scan=0, kick=0;
    reg pid_active=0, window_found=0, window_confirmed=0;
    wire [1:0] phase;
    wire capture_valid, capture_event, captured_seen, phase_change;
    integer checks=0;
    capture_phase_status dut(.*);
    task tick; @(posedge clk); #1; endtask
    task check(input bit ok, input string label);
        checks++;
        if (!ok) $fatal(1,"FAIL capture status: %s",label);
    endtask
    initial begin
        tick(); check(phase==0 && !captured_seen,"reset is idle without history");
        @(negedge clk); rst_n=1; sequence_start=1;
        tick(); check(phase==1 && phase_change,"accepted sequence enters scan");
        @(negedge clk); sequence_start=0; controller_state=1;
        tick(); check(phase==1 && !phase_change,"scan remains scan before kick");
        @(negedge clk); controller_state=2; kick=1;
        tick(); check(phase==2 && !capture_valid,"kick starts acquisition, even with scan still moving");
        @(negedge clk); pid_active=1;
        tick(); check(phase==2 && !captured_seen,"bypass enable alone is not successful capture");
        @(negedge clk); window_found=1;
        tick(); check(phase==2,"window must be confirmed while feedback runs");
        @(negedge clk); window_confirmed=1;
        tick(); check(phase==3 && capture_valid && capture_event && captured_seen,"qualified running PID enters feedback");
        tick(); check(phase==3 && !capture_event && !phase_change,"entry event lasts one clock");
        @(negedge clk); kick=0; controller_state=4;
        repeat(4) tick(); check(phase==3,"PID remains feedback after waveform completes");
        @(negedge clk); window_found=0; pid_active=0;
        tick(); check(phase==1 && !capture_valid && captured_seen,"loss enters rescan preparation and retains history");
        @(negedge clk); restart_scan=1; sequence_start=1;
        tick(); check(phase==1 && !capture_event,"recovery starts new scan");
        @(negedge clk); restart_scan=0; sequence_start=0; window_confirmed=0; controller_state=1;
        tick(); check(phase==1 && captured_seen,"new attempt does not erase capture history");
        @(negedge clk); kick=1; controller_state=2;
        tick(); check(phase==2,"second kick starts capture");
        @(negedge clk); pid_active=1; window_found=1; window_confirmed=1;
        tick(); check(phase==3 && capture_event,"second acquisition raises a new event");
        @(negedge clk); feedback_enable=0; pid_active=0; kick=0; controller_state=4;
        tick(); check(phase==0 && !capture_valid && captured_seen,"disabled feedback/frozen correction is not active PID");
        @(negedge clk); feedback_enable=1; window_confirmed=0; window_found=0;
        tick(); check(phase==2,"reenable awaits acquisition");
        @(negedge clk); pid_clear=1;
        tick(); check(phase==2 && !captured_seen && !capture_event,"clear resets history without pretending scan restarted");
        @(negedge clk); pid_clear=0; pid_active=1; window_found=1; window_confirmed=1;
        tick(); check(phase==3 && captured_seen,"can reacquire after clear");
        @(negedge clk); button_reset=1;
        tick(); check(phase==0 && !captured_seen && !capture_valid,"button reset dominates stale active inputs");
        @(negedge clk); button_reset=0; pid_active=0; window_found=0; window_confirmed=0; controller_state=1;
        tick(); check(phase==1,"scan without a reachable kick");
        @(negedge clk); controller_state=4;
        tick(); check(phase==0,"no-kick completed sweep must not claim acquisition");
        @(negedge clk); controller_state=2; kick=1;
        tick(); check(phase==2,"begin unsuccessful acquisition");
        @(negedge clk); controller_state=5; kick=0;
        tick(); check(phase==1,"automatic return is scan, not capture");
        @(negedge clk); controller_state=4;
        tick(); check(phase==0,"return clears stale kick history");
        @(negedge clk); rst_n=0; #1;
        check(phase==0 && !capture_event && !captured_seen,"clock-loss reset clears status asynchronously");
        $display("PASS: tb_capture_phase_regression checks=%0d",checks);
        $finish;
    end
    initial begin #100000; $fatal(1,"capture phase test timeout"); end
endmodule
