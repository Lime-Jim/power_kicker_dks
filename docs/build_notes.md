# VIO 主用稳定工程

正式入口为本目录的 `power-kicker-fast-feedback-v1.xpr`。器件为 `xcau15p-ffvb676-2-i`，使用 Vivado 2024.1。综合顶层是 `top_power_kicker`；GUI 仿真顶层是自检平台 `tb_control_regression`。

本版清理了旧 COE/WCFG 路径、重复加入的 VIO 生成 HDL、未参与当前设计的旧 IP 引用。旧版工程继续保留；交付目录与旧 Vivado 窗口分离，避免其再次保存旧 XPR。

VIO 是唯一生效的参数源，UART 收包/应答代码保留作后续开发，未接入控制输出。两份保存的实验参数未修改，也未连接或烧写板卡。具体参数、复位边界与 UART 协议见 `PARAMETER_CONTROL.md`。

## 构建与验证

在本目录的 PowerShell 中运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\run_regression.ps1
& 'D:\vivado2024\Vivado\2024.1\bin\vivado.bat' -mode batch -source build_fast_feedback_v1.tcl -log build.log -journal build.jou
```

回归包含5个RTL/器件原语平台和2个Tcl工具测试；需要 Vivado 的 xvlog/xelab/xsim，以及 PATH 中的 tclsh。可用 `-VivadoBin` / `-Tclsh` 指定其他安装位置。本机 Tcl 位于 `D:\anaconda\Library\bin\tclsh.exe`。测试中有故意注入的错误用例，最终必须出现 `REGRESSION=PASS`。

构建先检查输入清单，再综合、布线、导出时序/CDC/DRC/方法学报告，检查锁存器为0且已约束的建立/保持时序通过后生成bitstream。输出位于 `power-kicker-fast-feedback-v1.runs/impl_1/`，交付时另将配套BIT/LTX放入 `bitstream/`。

ADC/DAC约束通过 `constrs_1` 中的 `constraints/load_external_timing.tcl` 加载，属性为TCL、实现阶段启用、LATE。不要将 `source` 写回普通XDC：Vivado会忽略这些非XDC命令。

## 当前外部时序状态

`constraints/board_timing.tcl` 尚缺真实硬件依据；模板空值不代表0 ns。普通构建明确报告 `PROVISIONAL_MISSING_BOARD_PROFILE`，其内部时序通过不代表ADC/DAC外部接口已通过。

取得真实板级延迟差和当前ADC DCO配置的有效最小/最大时序后，按 `TIMING_CONSTRAINTS.md` 填写模板。严格检查命令为：

```powershell
& 'D:\vivado2024\Vivado\2024.1\bin\vivado.bat' -mode batch -source build_fast_feedback_v1.tcl -tclargs --signoff
```

缺参、参数未验证、DDR路径覆盖缺失或负余量会让严格检查失败。测试夹具中的数值只用于验证检查工具，不能复制为板卡依据。CDC残留项和检查范围见 `CDC_REVIEW.md`。

## XPR 恢复

先关闭本工程的GUI窗口，再执行：

```powershell
& 'D:\vivado2024\Vivado\2024.1\bin\vivado.bat' -mode batch -source recreate_project.tcl
```

该脚本备份现有XPR，然后从 `project_template.xml` 恢复工程元数据并重新打开验证；不调用 `create_project -force`，不删除源码目录。恢复方案已经在独立目录校验输入文件SHA256不变。后续增加或更换源文件时，应同步维护 `project_manifest.tcl` 和 `project_template.xml`，避免恢复时丢失新增引用。

详细构建结果和交付哈希见 `STABILIZATION_REPORT.md`、`verification/`、`DELIVERY_SHA256.csv`。
