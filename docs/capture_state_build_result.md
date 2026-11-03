# 流程状态机与控制域ILA构建记录（2026-09-21）

目标工程：`D:/power-kicking_handoff_20260907/code/vio_stable`。使用Vivado 2024.1，器件 `xcau15p-ffvb676-2-i`。详细使用方法见 `CAPTURE_STATE_ILA_GUIDE.md`。

## 本次变更

- 新增只读同步流程状态机：0=空闲，1=扫描/重扫，2=捕获中，3=确认捕获并进行PID反馈。既有波形控制器、PID增益和失锁恢复算法未改动。
- kick之后即使扫描继续也显示捕获中，通过独立的scan_stopped探针辨别重叠。绕过PID启动入窗门控时，只有真正连续入窗且PID运行才显示3。
- 新增成功事件脉冲、状态变化脉冲、当前捕获有效信号及跨重扫保留的成功历史标志。
- PID VIO新增输入8（2位阶段）、输入9（1位成功历史）；既有输入0～7及输出参数保持原端口顺序。
- 新增25 MHz控制域ILA `u_ila_capture`，23个探针、8192点、输入流水线1级；包含状态、PD有效采样、修正、DAC码和门控/事件信号。保留ADC及DAC ILA。
- 更新工程、IP清单和恢复模板；新增读取与CSV导出工具、专项回归及调试映射检查脚本。
- 构建流程新增布线后的aggressive_hold_fix检查及再布线，检查新增ILA内部比较器的极短保持路径；不放宽原时序约束。通过完整检查后保存最终routed DCP，再生成BIT。本次物理优化在其分析结果中判断无需额外插入延迟，完成再布线和检查点保存后又独立复查。

## 验证结果

- 完整9组回归通过：control、feedback、adc_capture、vio_uart、pid_delay、dac、capture_phase，以及IO约束/VIO参数两组Tcl回归。日志目录 `verification/sim_20260921_133820`。
- 新状态机专项25项检查；顶层PID/捕获/失锁流程集成1830项检查。覆盖重复成功/失锁、扫描与捕获重叠、绕过模式窗外纠偏、clear/复位、关闭反馈、无kick及自动回扫。
- 综合0 Error、0 Critical Warning。最终建立时间余量+0.136 ns，保持时间余量+0.011 ns，0锁存器。默认DRC 58条Warning、无Error/Critical Warning，明细随报告交付。
- BIT最终状态为 `write_bitstream Complete!`。独立打开用于BIT生成的最终检查点，在生成报告前后分别查询最差10条setup/hold路径，均通过且余量一致（`FRESH_CHECKPOINT=PASS`）。初次构建的负余量查询记录保留在initial日志中，不能与最终报告混用。
- LTX映射及IP配置核对通过：23个控制域ILA探针、VIO阶段2位/历史1位、ADC/DAC ILA保留。ILA中与VIO共用的探针显示名有 `_1` 后缀，读取指南已注明。
- Block RAM使用54/144（37.5%）。最终构建状态、锁存器数及调试映射核对记录随交付日志保存。
- Tcl读取工具通过离线source检查；尚未连接真实板卡验证JTAG抓取或采集真实PD波形。

板级外部ADC/DAC时序配置仍缺失，状态为 `PROVISIONAL_MISSING_BOARD_PROFILE`，内部时序通过不能代替完整板级I/O签核。程序中的“确认捕获”采用既有PD连续入窗判据，并未新增光学锁定检测或采样超时检测。

## 交付

同目录配套文件：`bitstream/capture_state_20260921/top_power_kicker.bit` 与 `top_power_kicker.ltx`，标准 `.runs/impl_1` 位置也同步更新。读取新增ILA/VIO必须使用本次配套BIT/LTX。

交付前核对原文件哈希并备份到 `.codex_backup_capture_state_<时间>`，复制后逐文件校验。当前保存的VIO参数文件不在替换清单中。清单及证据放在 `verification/capture_state_20260921`。

本次未自动下载到板卡。使用前重新打开更新后的工程，再选择配套BIT/LTX。以下为最终文件及检查记录：
- top_power_kicker.bit SHA256: 840F60FE2F8EACBF6D43151821EBAEC38C7CBF6E8D8C979A8B7E5312864396E7
- top_power_kicker.ltx SHA256: F6E52EE7E0F6338CEAC8E46FB8884F8EE15E938C196DE808FCE3E13FFB17A312
