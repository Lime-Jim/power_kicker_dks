`timescale 1ns / 1ps

module tb_dks_power_kicker();

    reg clk;
    reg rst_n;
    reg btn_start;
    reg btn_reset;

    wire [15:0] signal_1_nkt;
    wire [15:0] signal_2_aom;
    wire        kick;
    wire        kick_done;

    dks_power_kicker #(
        .CLK_HZ(1_000_000)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .btn_start(btn_start),
        .btn_reset(btn_reset),
        .DAC1_START_VAL(16'd0),
        .NKT_TARGET_VAL(16'd50),
        .NKT_FINAL_VAL(16'd64),
        .NKT_RAMP_DIV(32'd1),
        .AOM_INIT_VAL(16'd26000),
        .AOM_KICK_VAL(16'd13000),
        .AOM_FULL_VAL(16'd26000),
        .AOM_DROP_STEP(16'd1),
        .AOM_RISE_STEP(16'd1),
        .signal_1_nkt(signal_1_nkt),
        .signal_2_aom(signal_2_aom),
        .kick(kick),
        .kick_done(kick_done),
        .state_debug()
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end

    initial begin
        // 上电
        rst_n = 0; btn_start = 0; btn_reset = 0;
        #100; rst_n = 1; #50;

        // 【第一次循环】
        @(posedge clk); btn_start = 1; @(posedge clk); btn_start = 0;

        // 等待整个流程走完并进入稳态。
        // 你在波形里会看到，即使等再久(#5000)，信号也不会掉下来！
        #5000; 

        // 只有按下 reset，才会复位回一开始的样子
        @(posedge clk); btn_reset = 1; @(posedge clk); btn_reset = 0;
        #500; 

        // 【重来：第二次循环】
        @(posedge clk); btn_start = 1; @(posedge clk); btn_start = 0;
        #5000; 

        // 再次复位
        @(posedge clk); btn_reset = 1; @(posedge clk); btn_reset = 0;
        #500;

        $finish;
    end

endmodule
