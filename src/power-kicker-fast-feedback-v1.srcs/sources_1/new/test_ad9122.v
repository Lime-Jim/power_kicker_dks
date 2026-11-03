`timescale 1ns / 1ps

module test_ad9122(
    input  wire        clk_25m,
    input  wire        fpga_clk_p,
    input  wire        fpga_clk_n,

    input  wire [15:0] ext_nkt_data,
    input  wire [15:0] ext_aom_data,

    input  wire        key1,
    input  wire        key2,
    input  wire        done_flag,

    output wire        dac_frame_p,
    output wire        dac_frame_n,
    output wire        dac_dci_p,
    output wire        dac_dci_n,
    output wire [15:0] dac_data_p,
    output wire [15:0] dac_data_n
);

    reg [7:0] rst_cnt = 8'd0;
    reg       sys_rst_n = 1'b0;

    always @(posedge clk_25m) begin
        if (rst_cnt < 8'hff) begin
            rst_cnt   <= rst_cnt + 1'b1;
            sys_rst_n <= 1'b0;
        end else begin
            sys_rst_n <= 1'b1;
        end
    end

    wire clk_dco;
    wire clk_dco_buf;

    IBUFDS u_dac_clk_ibuf (
        .O  (clk_dco_buf),
        .I  (fpga_clk_p),
        .IB (fpga_clk_n)
    );

    BUFG u_dac_clk_bufg (
        .I (clk_dco_buf),
        .O (clk_dco)
    );

    wire key1_pulse;
    wire key2_pulse;

    key_filter #(.CLK_FREQ(500_000_000)) u_key1_dbg (
        .clk       (clk_dco),
        .rst_n     (sys_rst_n),
        .key_in    (key1),
        .key_out   (),
        .key_pulse (key1_pulse)
    );

    key_filter #(.CLK_FREQ(500_000_000)) u_key2_dbg (
        .clk       (clk_dco),
        .rst_n     (sys_rst_n),
        .key_in    (key2),
        .key_out   (),
        .key_pulse (key2_pulse)
    );

    (* ASYNC_REG = "TRUE" *) reg [2:0] done_sync = 3'b000;
    reg done_seen = 1'b0;
    reg [4:0] frame_cnt = 5'd0;

    always @(posedge clk_dco) begin
        done_sync <= {done_sync[1:0], done_flag};
        done_seen <= done_sync[2];

        if (done_sync[2] && !done_seen) begin
            frame_cnt <= 5'd16;
        end else if (frame_cnt != 5'd0) begin
            frame_cnt <= frame_cnt - 1'b1;
        end
    end

    wire done_ok = done_sync[2];
    wire dac_frame_i = (frame_cnt != 5'd0);
    wire dac_frame_ddr;
    wire dac_dci_ddr;

    ODDRE1 #(.SIM_DEVICE("ULTRASCALE_PLUS")) u_dac_frame_oddr (
        .Q  (dac_frame_ddr),
        .C  (clk_dco),
        .D1 (dac_frame_i),
        .D2 (dac_frame_i),
        .SR (1'b0)
    );

    OBUFDS #(.IOSTANDARD("LVDS")) u_dac_frame_obuf (
        .O  (dac_frame_p),
        .OB (dac_frame_n),
        .I  (dac_frame_ddr)
    );

    ODDRE1 #(.SIM_DEVICE("ULTRASCALE_PLUS")) u_dac_dci_oddr (
        .Q  (dac_dci_ddr),
        .C  (clk_dco),
        .D1 (1'b1),
        .D2 (1'b0),
        .SR (1'b0)
    );

    OBUFDS #(.IOSTANDARD("LVDS")) u_dac_dci_obuf (
        .O  (dac_dci_p),
        .OB (dac_dci_n),
        .I  (dac_dci_ddr)
    );

    reg [31:0] data_pair_25m = 32'd0;
    reg        data_req_25m  = 1'b0;

    always @(posedge clk_25m) begin
        if (!sys_rst_n) begin
            data_pair_25m <= 32'd0;
            data_req_25m  <= 1'b0;
        end else if (data_pair_25m != {ext_nkt_data, ext_aom_data}) begin
            data_pair_25m <= {ext_nkt_data, ext_aom_data};
            data_req_25m  <= ~data_req_25m;
        end
    end

    (* ASYNC_REG = "TRUE" *) reg [2:0] data_req_sync = 3'b000;
    reg        data_req_seen = 1'b0;
    reg [2:0]  data_load_wait = 3'd0;
    reg [15:0] nkt_data_dac = 16'd0;
    reg [15:0] aom_data_dac = 16'd0;

    always @(posedge clk_dco) begin
        data_req_sync <= {data_req_sync[1:0], data_req_25m};

        if (data_req_sync[2] != data_req_seen) begin
            data_req_seen  <= data_req_sync[2];
            data_load_wait <= 3'd4;
        end else if (data_load_wait != 3'd0) begin
            data_load_wait <= data_load_wait - 1'b1;
            if (data_load_wait == 3'd1) begin
                nkt_data_dac <= data_pair_25m[31:16];
                aom_data_dac <= data_pair_25m[15:0];
            end
        end
    end

    localparam DAC_SWAP_NKT_AOM = 1'b0;
    wire [15:0] dac_d1_data = DAC_SWAP_NKT_AOM ? aom_data_dac : nkt_data_dac;
    wire [15:0] dac_d2_data = DAC_SWAP_NKT_AOM ? nkt_data_dac : aom_data_dac;

    wire [15:0] dac_data_ddr;

    genvar pin_count;
    generate
        for (pin_count = 0; pin_count < 16; pin_count = pin_count + 1) begin : gen_dac_data
            ODDRE1 #(.SIM_DEVICE("ULTRASCALE_PLUS")) u_dac_data_oddr (
                .Q  (dac_data_ddr[pin_count]),
                .C  (clk_dco),
                .D1 (dac_d1_data[pin_count]),
                .D2 (dac_d2_data[pin_count]),
                .SR (1'b0)
            );

            OBUFDS #(.IOSTANDARD("LVDS")) u_dac_data_obuf (
                .O  (dac_data_p[pin_count]),
                .OB (dac_data_n[pin_count]),
                .I  (dac_data_ddr[pin_count])
            );
        end
    endgenerate

    ila_1 u_ila_dac (
        .clk    (clk_dco),
        .probe0 (nkt_data_dac),
        .probe1 (aom_data_dac),
        .probe2 ({dac_d1_data, dac_d2_data}),
        .probe3 ({3'b0, frame_cnt, data_load_wait, key1_pulse, key2_pulse, data_req_sync[2], data_req_seen, done_ok})
    );

endmodule
