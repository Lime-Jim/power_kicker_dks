# 工程稳定化交付记录 — 2026-09-08

交付位置：`D:\power-kicking_handoff_20260907\code\vio_stable`。旧GUI未确认关闭，因此采用独立工程目录交付，原 `code/fast_feedback_v1_1us` 不覆盖。本次没有板卡下载，也没有更改两份已保存的VIO实验参数。

## 已完成修改

- XPR仅保留4个活动IP：clk_wiz_1、ila_1、vio_0、vio_pid。清除旧COE/WCFG、重复生成HDL和不参与当前设计的IP引用；原有遗留文件保留在磁盘，不参与构建。
- 状态机异步复位只使用常量，VIO配置改为时钟沿装载；启动/按钮复位捕获波形快照，运行中保持既有波形参数。逻辑和ADC复位按时钟域同步释放；UART复位使用寄存器，避免组合复位直接驱动UART复位网络。
- VIO是唯一参数来源；UART独立为 `uart_power_kick_params.v` 并保持旧协议备用，未加入源切换。VIO工具修复有符号参数显示/保存/恢复与旧无符号补码兼容，防止确认次数脚本误改控制VIO的probe_out7。
- 固定GUI仿真顶层，增加5个自检仿真平台和2组Tcl工具测试。
- ADC/DAC双沿时序模型、配置模板、严格检查和192项实现后边沿覆盖审计已提供。时序入口使用实现阶段LATE的TCL约束，并用实际注册文件路径定位辅助脚本。
- 提供可重现的源文件清单和XPR元数据恢复模板；恢复操作经独立目录SHA256验证，不删除源码。

## 最终构建结果

最终综合、实现、BIT生成均完成，已约束路径时序通过：

| 项目 | 最终结果 |
|---|---:|
| WNS / TNS | +0.142 ns / 0 |
| WHS / THS | +0.019 ns / 0 |
| 锁存器 | 0 |
| DRC | 0错误、39警告（原178警告） |
| 方法学 | 106警告（原558项） |
| LUTAR-1 | 5项，均在厂商debug_hub（原285项） |
| TIMING-20 / LATCH-1 | 不再出现 |
| LUT / FF | 11452 / 5039，14.73% / 3.24% |
| BRAM / DSP | 18 / 11，12.50% / 1.91% |

最后实现过程没有严重警告或错误。CDC报告另外保留4项调试按键复位的Critical，不能把DRC零错误等同于所有CDC项目均已关闭。

最终工程使用Vivado 2024.1。顶层综合已对全部最终RTL重新执行；最后一次实现复用经 `NEEDS_REFRESH=false` 检查的同一份完整综合网表，应用修正后的Tcl约束加载方式。详见 `build_stabilized_final_20260908.log` 与 `verification/implementation/`。

## 自动验证

| 测试 | 验证范围 | 结果 |
|---|---|---|
| tb_control_regression | 停钟复位、配置快照、扫描与踢动、时间量化、自动回程 | 66项检查通过 |
| tb_feedback_regression | PID P/I/D、限幅、窗口确认、冻结与清除、NKT单通道修正 | 69项检查通过 |
| tb_adc_capture_regression | 250/25 MHz、512 ns原始抽取、符号转换、跨域与复位 | 12463项检查通过 |
| tb_vio_uart_regression | 真正串行收发、32位载荷、VIO隔离、按钮/失锁复位 | 通过 |
| tb_dac_regression | 真实UNISIM DDR、连续跨域、通道与差分、FRAME | 53092项检查，67对数据、2次FRAME通过 |
| test_vio_helpers | 有符号/补码兼容、进制解析、探针保护、错误处理 | 50项检查通过 |
| test_io_timing_constraints | 方程、参数核验、缺参拒绝签核、DDR覆盖 | 通过 |

另在Vivado实际实现加载流程中验证了TCL入口和转发时钟；独立元数据恢复和重开测试确认输入哈希不变。仿真不能验证亚稳态概率、真实PCB信号完整性或模拟闭环稳定性。

## 尚未完成的硬件签核

当前 `ADC_DAC_IO_STATUS=PROVISIONAL_MISSING_BOARD_PROFILE`。需要实际板卡数据线相对ADC DCO、DAC DCI的最小/最大走线延迟差，以及AD9643当前0x17=0x85设置下有效DCO延迟边界和抖动/裕量依据。没有用0 ns或测试夹具替代这些数据。

因此普通内部构建可生成BIT，但外部接口签核仍待硬件资料；`--signoff`会明确拒绝缺参构建。条件齐备后还必须通过逐位DDR建立/保持检查，不能只检查内部WNS。

CDC残留项详见 `CDC_REVIEW.md`。当前调试按键跨域复位、保持数据+toggle结构的物理路径预算仍需评审；DAC停钟保持旧值的板级联锁不在此次修改中。

## 交付文件校验

`top_power_kicker.bit`：3170710字节，2026-09-08 11:52生成。

```text
SHA256 6290175F600C2ECC41E5093DD9DE799C0247B2E188AEAB277E99CFC7E646FDCF
```

配套 `top_power_kicker.ltx`：109813字节。

```text
SHA256 69A0325F18B4EC5A3F4022D9E1534082D147F9C20C9CA57CE2DA76B061582D99
```

全部交付文件另有 `DELIVERY_SHA256.csv`。工程源文件、约束、测试、结果和配套BIT/LTX均在同一交付目录中；打开工程后Vivado可正常重新生成缓存。
