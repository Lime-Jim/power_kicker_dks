# vio_param_save_restore — VIO 参数保存与恢复

## 适用场景
板级实验中用 Vivado VIO 在线调整十几个以上的参数，需要：重新下载比特流后一键恢复上次参数；把某次实验的参数存档、写进报告；避免手动逐个输入出错。

## 使用方法
本项目实现位于 `../../src/open_vio_with_last_parameters.tcl`（主体）和 `../../src/load_vio_autosave_tools_only.tcl`（只加载命令、不自动连接硬件）。在 Hardware Manager 的 Tcl Console 中：

```tcl
source load_vio_autosave_tools_only.tcl
pk_program_device                 ;# 可选：下载默认 BIT/LTX
pk_restore_last_vio_parameters    ;# 恢复上次保存的参数
pk_save_current_vio_parameters    ;# 把当前 VIO 输出保存到文件
pk_list_vio_probes                ;# 列出全部探针与当前值
pk_autosave_status                ;# 查看保存文件位置与时间
```

保存的文件是纯数据（不含硬件写操作），格式见 `../../board/vio_params/`：

```tcl
set saved_control_values {vio_kick_base_mV 535 vio_kick_min_mV 280 ...}
set saved_pid_values     {vio_pid_kp 256 vio_pid_ki 8 ...}
```

迁移到其他工程时，修改脚本中的 VIO 单元名、探针名列表和有符号探针列表即可。

## 关键设计点
- **按名称而不是按序号恢复**：探针顺序变化时不会写错位置；缺少的探针给出警告而不是写入其他探针。
- **有符号探针归一化**：保存时统一写十进制有符号值，恢复时同时接受旧存档中的无符号补码（如 16 位的 65535 视为 −1）。
- **比特流不匹配检测**：若期望的探针不存在，提示"BIT 与 LTX 不匹配或版本过旧"，而不是静默跳过。
- **纯 Tcl 测试**：`../../src/tests/test_vio_helpers.tcl` 用内存桩替代 Hardware Manager，不连接硬件即可回归测试。

## 失效条件
- 只保存 VIO 输出探针，不保存 ILA 触发设置或 Hardware Manager 界面布局。
- VIO 探针位宽小于 RTL 实际使用位宽或反之时，恢复写入的值会被截断，需在 RTL 与 IP 两侧保持位宽一致（见 `pitfalls.md`）。

## 已验证的效果
`test_vio_helpers` 50 项检查全部通过（有符号/补码兼容、进制解析、探针保护、错误处理）；实验中多次重新下载比特流后用一条命令恢复全部 23 个参数。

## 来源
工程稳定化过程中修复了两类问题（见 `../../docs/stabilization_report.md`）：有符号探针在无符号显示进制下保存，恢复后变成 65535 一类的补码值；设置确认次数的辅助脚本可能误改控制 VIO 的 probe_out7。修复后形成了上述"按名称、归一化、强校验"的规则。
