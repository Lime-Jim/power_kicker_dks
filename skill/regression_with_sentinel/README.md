# regression_with_sentinel — 带哨兵字符串的一键回归仿真

## 适用场景
Vivado 工程有多个自检仿真平台，希望每次修改 RTL 后一条命令全部重跑，并且**不会把没跑完或失败的平台误判为通过**。

## 方法
本项目实现：`../../src/run_regression.ps1` 与 `../../src/tests/`。

1. **每个平台结尾打印哨兵**：全部检查通过后输出 `PASS: <平台名> (N checks)`；任何断言失败输出 `FAIL:`。
2. **启动器只认哨兵**：日志里没有 `PASS: <平台名>`、或出现 `Fatal:` / `FAIL:` 时抛出错误。原因是 xsim 中 `$fatal` 不一定把非零退出码传给启动脚本。
3. **故意注入错误用例**：平台内部故意构造越界参数、错误时序等场景，断言检查能够识别，确保检查本身有效。日志中因此会出现 ERROR 字样，以最终哨兵为准。
4. **硬件 IP 用行为模型替身**：VIO、ILA 等调试 IP 用 `vio_hardware_mocks.sv`、`ila_dac_mock.sv` 替代，使顶层集成平台可以从 VIO 参数一直仿真到 DAC 输出。
5. **纯 Tcl 工具也纳入回归**：VIO 保存/恢复脚本、约束计算脚本用 `tclsh` 测试，同一条命令执行。
6. 每次运行写入带时间戳的目录与 `summary.txt`，最后一行为 `REGRESSION=PASS (N suites)`。

## 使用方法
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_regression.ps1 -VivadoBin 'C:\Xilinx\Vivado\2024.1\bin' -Tclsh 'tclsh.exe'
```
迁移时修改脚本顶部的 `$Tests` 列表与 `$sourceMap`（每个平台需要的 RTL 文件）。

## 失效条件
- 脚本为 Windows PowerShell 编写，Linux 下需改写为 bash，但哨兵判断逻辑可直接沿用。
- 行为模型只模拟 IP 接口行为，不能验证真实硬件 IP 的时序。
- 数字仿真不能证明光路或模拟环路的稳定性。

## 已验证的效果
本项目 9 组平台全部通过，合计约 6.8 万项检查（`tb_dac_regression` 53092 项、`tb_adc_capture_regression` 12463 项、顶层集成 1830 项等），见 `../../sim/`。

## 来源
xsim 中 `$fatal` 不一定把非零退出码传给启动脚本，仅凭退出码判断可能把中途退出的平台当作通过；因此启动脚本改为"只认哨兵字符串"。
