# power_kicker_dks — 基于 FPGA 的程控光频梳激发系统

Programmable soliton-microcomb excitation, step detection, PID servo and automatic relock on an AMD Artix UltraScale+ FPGA.

本工程在 FPGA 中统一完成微腔耗散克尔孤子（DKS）光频梳的激光扫描、AOM power kicking、功率台阶识别、Q8 定点 PID 伺服和失锁自动重扫，扫描、kick 与反馈启动由同一 25 MHz 时钟控制，失锁后 120 ns 内重新开始扫描。进入 PID 伺服后孤子台阶可稳定保持 ≥ 24 h。

## 1. 平台信息 / Platform

| 项目 | 型号 / 版本 |
|---|---|
| FPGA 器件 | AMD Artix UltraScale+ `xcau15p-ffvb676-2-i` |
| 高速子卡 | JL-FM2AD0250C（AD9643 14 bit / 250 MSPS ADC，AD9122 16 bit 双通道 DAC，AD9516 时钟） |
| 开发工具 | **Vivado 2024.1**（选题指南推荐 2026.1 / 2025.2；本工程使用 2024.1，已提供脚本化重建流程，见第 4 节） |
| 综合顶层 | `top_power_kicker` |
| 仿真 | Vivado xsim（`xvlog` / `xelab` / `xsim`）+ `tclsh` |
| 光学平台 | Si₃N₄ 微环（FSR ≈ 106 GHz），NKT 泵浦激光器，EDFA，AOM，两路光电探测器，Siglent SDS5104X 示波器 |

## 2. 目录结构 / Repository layout

```
power_kicker_dks/
├── README.md           本文件：简介 + 复现步骤
├── LICENSE             MIT
├── src/                Vivado 工程根目录（设计源码 + IP + 约束 + 构建/调试脚本）
│   ├── power-kicker-fast-feedback-v1.srcs/
│   │   ├── sources_1/new/   RTL 源码（*.v）
│   │   ├── sources_1/ip/    IP：clk_wiz_1、ila_1、ila_adc、ila_capture、vio_0、vio_pid
│   │   ├── constrs_1/new/   kicker.xdc
│   │   └── sim_1/new/       tb_control.v
│   ├── constraints/        ADC/DAC 外部接口时序约束（Tcl，实现阶段加载）
│   ├── tests/              9 组自检仿真平台与 Tcl 测试
│   ├── power-kicker-fast-feedback-v1.xpr / project_template.xml / project_manifest.tcl
│   ├── recreate_project.tcl / build_fast_feedback_v1.tcl / verify_delivery.tcl
│   ├── run_regression.ps1  一键回归仿真
│   └── *_vio*.tcl, *_ila*.tcl  上板 VIO 参数与 ILA 采集工具
├── sim/                回归仿真结果（logs/，全部 PASS）
├── build/              综合与实现报告（reports/）、构建日志（logs/）
├── board/              上板文件：bitstream/（.bit + .ltx）、vio_params/（实验参数快照）
├── data/               实测数据与分析脚本
│   ├── ila/                控制域 ILA 一帧（8192 点）
│   ├── oscilloscope/       4 组示波器原始记录
│   └── scripts/            PID 定点复算、示波器波形分析
├── docs/               设计评审与调试说明（CDC、时序约束、参数控制、ILA 指南等）
├── skill/              技能包：9 项可复用模板/脚本 + 踩坑清单（见 skill/README.md）
└── report/             设计报告 + 大模型协作记录（llm_collaboration.md）
```

与选题指南推荐结构的对照：`src/` 即设计源码；由于 Vivado 工程脚本使用相对路径，仿真平台保存在 `src/tests/`，构建脚本保存在 `src/` 根目录，`sim/`、`build/` 中存放对应的结果与报告。

### RTL 模块 / Main modules

| 文件 | 功能 |
|---|---|
| `top_power_kicker.v` | 顶层：参数换算、模块连接、失锁重扫请求、VIO/ILA 例化 |
| `control.v` | 激发模块 `dks_power_kicker`：7 状态机 + 64 位序列时基，产生扫描斜坡与 AOM kick（余数累加斜坡） |
| `pd_adc_capture.v` | AD9643 IDDRE1 采样、128 倍抽取、toggle 跨时钟域、偏置校正 |
| `pd_pid_feedback.v` | 窗口判断与台阶确认、PID 使能、输出电压合成 |
| `pid_core_signed.v` | Q8 定点 PID（40 位积分、限幅、单周期 DSP 通路） |
| `capture_phase_status.v` | 四阶段状态码（扫描 / 等待台阶 / PID / 空闲），供 ILA 观测 |
| `ad9122_config.v`、`test_ad9122.v` | AD9122 配置与 ODDRE1 LVDS DDR 输出（500 MHz 域） |
| `ad9643_config.v`、`ad9516_config.v`、`spi_*.v` | 三线 SPI 配置 ADC、DAC 与时钟芯片 |
| `reset_sync.v`、`key_filter.v` | 异步置位同步释放复位、按键同步与锁定 |
| `uart_*.v` | 串口参数接口（保留，当前以 VIO 为唯一参数源） |

## 3. 结果摘要 / Key results

| 指标 | 结果 | 来源 |
|---|---|---|
| 扫描 / kick 时序分辨率 | 40 ns | RTL 设计，ILA 实测 |
| 功率反馈更新周期 | 512 ns（实测平均 511.99 ns） | `data/ila/` |
| 台阶确认 → PID 启动 | 1 个控制周期（40 ns） | `data/ila/` |
| PID 定点复算 | 3/3 与 ILA 一致 | `data/scripts/verify_pid_from_ila.py` |
| 失锁 → 重扫请求 / 重新扫描 | 80 ns / 120 ns | `data/ila/` |
| 孤子台阶维持时间 | 无 kick ≈ 0.5 μs；kick 无 PID ≈ 3.2 μs；kick + PID 伺服 ≥ 24 h | `data/oscilloscope/`（μs～ms 尺度过程）及长期运行测试 |
| 台阶消失 → 重新进入台阶 | ≈ 8.25 ms（一次扫描） | `data/oscilloscope/04_*.csv` |
| 资源 | LUT 22.24%，BRAM 37.50%，DSP 2.78% | `build/reports/utilization.rpt` |
| 时序 | WNS +0.136 ns，WHS +0.011 ns，TNS/THS = 0 | `build/reports/timing_summary.rpt` |
| 回归仿真 | 9 组平台全部 PASS | `sim/logs/` |

说明：各时钟域内部时序已收敛；ADC/DAC 外部接口因缺少板级走线延迟数据，外部 IO 时序标记为 PROVISIONAL，现阶段以 ILA 与示波器板级实测验证接口工作正常，详见 `docs/timing_constraints.md`。

## 4. 复现步骤 / How to reproduce

以下命令在 Windows PowerShell 中、`src/` 目录下执行。Vivado 安装路径请按实际修改。

### 4.1 回归仿真

```powershell
cd src
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_regression.ps1 -VivadoBin 'C:\Xilinx\Vivado\2024.1\bin' -Tclsh 'tclsh.exe'
```

运行结束应输出 `REGRESSION=PASS`，结果写入 `src/verification/sim_<时间戳>/summary.txt`。部分测试会故意注入错误用例，以验证检查本身有效。参考结果见 `sim/logs/`。

### 4.2 重建工程并生成比特流

```powershell
cd src
vivado -mode batch -source recreate_project.tcl         # 校验输入清单并重建 XPR（不删除源码目录）
vivado -mode batch -source build_fast_feedback_v1.tcl   # 综合、实现、导出报告、生成 bitstream
```

构建脚本先检查输入清单，再综合、布线并导出时序、CDC、DRC、方法学报告，确认锁存器为 0 且建立/保持时序通过后生成比特流，比特流输出位于 `src/power-kicker-fast-feedback-v1.runs/impl_1/`，报告输出到 `src/verification/implementation/`，可与 `build/reports/` 中的参考报告比对。

### 4.3 上板运行

1. 用 Vivado Hardware Manager 下载 `board/bitstream/top_power_kicker.bit`，探针文件为同目录的 `top_power_kicker.ltx`。
2. 在 Tcl Console 中 `source src/set_fast_feedback_v1_vio_params.tcl` 写入一组参数，或使用 `board/vio_params/` 中保存的实验参数快照；参数含义见 `docs/parameter_control.md`。
3. 采集控制域 ILA：`source src/configure_capture_debug.tcl`，以状态码 `w_capture_phase = 3` 为触发条件；ADC 域 ILA 使用 `src/configure_adc_ila.tcl`。说明见 `docs/capture_state_ila_guide.md`、`docs/adc_ila_guide.md`。
4. 示波器接线：CH1 AOM 驱动，CH2 激光调谐，CH3 透射功率（PD1），CH4 频梳功率（PD2）。

### 4.4 数据复算

```bash
cd data/scripts
python3 verify_pid_from_ila.py          # 由 ILA 帧复算 PID，应输出 RESULT=PASS
python3 analyze_oscilloscope.py         # 生成三种条件台阶对比与失锁恢复波形图（需要 numpy、matplotlib）
```

## 5. License

本项目以 MIT License 开源，见 `LICENSE`。
