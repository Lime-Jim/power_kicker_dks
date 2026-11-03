`timescale 1ns / 1ps

// Real DAC RTL and UNISIM DDR/differential primitives; ILA is a passive mock.
// This validates digital edge ordering/CDC behavior, not board analog timing.
module tb_dac_regression;
    reg clk_25m = 0;
    always #20 clk_25m = ~clk_25m;
    reg dac_clk = 0;
    // Non-coincident clock edges exercise CDC rather than simulator race order.
    initial begin
        #0.3;
        forever #1 dac_clk = ~dac_clk;
    end

    reg [15:0] ext_nkt = 16'h1357, ext_aom = 16'h2468;
    reg done_flag = 0;
    wire frame_p, frame_n, dci_p, dci_n;
    wire [15:0] data_p, data_n;
    reg monitor_enable = 0;
    integer checks = 0, issued = 0, received = 0, frame_pulses = 0;
    reg [31:0] expected_pairs [0:255];
    realtime issued_at [0:255];
    reg [31:0] previous_source = 0, previous_output = 0;
    reg [15:0] rise_sample, expected_nkt, expected_aom;
    reg expected_frame;
    reg [31:0] observed_pair;
    realtime latency, frame_start;
    integer i, initial_received;

    test_ad9122 dut (
        .clk_25m(clk_25m), .fpga_clk_p(dac_clk), .fpga_clk_n(~dac_clk),
        .ext_nkt_data(ext_nkt), .ext_aom_data(ext_aom),
        .key1(1'b1), .key2(1'b1), .done_flag(done_flag),
        .dac_frame_p(frame_p), .dac_frame_n(frame_n),
        .dac_dci_p(dci_p), .dac_dci_n(dci_n),
        .dac_data_p(data_p), .dac_data_n(data_n)
    );

    task automatic check(input bit condition, input string description);
        begin
            checks = checks + 1;
            if (!condition) $fatal(1, "FAIL: %s at %0t", description, $time);
        end
    endtask

    // Scoreboard stores each pair accepted at the documented 25 MHz boundary.
    // Output pairs must appear once, in order, with both channels from the same
    // source sample. No receiver internals are used to decide expected values.
    always @(posedge clk_25m) begin
        if (dut.sys_rst_n && {ext_nkt, ext_aom} !== previous_source) begin
            check(issued < 256, "scoreboard capacity");
            expected_pairs[issued] = {ext_nkt, ext_aom};
            issued_at[issued] = $realtime;
            previous_source = {ext_nkt, ext_aom};
            issued = issued + 1;
        end
    end

    // ODDRE1 captures D1 and D2 together at the rising clock. D1 appears on the
    // rising edge and that captured D2 appears on the following falling edge.
    always @(posedge dut.clk_dco) begin
        expected_nkt = dut.nkt_data_dac;
        expected_aom = dut.aom_data_dac;
        expected_frame = dut.dac_frame_i;
        #0.25;
        if (monitor_enable) begin
            check(data_p === expected_nkt, "rising DDR edge carries NKT/D1");
            check(data_n === ~data_p, "rising data pins are complementary");
            check(dci_p === 1'b1 && dci_n === 1'b0, "DCI rising edge ordering");
            check(frame_p === expected_frame && frame_n === ~frame_p,
                  "frame rising edge and differential polarity");
            rise_sample = data_p;
        end
    end

    always @(negedge dut.clk_dco) begin
        #0.25;
        if (monitor_enable) begin
            check(data_p === expected_aom, "falling DDR edge carries captured AOM/D2");
            check(data_n === ~data_p, "falling data pins are complementary");
            check(dci_p === 1'b0 && dci_n === 1'b1, "DCI falling edge ordering");
            check(frame_p === expected_frame && frame_n === ~frame_p,
                  "frame falling edge holds rising-edge sample");
            observed_pair = {rise_sample, data_p};
            if (observed_pair !== previous_output) begin
                check(received < issued, "DAC cannot emit an unissued pair");
                check(observed_pair === expected_pairs[received],
                      "DAC output pair is coherent and follows source order");
                latency = $realtime - issued_at[received];
                check(latency >= 14.0 && latency <= 24.0,
                      "toggle synchronization plus wait transfers within 14..24 ns");
                previous_output = observed_pair;
                received = received + 1;
            end
        end
    end

    always @(posedge frame_p) begin
        if (monitor_enable) begin
            check(done_flag, "frame pulse only starts after configuration done");
            frame_pulses = frame_pulses + 1;
        end
    end

    task automatic wait_drained;
        integer attempts;
        begin
            attempts = 0;
            while ((received != issued || previous_source !== {ext_nkt, ext_aom}) && attempts < 100) begin
                @(negedge dac_clk);
                #0.4;
                attempts = attempts + 1;
            end
            check(received == issued && previous_source === {ext_nkt, ext_aom},
                  "all changed source pairs arrive within bounded timeout");
        end
    endtask

    task automatic check_frame_pulse;
        begin
            @(posedge frame_p);
            frame_start = $realtime;
            @(negedge frame_p);
            check(($realtime - frame_start) >= 31.99 &&
                  ($realtime - frame_start) <= 32.01,
                  "frame pulse lasts exactly 16 DAC clock periods (32 ns)");
        end
    endtask

    initial begin
        // Allow real UNISIM global startup reset to finish before pin checks.
        #120;
        @(posedge dac_clk);
        #0.5;
        rise_sample = data_p;
        monitor_enable = 1;
        check(dut.sys_rst_n === 1'b0 && dut.nkt_data_dac === 16'd0 &&
              dut.aom_data_dac === 16'd0,
              "startup local reset holds the uninitialized DAC pair at zero");
        check(issued == 0 && received == 0, "no pair accepted during startup reset");
        #9900;
        check(dut.sys_rst_n === 1'b0 && previous_output === 32'd0,
              "255-cycle startup hold blocks nonzero external data");
        check(frame_pulses == 0 && frame_p === 1'b0,
              "frame stays low before SPI completion");
        wait (dut.sys_rst_n === 1'b1);
        wait_drained();
        check(previous_output === 32'h1357_2468 && received == 1,
              "first nonzero pair is emitted after startup reset release");

        // Exercise every 25 MHz input period; channel values deliberately
        // differ strongly so swapped or mixed old/new halves cannot pass.
        for (i = 0; i < 64; i = i + 1) begin
            @(negedge clk_25m);
            ext_nkt = 16'h8001 + i * 17;
            ext_aom = 16'h7ffe - i * 31;
        end
        wait_drained();
        check(received == 65, "all 64 consecutive changing pairs delivered exactly once");
        initial_received = received;
        repeat (4) @(negedge clk_25m);
        check(received == initial_received, "unchanged inputs do not generate duplicate transfers");

        @(negedge clk_25m);
        ext_nkt = 0; ext_aom = 0;
        wait_drained();
        check(previous_output === 32'd0, "both output channels can return to zero");
        @(negedge clk_25m);
        ext_nkt = 16'hffff; ext_aom = 16'h0001;
        wait_drained();
        check(previous_output === 32'hffff_0001, "all sixteen data lanes preserve extremes");

        @(negedge clk_25m);
        done_flag = 1;
        check_frame_pulse();
        #80;
        check(frame_pulses == 1 && frame_p === 1'b0,
              "held done flag emits one finite frame pulse");
        done_flag = 0;
        #40;
        done_flag = 1;
        check_frame_pulse();
        #40;
        check(frame_pulses == 2 && frame_p === 1'b0,
              "a new done edge retriggers exactly one finite frame pulse");
        check(issued == received && received == 67, "final transfer scoreboard drained");

        $display("PASS: tb_dac_regression (%0d checks, %0d coherent pairs, %0d frame pulses)",
                 checks, received, frame_pulses);
        $finish;
    end

    initial begin
        #50000;
        $fatal(1, "FAIL: DAC regression watchdog timeout");
    end
endmodule
