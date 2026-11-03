# external_io_timing_gate — 外部 IO 时序的"未签核"门禁

## 适用场景
FPGA 与高速 ADC/DAC 通过 LVDS DDR 连接，但缺少板级走线延迟差、器件可编程延迟的全条件边界等数据，暂时无法完成外部接口时序签核；同时又需要继续构建、上板调试。

## 方法
本项目实现：`../../src/constraints/` 与 `../../docs/timing_constraints.md`。

1. 外部接口约束写成参数化 Tcl（DDR 两个边沿 × min/max），板级参数放在单独的 profile 文件，模板中的空值明确表示"未知"，**不是 0 ns**。
2. 缺少有效 profile 时，构建正常完成但打印 `ADC_DAC_IO_STATUS=PROVISIONAL_MISSING_BOARD_PROFILE`；加 `--signoff` 时直接失败。
3. 约束通过 `FILE_TYPE=Tcl`、仅实现阶段使用、`PROCESSING_ORDER=LATE` 的约束文件加载，不在普通 XDC 中写 `source`。
4. 约束脚本通过 `get_files` 取得自身目录，而不是 `info script`。
5. 实现后逐位审计 192 项（ADC/DAC 每个数据位 × 两个边沿 × min/max）覆盖情况，写出 CSV。

## 失效条件
- 门禁只保证"不会把未签核说成已签核"，不能替代真实的板级参数与上板眼图测试。
- 内部 WNS 为正不代表外部接口通过，报告中应分别陈述。

## 已验证的效果
本项目内部时序收敛（WNS +0.136 ns），外部接口状态明确为 PROVISIONAL，并以 ILA 与示波器的板级实测补充说明接口工作正常；`test_io_timing_constraints` 测试通过。

## 来源
- Vivado 托管 XDC 解释器不接受 `source` 等任意 Tcl 命令，写在普通 XDC 中的约束会被忽略而不报错。
- 在实现子进程中 `info script` 返回 `.runs/impl_1/` 下的临时脚本路径，导致找不到参数文件。
- 若把空白参数当作 0 ns，时序报告会显示"通过"，造成外部接口已签核的错误印象。
