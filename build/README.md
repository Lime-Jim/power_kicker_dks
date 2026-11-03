# build — 综合与实现结果

构建脚本位于 `../src/`：`recreate_project.tcl`（重建工程）、`build_fast_feedback_v1.tcl`（综合、实现、报告、比特流）、`verify_delivery.tcl`（交付校验）。

- `reports/utilization.rpt`、`timing_summary.rpt`、`drc.rpt`：最终版本（与 `board/bitstream/` 对应）的实现报告。LUT 22.24%，BRAM 37.50%，DSP 2.78%；WNS +0.136 ns，WHS +0.011 ns。
- `reports/cdc.rpt`、`methodology.rpt`：CDC 与方法学检查，跨时钟域结构说明见 `../docs/cdc_review.md`。
- `reports/adc_dac_io_status.txt`：ADC/DAC 外部接口约束状态（PROVISIONAL，见 `../docs/timing_constraints.md`）。
- `reports/recreate/`：工程重建与源码哈希校验记录。
- `logs/`：最终版本构建与布线后校验日志。
