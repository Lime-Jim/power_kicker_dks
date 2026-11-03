# sim — 回归仿真结果

仿真平台源码位于 `../src/tests/`（Vivado 脚本使用相对路径，因此保留在工程目录内），运行方法见根目录 README 第 4.1 节。

| 平台 | 验证内容 | 结果 |
|---|---|---|
| tb_control_regression | 复位、参数快照、扫描与 kick、时间量化、自动回扫 | 66 项 PASS |
| tb_feedback_regression | P/I/D 运算、限幅、窗口确认、冻结与清除 | 69 项 PASS |
| tb_adc_capture_regression | 250/25 MHz 抽取、符号扩展、跨域与复位 | 12463 项 PASS |
| tb_dac_regression | DDR 原语、跨域、双通道一致、FRAME | 53092 项 PASS |
| tb_pid_delay_regression | PID 启动延时、使能条件、顶层集成 | 1830 项 PASS |
| tb_capture_phase_regression | 四阶段状态码 | 25 项 PASS |
| tb_vio_uart_regression | 串口收发、VIO 隔离、按键与失锁复位 | PASS |
| test_vio_helpers | VIO 参数保存 / 恢复 | 50 项 PASS |
| test_io_timing_constraints | ADC/DAC 接口约束检查 | PASS |

`logs/` 为全量回归日志；`logs/capture_state/` 为最终版本（与 `board/bitstream` 对应）修改后重新运行的相关平台日志及汇总。
