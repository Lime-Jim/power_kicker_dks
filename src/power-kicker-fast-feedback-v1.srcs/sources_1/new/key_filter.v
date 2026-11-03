// 简单的按键消抖模块
module key_filter #(
    parameter CLK_FREQ = 500_000_000 // 默认时钟 500MHz
)(
    input  clk,
    input  rst_n,
    input  key_in,      // 物理按键输入 (低有效)
    output reg key_out, // 消抖后的电平
    output key_pulse    // 按下瞬间的一个脉冲 (高有效)
);

    // 20ms 消抖时间: 500MHz * 0.02s = 10,000,000
    localparam CNT_MAX = CLK_FREQ / 50; 
    
    reg [23:0] cnt;
    reg key_r0, key_r1, key_r2; // 同步寄存器

    // 1. 跨时钟域同步 (打两拍防止亚稳态)
    always @(posedge clk) begin
        key_r0 <= key_in;
        key_r1 <= key_r0;
    end

    // 2. 消抖计数
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            cnt <= 0;
            key_r2 <= 1;
            key_out <= 1;
        end else begin
            // 状态变化检测
            if(key_r1 != key_r2) begin
                cnt <= CNT_MAX; // 重置计数器
                key_r2 <= key_r1;
            end else begin
                if(cnt > 0) 
                    cnt <= cnt - 1;
                else 
                    key_out <= key_r2; // 计数倒数结束，确认状态
            end
        end
    end

    // 3. 产生下降沿脉冲 (即按下瞬间)
    reg key_out_d;
    always @(posedge clk) key_out_d <= key_out;
    
    // key_out 从 1 变 0 时产生脉冲
    assign key_pulse = (~key_out) & key_out_d;

endmodule