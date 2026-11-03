# ADC/DAC 外部时序约束与签核

当前工程缺少 AXAU15 + PZ-FL4322 实际板卡/连接器的走线延迟差及其依据，也没有当前 ADC DCO 延迟设置的全条件有效边界。因此本次交付提供完整的参数化 DDR 约束及失败门禁，**默认状态仍是 PROVISIONAL（外部接口尚未签核）**。内部实现和 bitstream 构建可继续；不能以内部 WNS 为正代替 ADC/DAC 接口时序通过。

## 文件与入口

- `constraints/adc_dac_io_timing.tcl`：计算并施加 ADC/DAC 两个时钟边沿的 min/max 延迟，建立 DAC 转发时钟。
- `constraints/board_timing.tcl.example`：待补齐的板卡参数模板。复制为同目录 `board_timing.tcl` 后填写。空白字段不是 0 ns。
- `kicker.xdc`：只保留引脚、器件属性和输入时钟等原生XDC命令。
- `constraints/load_external_timing.tcl`：作为 `constrs_1` 中 `FILE_TYPE=Tcl`、仅实现使用、`PROCESSING_ORDER=LATE` 的文件，加载时序模型后分组异步时钟。`dac_dci_forwarded` 随其500 MHz源时钟进入同一组。普通GUI实现与批处理使用同一入口。
- `tests/test_io_timing_constraints.tcl`：纯 Tcl 方程、无效输入和 DDR覆盖测试。测试里的数字只是假设数据，不能复制为真实板卡参数。
- `tests/check_constraint_loader_vivado.tcl`：用现有综合检查点、OOC IP及真正的 `read_xdc -unmanaged` / `link_design` 顺序验证约束集入口；不保存XPR或执行布局布线。

可用 `POWER_KICKER_BOARD_TIMING` 环境变量指定另一份板卡参数文件的绝对路径；批处理子进程会继承该变量。参数文件使用 Tcl 字典 `::power_kicker_io::profile`。

Vivado的托管XDC解释器不接受任意 `source/info/file` 命令，所以动态加载必须使用Tcl类型约束文件。该方式由 [AMD UG894 2024.1：Using Tcl Scripts in a Constraints Set](https://docs.amd.com/r/2024.1-English/ug894-vivado-tcl-scripting/Using-Tcl-Scripts-in-a-Constraints-Set) 明确支持。仅实现时加载避免综合读取OOC时钟IP黑盒时尚不存在派生逻辑时钟；板卡I/O的最终优化和分析发生在实现阶段。

约束入口通过 `get_files` 注册记录取得自身目录，而非依赖 `info script`：在实现子进程的延后求值环境中，后者可能返回 `.runs/impl_1/top_power_kicker.tcl`。同一个注册目录用于库和板卡参数定位，已用实际实现加载顺序验证。

## 已核对的芯片条件

AD9643 当前 SPI 表写入 `0x16=0x00`、`0x17=0x85`：DCO未反相，延迟使能且码值5，按寄存器公式为名义600 ps额外延迟。资料给出的基础 DCO 对数据滞后范围为0.4–1.0 ns。不能用名义600 ps代替该可编程延迟在温度、电压、器件差异下的最小/最大保证值。依据：[AD9643 Rev G，第8–9页及32–33页](https://www.analog.com/media/en/technical-documentation/data-sheets/AD9643.pdf#page=8)。

AD9122 当前采用word模式，`0x16=0x00`；数据与DCI同边沿发送是该接口预期用法。普通AD9122 Rev C表13的建立时间 `tS=-0.05 ns`，保持时间 `tH=0.65 ns`，FRAME也必须满足采样窗口。不要混用AD9122-EP数据表中不同的数值。依据：[AD9122 Rev C，第31–32页](https://www.analog.com/media/en/technical-documentation/data-sheets/AD9122.pdf#page=31)。

## 必须提供的参数

所有时间单位为ns。范围必须覆盖全部相关差分通道、板卡、FMC连接器和温度/电压条件。若每线有独立报告，取其联合最坏包络是保守且可用的起点。

| 字段 | 含义/取得方式 |
|---|---|
| `board_revision`、`evidence` | 真实板号/版本；走线或SI报告、测量记录与条件的路径/编号 |
| `adc_data_lead_min_ns/max_ns` | 在ADC引脚处，数据跳变领先其对应采样DCO边沿的正时间；必须包含当前0x85设置实际效果，覆盖上升/下降边沿与全条件 |
| `adc_board_skew_min_ns/max_ns` | ADC→FPGA的数据走线延迟减去DCO走线延迟的最小/最大值 |
| `dac_board_skew_min_ns/max_ns` | FPGA→DAC的数据/FRAME走线延迟减去DCI走线延迟的最小/最大值 |
| `adc_margin_ns`、`dac_margin_ns` | 在上述范围尚未覆盖的相对抖动、占空比误差、测量不确定度及工程裕量的保守单边总和；不得把ADC的模拟孔径抖动直接当作DCO接口抖动 |
| `validated` | 依据检查完成后设置为1；它声明参数已核验，不代表STA已经通过 |

模板同时记录当前寄存器值及4 ns/2 ns时钟周期作为配置指纹。代码拒绝不匹配的配置；将来更改SPI表或时钟时必须一并评审约束。可用值不只是走线长度：还要有层叠传播速度、连接器/转接板影响及其变化范围。不能直接从照片估算并用于签核。

## 方程及边沿选择

令 `S = 数据板延迟 - 转发时钟板延迟`，`M` 为额外单边裕量。脚本给P/N两侧都施加约束，每个接口均包含 rising/falling × min/max；下降沿使用 `-clock_fall -add_delay` 保留上升沿。AMD选项定义见 [UG903：Output Delay](https://docs.amd.com/r/en-US/ug903-vivado-using-constraints/Output-Delay)。

ADC的半周期 `UI_ADC=2 ns`。数据领先采样边沿 `L`，将该跳变改写为相对前一个相反DCO边沿的正延迟：

```text
input_min = UI_ADC - Lmax + Smin - M
input_max = UI_ADC - Lmin + Smax + M
```

脚本要求 `0 < input_min <= input_max < UI_ADC`，让当前IDDRE1采样边沿位于同一个连续数据窗口内。如果越界，应复核DCO配置、捕获相位、PCB或引脚设计，不能用增大周期或false path掩盖。

DAC半周期 `UI_DAC=1 ns`，数据和DCI由同一个时钟边沿的ODDRE1发出。新数据必须在该DCI边沿的 `-tS` 之前有效，且下一次跳变必须在 `tH` 之后；只填普通 `tS/-tH` 会让默认DDR STA多给新数据一个UI。脚本将两项延迟同时重基准到下一相反边沿，保持默认DDR检查，无需切掉任何I/O路径：

```text
output_max = UI_DAC + tS + Smax + M
output_min = UI_DAC - tH + Smin - M
```

作为方程校验，假设板延迟差和裕量全为0时，FPGA端数据相对DCI允许的跳变偏移为 `-0.35 ns <= Tdata-Tdci <= +0.05 ns`。这个假设只解释方程，不是已知板卡参数。它也说明现有同边沿输出的建立裕量可能很紧，后续真实STA若失败，可能需要IO延迟/相位设计改动。

`dac_dci_forwarded` 从实际源端口 `fpga_clk_p` 沿缓冲、ODDR及输出缓冲路径推导至 `dac_dci_p`，避免ODDRE1实现阶段展开造成的层次名变化；FPGA内部时钟/输出缓冲/布线延迟由Vivado计入，板卡参数不要把这些再算一遍。FRAME与16位DAC数据都被约束。3个异步域之间的CDC仍需单独检查；SPI/UART/按键等低速接口不属于这份ADC/DAC签核模型。

## 门禁与验证流程

在Vivado或普通Tcl中，以下调用验证参数完整性和配置，缺失时抛出错误，可用于自动化签核构建的前置门禁：

```tcl
source constraints/adc_dac_io_timing.tcl
::power_kicker_io::require_validated_profile
```

普通实现加载约束集时，缺少有效参数会明确输出 `POWER_KICKER_IO_TIMING=PROVISIONAL_*`；仅生成真实DCI转发时钟，保留外部路径未约束的事实。完整参数生效后状态为 `CONSTRAINED_AWAITING_STA`，不是PASS。

实现完成后调用 `::power_kicker_io::audit_routed_profile $report_dir $require_signoff`，检查已经施加在实现中的约束，不会事后重施约束。它逐位检查ADC的两个外部发射边沿、DAC/FRAME的两个采样边沿，各自的min/max延迟、slack与DAC边沿关系，产生192项覆盖CSV及详细报告；真实参数缺失时只写明确的PROVISIONAL状态。`require_signoff=1`时缺参数、缺路径、约束与参数不一致或负slack均导致失败。

补齐依据后，重置综合与实现，检查：

1. profile门禁通过，构建记录含板卡版本、参数和依据；SPI读回与配置指纹一致。
2. 对全部ADC输入、DAC数据/FRAME输出分别生成 min/max 完整时钟展开报告，两个DDR边沿均有路径。DAC的默认相反边沿检查应有1 ns关系，输出max/min已包含上述一个UI重基准；不要再次加入0周期multicycle。
3. ADC/DAC相关端点无missing input/output delay，建立/保持均无负slack，CDC报告中的跨域路径有明确结构解释。其余未约束端口单独处理，不能把本门禁叫作全芯片时序签核。
4. 使用ADC测试码/PN序列和DAC SED或适当的上板码型验证实际窗口，在目标温度、电压条件下记录结果。RTL仿真只验证数字功能，不能替代模拟采样眼图及真实板卡验证。

当前缺少的硬件资料限制第1步及之后的最终签核；不会阻止工程清理、复位重构或数字回归仿真继续执行。
