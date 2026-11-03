# ADC ILA 读取说明

新增 `u_hardware/u_ila_adc`，原 DAC ILA 保留。ADC ILA 使用 ADC 自己的 `adc_clk`，采样深度8192，输入流水线1级。工程约束为250 MHz，即每点4 ns，一次抓取覆盖约32.768 μs；实际时间以板上ADC时钟为准。

## 探针与数值

| 探针 | RTL信号 | 位宽/建议显示 | 内容 |
|---|---|---|---|
| probe0 | adc_data_a | 14位，Signed Decimal | DDR接收器Q1支路经寄存后的原始ADC码 |
| probe1 | adc_data_b | 14位，Signed Decimal | DDR接收器Q2支路经寄存后的原始ADC码；现有PID使用此支路 |
| probe2 | pd_adc_debug | 16位，Signed Decimal | B支路每128周期抽取一次并左移2位，保持到下次更新；未扣21 mV偏置 |

Signed Decimal 的14位范围为-8192～8191，16位范围为-32768～32767。A/B是代码中DDR两支路的名称；物理模拟通道对应关系仍以板卡接线与ADC模式为准。probe2是抽取而非平均，每512 ns更新一次（250 MHz条件下），因此看到阶梯保持是正常现象。相邻抽取值相同会看不到跳变。

ILA显示的是数字采样码。按当前程序的标定约定，近似换算为：

```
原始B电压(mV) = signed(probe1) × 4 × 875 / 32767
抽取PD电压(mV) = signed(probe2) × 875 / 32767
PID校正后PD(mV) ≈ 抽取PD电压 - 21
```

实际PID先以整数码扣除偏置并限幅，存在量化差异。这些系数沿用现有程序，不能替代板卡模拟前端的实测标定。PID VIO的probe_in0仍可查看跨时钟、扣偏置后的反馈码；ADC ILA的probe2位于这些处理之前。

## 打开和抓取

1. 在Vivado Hardware Manager中使用本次同目录的 `top_power_kicker.bit` 和 `top_power_kicker.ltx` 配套文件编程。不要混用旧LTX。
2. 刷新器件，选择名称包含 `u_hardware/u_ila_adc` 的ILA。波形探针名称可能带完整层级，按上表probe编号识别。
3. 选择三条信号，在波形窗口右键将Radix设为 **Signed Decimal**；移动光标读取Value列。想看曲线时可切换总线的模拟显示样式。
4. 点击Run Trigger Immediate立即抓取一帧。若要观察kick附近的ADC变化，可以在B支路设置电平码触发；新增ADC ILA没有跨时钟接入kick触发信号。

也可在Vivado Tcl Console执行：

```tcl
source {D:/power-kicking_handoff_20260907/code/vio_stable/adc_ila_tools.tcl}
pk_adc_capture
```

抓取并导出CSV（先建立输出目录，使用未存在的文件名）：

```tcl
pk_adc_capture {D:/measurements/adc_001.csv}
```

脚本只选择当前器件上的ADC ILA，设置连续采样/8192点/立即触发，等待最多30秒后上传并显示。source本身不连接硬件、不下载BIT、不修改VIO。CSV中数值的进制以导出的Radix记录为准，不能将十六进制文本直接当作十进制。

如刷新后没有ADC ILA，检查是否下载本次BIT、加载对应LTX及ADC时钟是否运行。当前只完成离线构建与验证，未替用户下载到板卡，也未采集真实ADC波形。构建记录见 `PID_WINDOW_BUILD_RESULT.md`。
