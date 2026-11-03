# board — 上板文件

- `bitstream/top_power_kicker.bit` / `.ltx`：最终版本比特流与调试探针（含状态码触发的控制域 ILA、ADC 域 ILA、DAC 域 ILA 及两组 VIO）。
- `vio_params/`：实验中保存的 VIO 参数快照，可在 Hardware Manager 的 Tcl Console 中直接 `source` 恢复。

上板步骤见根目录 README 第 4.3 节；实测数据见 `../data/`。
