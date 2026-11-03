`timescale 1ns/1ps
module tb_vio_uart_regression;
    localparam integer BIT_CYCLES=25000000/115200;
    reg clk=0, serial_rx=1, reset_button_n=1;
    always #20 clk=~clk;
    wire serial_tx;
    top_power_kicker dut(
        .sys_clk_p(clk), .sys_clk_n(~clk), .fpga_clk_p(1'b0), .fpga_clk_n(1'b1),
        .adc_clk_p(1'b0), .adc_clk_n(1'b1), .adc_data_p1(14'd0), .adc_data_n1(14'd0),
        .key1_rst(reset_button_n), .key2_start(1'b1), .ext_reset(1'b0),
        .uart_rx(serial_rx), .uart_tx(serial_tx));

    task tick(input integer n);
        repeat(n) begin @(posedge clk); #1; end
    endtask
    task send_byte(input [7:0] value);
        @(negedge clk); serial_rx=0;
        repeat(BIT_CYCLES) @(negedge clk);
        for(integer i=0;i<8;i=i+1) begin
            serial_rx=value[i];
            repeat(BIT_CYCLES) @(negedge clk);
        end
        serial_rx=1;
        repeat(BIT_CYCLES) @(negedge clk);
    endtask
    task receive_ack(input [7:0] expected);
        reg [7:0] value;
        @(negedge serial_tx);
        repeat(BIT_CYCLES + BIT_CYCLES/2) @(posedge clk);
        #1;
        for(integer i=0;i<8;i=i+1) begin
            value[i]=serial_tx;
            if(i<7) begin repeat(BIT_CYCLES) @(posedge clk); #1; end
        end
        if(value!==expected) $fatal(1,"ACK address mismatch: %h != %h",value,expected);
        repeat(BIT_CYCLES) @(posedge clk); #1;
        if(serial_tx!==1) $fatal(1,"UART stop bit missing");
    endtask
    task write_shadow(input [7:0] addr,input [31:0] value);
        fork
            begin
                send_byte(8'hA5); send_byte(addr);
                send_byte(value[31:24]); send_byte(value[23:16]);
                send_byte(value[15:8]); send_byte(value[7:0]);
            end
            receive_ack(addr);
        join
        tick(4);
    endtask
    task check_vio_values;
        if(dut.ctrl_sweep_initial_code !== 16'd2184 || dut.w_nkt_data !== 16'd2184)
            $fatal(1,"VIO NKT 100mV must remain authoritative");
        if(dut.ctrl_kick_base_code !== 16'd21844 || dut.w_aom_data !== 16'd21844)
            $fatal(1,"VIO AOM 1000mV must remain authoritative");
        if(dut.ctrl_pid_feedback_enable !== 0 || dut.vio_pid_kp !== 16'd256)
            $fatal(1,"UART changed active PID parameters");
    endtask
    initial begin
        #2;
        tick(5);
        if(dut.logic_rst_n!==0) $fatal(1,"Must remain reset before MMCM locks");
        @(negedge clk); dut.u_hardware.clocks_locked=1;
        tick(270); check_vio_values();
        send_byte(8'h55); // ignored garbage before a valid frame
        write_shadow(8'h00,32'h00007fff);
        if(dut.cfg_dac1_start_code!==16'h7fff) $fatal(1,"Reserved UART write was lost");
        check_vio_values();
        write_shadow(8'h03,32'h00000001);
        if(dut.cfg_dac2_base_code!==1) $fatal(1,"UART AOM shadow write");
        check_vio_values();
        write_shadow(8'h10,32'd1);
        write_shadow(8'h13,32'hffffff00);
        if(dut.cfg_pid_enable!==1 || $signed(dut.cfg_pid_kp)!==-256)
            $fatal(1,"UART PID shadow signed payload");
        check_vio_values();
        write_shadow(8'h02,32'h12345678);
        if(dut.cfg_dac1_scan_ms!==32'h12345678) $fatal(1,"UART 32-bit payload byte order");
        check_vio_values();
        @(negedge clk); reset_button_n=0;
        tick(6);
        if(dut.uart_rst_n!==0 || dut.cfg_pid_enable!==0 || dut.cfg_dac1_scan_ms!==100)
            $fatal(1,"Synchronized button must reset reserved UART registers");
        check_vio_values();
        @(negedge clk); reset_button_n=1;
        tick(6);
        if(dut.uart_rst_n!==1) $fatal(1,"UART reset must release after synchronized button");
        @(negedge clk); dut.u_vio_control.probe_out6=200;
        tick(3);
        if(dut.w_nkt_data!==16'd4368) $fatal(1,"VIO edit must affect idle output");
        // MMCM lock loss reasserts the fixed reset, even with nonzero VIO.
        @(negedge clk); dut.u_hardware.clocks_locked=0;
        #1;
        if(dut.logic_rst_n!==0 || dut.w_nkt_data!==0 || dut.w_aom_data!==0)
            $fatal(1,"Lock-loss reset must assert asynchronously to constant values");
        @(negedge clk); dut.u_hardware.clocks_locked=1;
        tick(10);
        if(dut.logic_rst_n!==0) $fatal(1,"Startup guard bypassed after lock loss");
        tick(260);
        if(dut.w_nkt_data!==16'd4368) $fatal(1,"VIO config not reloaded after reset");
        $display("PASS: tb_vio_uart_regression");
        $finish;
    end
    initial begin #10000000; $fatal(1,"UART/VIO test timeout"); end
endmodule
