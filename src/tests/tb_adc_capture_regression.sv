`timescale 1ns / 1ps

module tb_adc_capture_regression;
    reg adc_clk = 0, logic_clk = 0;
    reg adc_running = 1, logic_running = 1;
    always #2 if (adc_running) adc_clk = ~adc_clk;
    always #20 if (logic_running) logic_clk = ~logic_clk;
    reg rst_n = 0;
    reg [13:0] adc_raw = 0;
    wire signed [15:0] pd_sample, pd_adc_debug;
    wire pd_sample_tick;
    integer checks = 0;
    integer produced = 0, consumed = 0, source_count = 0, stimulus_count = 0;
    integer expected_samples [0:255];
    time expected_times [0:255];
    time previous_tick = 0;
    reg previous_tick_level = 0;
    integer expected_debug = 0;
    reg expected_toggle = 0;
    integer adc_release_edges = 0, logic_release_edges = 0;

    pd_adc_capture #(.AVG_BITS(7), .ADC_LEFT_SHIFT(2)) dut (
        .adc_clk(adc_clk), .logic_clk(logic_clk), .rst_n(rst_n),
        .adc_raw(adc_raw), .pd_sample(pd_sample),
        .pd_sample_tick(pd_sample_tick), .pd_adc_debug(pd_adc_debug)
    );

    task automatic check(input bit condition, input string label);
        begin
            checks = checks + 1;
            if (!condition) $fatal(1, "FAIL ADC capture: %s at %0t", label, $time);
        end
    endtask

    // Deliberately vary all discarded inputs. Terminal samples include both
    // two's-complement extrema, so averaging or unsigned conversion cannot pass.
    always @(negedge adc_clk) begin
        if (!dut.adc_rst_n) begin
            adc_raw = 0;
            stimulus_count = 0;
        end else begin
            stimulus_count = stimulus_count + 1;
            if (source_count == 127) begin
                case (produced % 8)
                    0: adc_raw = 14'h1fff; // +8191 -> +32764
                    1: adc_raw = 14'h2000; // -8192 -> -32768
                    2: adc_raw = 14'h3fff; // -1 -> -4
                    3: adc_raw = 14'h0001; // +1 -> +4
                    4: adc_raw = 14'h3f85; // -123 -> -492
                    5: adc_raw = 14'h07ff; // +2047 -> +8188
                    6: adc_raw = 14'h0000;
                    7: adc_raw = 14'h1000; // +4096 -> +16384
                endcase
            end else begin
                adc_raw = (stimulus_count * 137 + 23) & 14'h3fff;
            end
        end
    end

    // Reference the public input on every 128th accepted ADC edge, without
    // depending on DUT counters/data or duplicating its conversion expression.
    always @(posedge adc_clk or negedge dut.adc_rst_n) begin
        if (!dut.adc_rst_n) begin
            source_count = 0;
            produced = 0;
            expected_debug = 0;
            expected_toggle = 0;
        end else begin
            source_count = source_count + 1;
            if (source_count == 128) begin
                source_count = 0;
                expected_debug = (adc_raw >= 8192 ? integer'(adc_raw) - 16384 :
                                  integer'(adc_raw)) * 4;
                expected_samples[produced] = expected_debug;
                expected_times[produced] = $time;
                produced = produced + 1;
                expected_toggle = ~expected_toggle;
            end
        end
        #0.1;
        check($signed(pd_adc_debug) === expected_debug,
              "ADC debug must hold exact terminal raw sample (no averaging)");
        check(dut.pd_toggle_adc === expected_toggle,
              "source toggle occurs exactly once per 128 ADC edges");
    end

    always @(posedge logic_clk or negedge dut.logic_rst_n) begin
        if (!dut.logic_rst_n) begin
            consumed = 0;
            previous_tick = 0;
            previous_tick_level = 0;
            #0.2;
            check(pd_sample_tick === 1'b0 && pd_sample === 16'sd0,
                  "logic reset clears sample/tick asynchronously");
        end else begin
            #0.2;
            if (pd_sample_tick) begin
                check(!previous_tick_level, "sample tick is exactly one logic cycle wide");
                check(consumed < produced, "no output tick without an ADC sample");
                if ($signed(pd_sample) !== expected_samples[consumed])
                    $fatal(1, "FAIL ADC sample %0d: got=%0d expected=%0d",
                           consumed, pd_sample, expected_samples[consumed]);
                checks = checks + 1;
                check(($time - expected_times[consumed] >= 280) &&
                      ($time - expected_times[consumed] <= 320),
                      "toggle synchronization and data settling latency is 280..320 ns");
                if (consumed > 0)
                    check(($time - previous_tick == 480) || ($time - previous_tick == 520),
                          "512 ns source cadence is quantized to 480/520 ns logic ticks");
                previous_tick = $time;
                consumed = consumed + 1;
            end else if (consumed > 0) begin
                check($signed(pd_sample) === expected_samples[consumed-1],
                      "output sample remains stable between ticks");
            end
            previous_tick_level = pd_sample_tick;
        end
    end

    // Verify release takes exactly two local rising edges independently in each
    // domain. Asserting reset below also tests reset while each clock is stopped.
    always @(posedge adc_clk or negedge rst_n) begin
        if (!rst_n) adc_release_edges = 0;
        else if (adc_release_edges < 2) adc_release_edges = adc_release_edges + 1;
        #0.3;
        check(dut.adc_rst_n === (adc_release_edges >= 2), "ADC reset local synchronous release");
    end
    always @(posedge logic_clk or negedge rst_n) begin
        if (!rst_n) logic_release_edges = 0;
        else if (logic_release_edges < 2) logic_release_edges = logic_release_edges + 1;
        #0.3;
        check(dut.logic_rst_n === (logic_release_edges >= 2), "logic reset local synchronous release");
    end

    initial begin
        #123 rst_n = 1;
        wait (consumed >= 12);

        @(negedge logic_clk);
        rst_n = 0;
        logic_running = 0;
        #1;
        check(dut.logic_rst_n === 0 && pd_sample_tick === 0 && pd_sample === 0,
              "reset assertion works while logic clock is stopped");
        #62 rst_n = 1;
        #120;
        check(dut.adc_rst_n === 1 && dut.logic_rst_n === 0,
              "ADC reset releases while stopped logic domain stays reset");
        check(pd_sample_tick === 0 && pd_sample === 0, "stopped logic emits no stale tick");
        logic_running = 1;
        wait (consumed >= 8);

        @(negedge adc_clk);
        rst_n = 0;
        adc_running = 0;
        #1;
        check(dut.adc_rst_n === 0 && pd_adc_debug === 0,
              "reset assertion works while ADC clock is stopped");
        #79 rst_n = 1;
        #120;
        check(dut.adc_rst_n === 0 && dut.logic_rst_n === 1,
              "logic reset releases while stopped ADC domain stays reset");
        check(pd_sample_tick === 0 && consumed == 0, "no phantom output after independent reset release");
        adc_running = 1;
        wait (consumed >= 8);
        #1;
        $display("PASS: tb_adc_capture_regression checks=%0d", checks);
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "FAIL ADC capture regression watchdog timeout");
    end
endmodule
