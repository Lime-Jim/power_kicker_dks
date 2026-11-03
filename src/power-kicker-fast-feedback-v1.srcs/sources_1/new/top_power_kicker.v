`timescale 1ns / 1ps

module top_power_kicker(
    input  wire        sys_clk_p,
    input  wire        sys_clk_n,

    input  wire        fpga_clk_p,
    input  wire        fpga_clk_n,
    input  wire        adc_clk_p,
    input  wire        adc_clk_n,
    input  wire [13:0] adc_data_p1,
    input  wire [13:0] adc_data_n1,

    input  wire        key1_rst,
    input  wire        key2_start,
    input  wire        ext_reset,

    output wire        led_kick,

    output wire [15:0] dac_data_p,
    output wire [15:0] dac_data_n,
    output wire        dac_dci_p,
    output wire        dac_dci_n,
    output wire        dac_frame_p,
    output wire        dac_frame_n,

    output wire        dac_spi_ce,
    output wire        adc_spi_ce,
    output wire        clk_spi_ce,
    output wire        spi_clk,
    inout  wire        spi_io,

    input  wire        uart_rx,
    output wire        uart_tx
);

    wire        clk_logic_sync;
    wire        clocks_locked;
    wire [15:0] w_nkt_data;
    wire [15:0] w_aom_data;
    wire [15:0] w_pid_nkt_data;
    wire [15:0] w_pid_aom_data;
    wire        w_kick_sig;
    wire signed [15:0] w_pd_adc_sample;
    wire signed [15:0] w_pd_adc_sample_corrected;
    wire        w_pd_adc_sample_tick;
    wire        w_pd_step_found;
    wire        w_pid_active;
    wire [2:0] w_controller_state;
    (* keep = "true" *) wire [1:0] w_capture_phase;
    wire w_capture_valid;
    wire w_capture_event;
    (* keep = "true" *) wire w_captured_seen;
    wire w_phase_change;
    (* keep = "true" *) wire vio_pid_locked;
    wire        w_kick_done;
    wire        w_kick_fall_done;
    (* keep = "true" *) wire w_scan_stopped;
    (* keep = "true" *) wire w_pid_delay_done;
    wire w_sequence_start;
    (* keep = "true" *) wire w_pid_restart_scan;
    reg pid_restart_request = 1'b0;
    reg pid_window_confirmed = 1'b0;
    wire signed [15:0] w_pid_nkt_corr;
    wire signed [15:0] w_pid_aom_corr;

    // Reserved UART shadow values: deliberately not connected to ctrl_*.
    // VIO is the only active source; no automatic fallback or source mux.
    wire [15:0] cfg_dac1_start_code;
    wire [15:0] cfg_dac1_kick_code;
    wire [31:0] cfg_dac1_scan_ms;
    wire [15:0] cfg_dac2_base_code;
    wire [15:0] cfg_dac2_min_code;
    wire [15:0] cfg_dac2_fall_ms;
    wire [15:0] cfg_dac2_rise_ms;
    wire        cfg_pid_enable;
    wire signed [15:0] cfg_pid_target_code;
    wire signed [15:0] cfg_pid_window_code;
    wire signed [15:0] cfg_pid_kp;
    wire signed [15:0] cfg_pid_ki;
    wire signed [15:0] cfg_pid_kd;
    wire [15:0] cfg_pid_corr_limit;
    wire [7:0]  cfg_uart_last_addr;
    wire        cfg_uart_update_tick;

    (* keep = "true" *) wire [15:0] vio_sweep_start_mV;
    (* keep = "true" *) wire [31:0] vio_sweep_scan_us;
    (* keep = "true" *) wire [15:0] vio_sweep_final_mV;
    (* keep = "true" *) wire [15:0] vio_sweep_trigger_mV;
    // Preserve existing probe_out2 as the post-kick voltage source.
    // New probe_out10 adjusts only the pre-kick base voltage.
    (* keep = "true" *) wire [15:0] vio_kick_final_mV;
    (* keep = "true" *) wire [15:0] vio_kick_base_mV;
    (* keep = "true" *) wire signed [31:0] vio_sweep_stop_offset_ns;
    (* keep = "true" *) wire [15:0] vio_kick_min_mV;
    (* keep = "true" *) wire [15:0] vio_kick_fall_ns;
    (* keep = "true" *) wire [15:0] vio_kick_rise_ns;
    (* keep = "true" *) wire        vio_auto_sweep_enable;
    (* keep = "true" *) wire [15:0] vio_auto_sweep_freq_Hz;
    (* keep = "true" *) wire        vio_pid_feedback_enable;
    wire        vio_pid_clear;
    (* keep = "true" *) wire signed [15:0] vio_pid_target_mV;
    (* keep = "true" *) wire [15:0] vio_pid_window_mV;
    (* keep = "true" *) wire [7:0]  vio_pid_confirm_samples;
    (* keep = "true" *) wire signed [15:0] vio_pid_kp;
    (* keep = "true" *) wire signed [15:0] vio_pid_ki;
    (* keep = "true" *) wire signed [15:0] vio_pid_kd;
    (* keep = "true" *) wire [15:0] vio_pid_corr_limit;
    (* keep = "true" *) wire [31:0] vio_pid_start_delay_ns;
    (* keep = "true" *) wire vio_pid_require_window;
    wire        vio_pid_hold = 1'b0;

    // Assert on MMCM lock loss; release only on a valid logic-clock edge
    // after the startup guard. Use a registered reset, not a counter decode.
    reg [7:0] logic_rst_cnt = 8'd0;
    reg       logic_rst_n = 1'b0;
    wire      clock_ready_n;
    reset_sync u_logic_clock_reset (
        .clk(clk_logic_sync), .arst_n(clocks_locked), .rst_n(clock_ready_n)
    );
    always @(posedge clk_logic_sync or negedge clock_ready_n) begin
        if (!clock_ready_n) begin
            logic_rst_cnt <= 8'd0;
            logic_rst_n <= 1'b0;
        end else if (logic_rst_cnt != 8'hff) begin
            logic_rst_cnt <= logic_rst_cnt + 1'b1;
        end else begin
            logic_rst_n <= 1'b1;
        end
    end

    (* ASYNC_REG = "TRUE" *) reg key1_rst_meta = 1'b1;
    (* ASYNC_REG = "TRUE" *) reg key1_rst_sync = 1'b1;
    (* ASYNC_REG = "TRUE" *) reg key2_start_meta = 1'b1;
    (* ASYNC_REG = "TRUE" *) reg key2_start_sync = 1'b1;
    (* ASYNC_REG = "TRUE" *) reg ext_reset_meta = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg ext_reset_sync = 1'b0;

    always @(posedge clk_logic_sync) begin
        key1_rst_meta   <= key1_rst;
        key1_rst_sync   <= key1_rst_meta;
        key2_start_meta <= key2_start;
        key2_start_sync <= key2_start_meta;
        ext_reset_meta  <= ext_reset;
        ext_reset_sync  <= ext_reset_meta;
    end

    wire btn_reset_level = (~key1_rst_sync) | ext_reset_sync;
    wire btn_start_level = ~key2_start_sync;

    // Register the synchronized button reset instead of distributing a LUT
    // expression to all UART asynchronous-reset pins.
    reg uart_rst_n = 1'b0;
    always @(posedge clk_logic_sync or negedge logic_rst_n) begin
        if (!logic_rst_n)
            uart_rst_n <= 1'b0;
        else
            uart_rst_n <= ~btn_reset_level;
    end

    localparam [15:0] DAC_REAL_FULL_SCALE_MV = 16'd1500;
    localparam signed [15:0] FEEDBACK_ADC_OFFSET_MV = 16'sd21;

    function [15:0] sweep_mv_to_code;
        input [15:0] sweep_mV;
        reg [31:0] code_value;
        begin
            code_value = (sweep_mV * 32'd32767) / DAC_REAL_FULL_SCALE_MV;
            sweep_mv_to_code = (code_value > 32'd32767) ? 16'h7fff : code_value[15:0];
        end
    endfunction

    function [15:0] kick_mv_to_code;
        input [15:0] kick_mV;
        reg [31:0] code_value;
        begin
            code_value = (kick_mV * 32'd32767) / DAC_REAL_FULL_SCALE_MV;
            kick_mv_to_code = (code_value > 32'd32767) ? 16'h7fff : code_value[15:0];
        end
    endfunction

    function signed [15:0] adc_mv_to_code;
        input signed [15:0] adc_mV;
        reg signed [31:0] code_value;
        begin
            code_value = (adc_mV * 32'sd32767) / 32'sd875;
            if (code_value > 32'sd32767)
                adc_mv_to_code = 16'sh7fff;
            else if (code_value < -32'sd32768)
                adc_mv_to_code = 16'sh8000;
            else
                adc_mv_to_code = code_value[15:0];
        end
    endfunction

    function signed [15:0] adc_window_mv_to_code;
        input [15:0] window_mV;
        reg [31:0] code_value;
        begin
            code_value = (window_mV * 32'd32767) / 32'd875;
            adc_window_mv_to_code = (code_value > 32'd32767) ? 16'sh7fff : code_value[15:0];
        end
    endfunction

    // Active control parameters: VIO only (UART must not override these).
    wire [15:0] eff_initial_sweep_mV = vio_sweep_start_mV;
    wire [31:0] eff_sweep_scan_us    = (vio_sweep_scan_us == 32'd0) ? 32'd100000 : vio_sweep_scan_us;
    wire [15:0] eff_final_sweep_mV   = vio_sweep_final_mV;
    wire [15:0] eff_dac1_kick_mV     = vio_sweep_trigger_mV;
    wire [15:0] eff_kick_base_mV     = vio_kick_base_mV;
    wire [15:0] eff_kick_final_mV    = vio_kick_final_mV;
    wire [15:0] eff_kick_min_mV      = vio_kick_min_mV;
    wire [15:0] eff_kick_fall_ns     = vio_kick_fall_ns;
    wire [15:0] eff_kick_rise_ns     = vio_kick_rise_ns;

    wire [15:0] ctrl_sweep_initial_code = sweep_mv_to_code(eff_initial_sweep_mV);
    wire [15:0] ctrl_sweep_final_code   = sweep_mv_to_code(eff_final_sweep_mV);
    wire [15:0] ctrl_dac1_kick_code     = sweep_mv_to_code(eff_dac1_kick_mV);
    wire [31:0] ctrl_sweep_scan_us      = (eff_sweep_scan_us == 32'd0) ? 32'd1 : eff_sweep_scan_us;
    wire [15:0] ctrl_kick_base_code     = kick_mv_to_code(eff_kick_base_mV);
    wire [15:0] ctrl_kick_final_code    = kick_mv_to_code(eff_kick_final_mV);
    wire [15:0] ctrl_kick_min_code      = kick_mv_to_code(eff_kick_min_mV);
    wire [15:0] ctrl_kick_fall_ns       = (eff_kick_fall_ns == 16'd0) ? 16'd1 : eff_kick_fall_ns;
    wire [15:0] ctrl_kick_rise_ns       = (eff_kick_rise_ns == 16'd0) ? 16'd1 : eff_kick_rise_ns;
    wire        ctrl_pid_feedback_enable = vio_pid_feedback_enable;
    assign w_pid_restart_scan = pid_restart_request & ctrl_pid_feedback_enable &
                                logic_rst_n & ~btn_reset_level & ~vio_pid_clear;
    wire signed [15:0] ctrl_pid_target_code = adc_mv_to_code(vio_pid_target_mV);
    wire signed [15:0] ctrl_pid_window_code = adc_window_mv_to_code(vio_pid_window_mV);
    // PID delay is measured from kick start, independently of the AOM fall time.
    // Keep the scan-stop and consecutive PD-window qualification.
    wire        step_detect_arm = ctrl_pid_feedback_enable & w_pid_delay_done & w_scan_stopped;
    // Bypass only the PD window. Keep enable, kick delay, scan-stop and clear.
    // The detector continues reporting actual window qualification in both modes.
    wire        pid_window_bypass = step_detect_arm & ~vio_pid_require_window &
                                   logic_rst_n & ~btn_reset_level & ~vio_pid_clear &
                                   ~w_pid_restart_scan;
    wire        fast_pid_hold = vio_pid_hold | ~ctrl_pid_feedback_enable |
                                ~w_pid_delay_done | ~w_scan_stopped;

    // Treat loss as a new capture attempt, never as same-position re-entry.
    // In bypass mode acquisition is allowed outside the window; loss monitoring
    // starts only after the PD has subsequently qualified inside the window.
    always @(posedge clk_logic_sync or negedge logic_rst_n) begin
        if (!logic_rst_n) begin
            pid_restart_request <= 1'b0;
            pid_window_confirmed <= 1'b0;
        end else if (btn_reset_level || vio_pid_clear || !ctrl_pid_feedback_enable ||
                     w_sequence_start || !w_pid_delay_done || !w_scan_stopped) begin
            pid_restart_request <= 1'b0;
            pid_window_confirmed <= 1'b0;
        end else begin
            pid_restart_request <= 1'b0;
            if (w_pid_active) begin
                if (w_pd_step_found)
                    pid_window_confirmed <= 1'b1;
            end
            if (pid_window_confirmed && !w_pd_step_found)
                pid_restart_request <= 1'b1;
        end
    end
    wire signed [15:0] feedback_adc_offset_code = adc_mv_to_code(FEEDBACK_ADC_OFFSET_MV);
    wire signed [16:0] pd_adc_corrected_ext =
        {w_pd_adc_sample[15], w_pd_adc_sample} -
        {feedback_adc_offset_code[15], feedback_adc_offset_code};
    assign w_pd_adc_sample_corrected =
        (pd_adc_corrected_ext > 17'sd32767)  ? 16'sh7fff :
        (pd_adc_corrected_ext < -17'sd32768) ? 16'sh8000 :
                                               pd_adc_corrected_ext[15:0];

    uart_power_kick_params #(
        .CLK_FRE(25)
    ) u_uart_params (
        .clk              (clk_logic_sync),
        .rst_n            (uart_rst_n),
        .uart_rx_pin      (uart_rx),
        .uart_tx_pin      (uart_tx),
        .dac1_start_code  (cfg_dac1_start_code),
        .dac1_kick_code   (cfg_dac1_kick_code),
        .dac1_scan_ms     (cfg_dac1_scan_ms),
        .dac2_base_code   (cfg_dac2_base_code),
        .dac2_min_code    (cfg_dac2_min_code),
        .dac2_fall_ms     (cfg_dac2_fall_ms),
        .dac2_rise_ms     (cfg_dac2_rise_ms),
        .pid_enable       (cfg_pid_enable),
        .pid_target_code  (cfg_pid_target_code),
        .pid_window_code  (cfg_pid_window_code),
        .pid_kp           (cfg_pid_kp),
        .pid_ki           (cfg_pid_ki),
        .pid_kd           (cfg_pid_kd),
        .pid_corr_limit   (cfg_pid_corr_limit),
        .last_addr        (cfg_uart_last_addr),
        .update_tick      (cfg_uart_update_tick)
    );

    vio_0 u_vio_control (
        .clk        (clk_logic_sync),
        .probe_out0 (vio_auto_sweep_enable),
        .probe_out1 (vio_auto_sweep_freq_Hz),
        .probe_out2 (vio_kick_final_mV), // existing port/value retained for final voltage
        .probe_out3 (vio_kick_min_mV),
        .probe_out4 (vio_kick_fall_ns),
        .probe_out5 (vio_kick_rise_ns),
        .probe_out6 (vio_sweep_start_mV),
        .probe_out7 (vio_sweep_final_mV),
        .probe_out8 (vio_sweep_trigger_mV),
        .probe_out9 (vio_sweep_scan_us),
        .probe_out10(vio_kick_base_mV),
        .probe_out11(vio_sweep_stop_offset_ns)
    );

    vio_pid u_vio_pid (
        .clk         (clk_logic_sync),
        .probe_in0   (w_pd_adc_sample_corrected),
        .probe_in1   (w_pd_step_found),
        .probe_in2   (w_pid_active),
        .probe_in3   (w_pid_nkt_corr),
        .probe_in4   (w_pid_aom_corr),
        .probe_in5   (w_pid_nkt_data),
        .probe_in6   (w_pid_aom_data),
        .probe_in7   (vio_pid_locked),
        .probe_in8   (w_capture_phase),
        .probe_in9   (w_captured_seen),
        .probe_out0  (vio_pid_feedback_enable),
        .probe_out1  (vio_pid_target_mV),
        .probe_out2  (vio_pid_window_mV),
        .probe_out3  (vio_pid_ki),
        .probe_out4  (vio_pid_kd),
        .probe_out5  (vio_pid_kp),
        .probe_out6  (vio_pid_clear),
        .probe_out7  (vio_pid_confirm_samples),
        .probe_out8  (vio_pid_corr_limit),
        .probe_out9  (vio_pid_start_delay_ns),
        .probe_out10 (vio_pid_require_window)
    );

    dks_power_kicker u_logic (
        .clk            (clk_logic_sync),
        .rst_n          (logic_rst_n),
        .btn_start      (btn_start_level),
        .btn_reset      (btn_reset_level),
        .auto_sweep_enable(vio_auto_sweep_enable),
        .auto_sweep_freq_Hz(vio_auto_sweep_freq_Hz),

        .DAC1_START_VAL (ctrl_sweep_initial_code),
        .NKT_TARGET_VAL (ctrl_dac1_kick_code),
        .NKT_FINAL_VAL  (ctrl_sweep_final_code),
        .NKT_RAMP_DIV   (ctrl_sweep_scan_us),
        .SCAN_STOP_OFFSET_NS(vio_sweep_stop_offset_ns),
        .AOM_INIT_VAL   (ctrl_kick_base_code),
        .AOM_KICK_VAL   (ctrl_kick_min_code),
        .AOM_FULL_VAL   (ctrl_kick_final_code),
        .AOM_DROP_STEP  (ctrl_kick_fall_ns),
        .AOM_RISE_STEP  (ctrl_kick_rise_ns),
        .PID_START_DELAY_NS(vio_pid_start_delay_ns),
        .pid_loop_active(w_pid_active),
        .pid_restart_scan(w_pid_restart_scan),

        .signal_1_nkt   (w_nkt_data),
        .signal_2_aom   (w_aom_data),
        .kick           (w_kick_sig),
        .kick_done      (w_kick_done),
        .kick_fall_done (w_kick_fall_done),
        .scan_stopped   (w_scan_stopped),
        .pid_delay_done (w_pid_delay_done),
        .sequence_start_pulse(w_sequence_start),
        .state_debug    (w_controller_state)
    );

    assign led_kick = w_kick_sig;

    capture_phase_status u_capture_status (
        .clk(clk_logic_sync), .rst_n(logic_rst_n),
        .button_reset(btn_reset_level), .pid_clear(vio_pid_clear),
        .feedback_enable(ctrl_pid_feedback_enable),
        .controller_state(w_controller_state), .sequence_start(w_sequence_start),
        .restart_scan(w_pid_restart_scan), .kick(w_kick_sig),
        .pid_active(w_pid_active), .window_found(w_pd_step_found),
        .window_confirmed(pid_window_confirmed), .phase(w_capture_phase),
        .capture_valid(w_capture_valid), .capture_event(w_capture_event),
        .captured_seen(w_captured_seen), .phase_change(w_phase_change)
    );

    // All probes are in the 25 MHz control domain, including the CDC output
    // sample and its valid tick. Raw high-speed ADC remains on u_ila_adc.
    ila_capture u_ila_capture (
        .clk(clk_logic_sync),
        .probe0(w_capture_phase),
        .probe1(w_controller_state),
        .probe2(w_pd_adc_sample_corrected),
        .probe3(w_pd_adc_sample_tick),
        .probe4(w_pid_nkt_corr),
        .probe5(w_pid_nkt_data),
        .probe6(w_pid_aom_data),
        .probe7(w_pid_active),
        .probe8(w_pd_step_found),
        .probe9(w_capture_valid),
        .probe10(w_kick_sig),
        .probe11(w_pid_delay_done),
        .probe12(w_scan_stopped),
        .probe13(w_pid_restart_scan),
        .probe14(w_sequence_start),
        .probe15(ctrl_pid_target_code),
        .probe16(ctrl_pid_window_code),
        .probe17(w_capture_event),
        .probe18(w_captured_seen),
        .probe19(ctrl_pid_feedback_enable),
        .probe20(vio_pid_require_window),
        .probe21(vio_pid_clear),
        .probe22(w_phase_change)
    );

    pd_pid_feedback u_pd_pid_feedback (
        .clk            (clk_logic_sync),
        .rst_n          (logic_rst_n),
        .pd_sample_tick (w_pd_adc_sample_tick),
        .pd_sample      (w_pd_adc_sample_corrected),
        .step_detect_arm(step_detect_arm),
        .pid_enable_after_step(step_detect_arm & vio_pid_require_window & ~w_pid_restart_scan),
        .pid_force_enable(pid_window_bypass),
        .pid_clear      (btn_reset_level | vio_pid_clear | w_sequence_start),
        .pid_hold       (fast_pid_hold),
        .nkt_pid_enable (ctrl_pid_feedback_enable),
        .nkt_pd_target  (ctrl_pid_target_code),
        .pd_window_code (ctrl_pid_window_code),
        .step_confirm_samples(vio_pid_confirm_samples),
        .nkt_kp         (vio_pid_kp),
        .nkt_ki         (vio_pid_ki),
        .nkt_kd         (vio_pid_kd),
        .nkt_corr_limit (vio_pid_corr_limit),
        .base_nkt       (w_nkt_data),
        .base_aom       (w_aom_data),
        .final_nkt      (w_pid_nkt_data),
        .final_aom      (w_pid_aom_data),
        .step_found     (w_pd_step_found),
        .pid_active     (w_pid_active),
        .feedback_locked(vio_pid_locked),
        .nkt_correction (w_pid_nkt_corr),
        .aom_correction (w_pid_aom_corr)
    );

    top_test u_hardware (
        .clk_p          (sys_clk_p),
        .clk_n          (sys_clk_n),
        .fpga_clk_p     (fpga_clk_p),
        .fpga_clk_n     (fpga_clk_n),
        .adc_clk_p      (adc_clk_p),
        .adc_clk_n      (adc_clk_n),

        .data_in_nkt    (w_pid_nkt_data),
        .data_in_aom    (w_pid_aom_data),
        .adc_data_p1    (adc_data_p1),
        .adc_data_n1    (adc_data_n1),
        .clk_out_sync   (clk_logic_sync),
        .clocks_locked  (clocks_locked),
        .pd_adc_sample  (w_pd_adc_sample),
        .pd_adc_sample_tick(w_pd_adc_sample_tick),

        .dac_data_p      (dac_data_p),
        .dac_data_n      (dac_data_n),
        .dac_frame_p     (dac_frame_p),
        .dac_frame_n     (dac_frame_n),
        .dac_dci_p       (dac_dci_p),
        .dac_dci_n       (dac_dci_n),

        .dac_spi_ce      (dac_spi_ce),
        .adc_spi_ce      (adc_spi_ce),
        .clk_spi_ce      (clk_spi_ce),
        .spi_clk         (spi_clk),
        .spi_io          (spi_io),

        .key1            (key1_rst),
        .key2            (key2_start)
    );
endmodule
