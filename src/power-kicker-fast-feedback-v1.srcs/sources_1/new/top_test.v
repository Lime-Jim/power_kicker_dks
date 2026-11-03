`timescale 1ns / 1ps

module top_test(
    input  wire        clk_p,
    input  wire        clk_n,
    input  wire        fpga_clk_p,
    input  wire        fpga_clk_n,
    input  wire        adc_clk_p,
    input  wire        adc_clk_n,

    input  wire [15:0] data_in_nkt,
    input  wire [15:0] data_in_aom,
    input  wire [13:0] adc_data_p1,
    input  wire [13:0] adc_data_n1,

    output wire        clk_out_sync,
    output wire        clocks_locked,
    output wire signed [15:0] pd_adc_sample,
    output wire        pd_adc_sample_tick,
    output wire        dac_frame_p,
    output wire        dac_frame_n,
    output wire        dac_dci_p,
    output wire        dac_dci_n,
    output wire [15:0] dac_data_p,
    output wire [15:0] dac_data_n,

    input  wire        key1,
    input  wire        key2,

    output wire        dac_spi_ce,
    output wire        adc_spi_ce,
    output wire        clk_spi_ce,
    output wire        spi_clk,
    inout  wire        spi_io
);

    wire clk_25m;
    wire locked;
    assign clk_out_sync = clk_25m;
    assign clocks_locked = locked;

    wire [9:0]  adc_lut_index;
    wire [24:0] adc_lut_data;
    wire [9:0]  dac_lut_index;
    wire [15:0] dac_lut_data;
    wire [9:0]  clk_lut_index;
    wire [24:0] clk_lut_data;
    wire        done_flag;
    wire        adc_clk;
    wire [13:0] adc_data_a;
    wire [13:0] adc_data_b;
    wire signed [15:0] pd_adc_debug;

    clk_wiz_1 clk_md (
        .clk_out1  (clk_25m),
        .resetn    (1'b1),
        .locked    (locked),
        .clk_in1_p (clk_p),
        .clk_in1_n (clk_n)
    );

    ad9643_config u_adc_cfg (
        .lut_index (adc_lut_index),
        .lut_data  (adc_lut_data)
    );

    ad9122_config u_dac_cfg (
        .lut_index (dac_lut_index),
        .lut_data  (dac_lut_data)
    );

    ad9516_config u_clk_cfg (
        .lut_index (clk_lut_index),
        .lut_data  (clk_lut_data)
    );

    spi_config_top u_spi_cfg (
        .clk_50m        (clk_25m),
        .locked         (locked),
        .spi_clk        (spi_clk),
        .spi_io         (spi_io),
        .clk_spi_ce     (clk_spi_ce),
        .adc_spi_ce     (adc_spi_ce),
        .dac_spi_ce     (dac_spi_ce),
        .adc_lut_index  (adc_lut_index),
        .adc_lut_data   (adc_lut_data),
        .dac_lut_index  (dac_lut_index),
        .dac_lut_data   (dac_lut_data),
        .clk_lut_index  (clk_lut_index),
        .clk_lut_data   (clk_lut_data),
        .done_flag      (done_flag)
    );

    test_ad9643 u_adc_phy (
        .adc_clk_p      (adc_clk_p),
        .adc_clk_n      (adc_clk_n),
        .adc_clk_oeb    (),
        .adc_clk_pwn    (),
        .adc_clk        (adc_clk),
        .adc_data_a_out (adc_data_a),
        .adc_data_b_out (adc_data_b),
        .adc_data_p     (adc_data_p1),
        .adc_data_n     (adc_data_n1)
    );

    pd_adc_capture #(
        .AVG_BITS       (7),
        .ADC_LEFT_SHIFT (2)
    ) u_pd_capture (
        .adc_clk        (adc_clk),
        .logic_clk      (clk_25m),
        .rst_n          (locked),
        .adc_raw        (adc_data_b),
        .pd_sample      (pd_adc_sample),
        .pd_sample_tick (pd_adc_sample_tick),
        .pd_adc_debug   (pd_adc_debug)
    );

    // Capture only ADC-domain registers here; the 25 MHz feedback sample/tick
    // must not be probed asynchronously with the ADC clock.
    ila_adc u_ila_adc (
        .clk    (adc_clk),
        .probe0 (adc_data_a),
        .probe1 (adc_data_b),
        .probe2 (pd_adc_debug)
    );

    test_ad9122 u_dac_phy (
        .clk_25m        (clk_25m),
        .fpga_clk_p     (fpga_clk_p),
        .fpga_clk_n     (fpga_clk_n),
        .ext_nkt_data   (data_in_nkt),
        .ext_aom_data   (data_in_aom),
        .dac_frame_p    (dac_frame_p),
        .dac_frame_n    (dac_frame_n),
        .dac_dci_p      (dac_dci_p),
        .dac_dci_n      (dac_dci_n),
        .dac_data_p     (dac_data_p),
        .dac_data_n     (dac_data_n),
        .key1           (key1),
        .key2           (key2),
        .done_flag      (done_flag)
    );
endmodule
