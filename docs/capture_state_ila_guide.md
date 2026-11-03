# 扫描、捕获、PID反馈状态与ILA

本次新增同步流程状态机 `capture_phase_status`，观察既有扫描/kick/PID流程，不改变波形时序、PID增益或失锁恢复策略。状态记录使用25 MHz控制时钟。

## 先看状态

| 状态码 | 名称 | 含义 |
|---|---|---|
| 0 | IDLE 空闲 | 复位/尚未启动；未触发kick的扫描已结束；或kick结束后反馈关闭 |
| 1 | SCAN 扫描 | 本轮开始、kick之前的扫描阶段；也包括失锁后的重扫准备和自动回扫 |
| 2 | CAPTURE 捕获中 | kick已经开始，等待PID延时、扫描停止、连续入窗等条件；也包括绕过入窗门控后在窗外PID纠偏 |
| 3 | PID_FEEDBACK 已确认捕获并反馈 | PID正在运行，PD已在运行中满足连续入窗确认，且当前窗口资格仍有效 |

`w_capture_phase` 是当前阶段，`w_capture_valid` 是当前有效的捕获资格；`w_captured_seen` 是历史标志。看到状态3可判断程序已确认捕获并进入反馈；这仍基于程序的PD窗口判据，不是额外的光学锁定检测。

关闭 `vio_pid_require_window` 只绕过PID启动门控，不绕过此处“捕获成功”的判定。此时 `w_pid_active=1`、状态2是合法情况：PID已经纠偏，但PD尚未连续入窗。连续入窗后才转为3。

正常过程为 `0 → 1 → 2 → 3`，出窗失锁后为 `3 → 1 → 2 → 3`。若一直未捕获，状态2可能持续到自动回扫或人工操作；原有逻辑没有新增捕获超时。关闭反馈或手动clear不会冒充一次失锁。

### 扫描和捕获是否重叠

实际动作允许重叠，状态码互斥。正的 `vio_sweep_stop_offset_ns` 会使扫描在kick开始后继续一段时间，此时优先显示2，且 `w_scan_stopped=0`。因此不能用状态2推断扫描已经停止。负偏移则可能在kick之前就停止扫描，此时仍显示1，等待kick开始。状态3仍要求既有PID扫描停止门控满足。

状态机在时钟边沿采样控制信号，阶段变化相对被观察到的事件有一个控制时钟（40 ns）的记录延迟；所有ILA输入统一经过1级采样流水线。精确判断重叠时同时看kick、scan_stopped和底层controller_state。PD连续入窗计数按有效采样tick推进，不是每个ILA采样点推进。

## VIO也能直接读

`u_vio_pid` 保留原输入0～7，新增：

- `probe_in8 / w_capture_phase`：2位，显示为Unsigned Decimal，0/1/2/3按上表解释。
- `probe_in9 / w_captured_seen`：1位；出现过状态3后保持1，即使之后失锁重扫也不清零，避免VIO刷新漏掉短暂成功。

`w_captured_seen=1` 不代表现在仍锁住。按钮复位、失钟复位或 `vio_pid_clear=1` 清除历史；原 `pid_clear` 同时会清除PID状态和修正，不只是清历史。新的扫描周期不会清历史。

## 控制域ILA探针

选择 `u_ila_capture`。采样时钟25 MHz，每点40 ns，深度8192，一帧约327.68 μs。高频原始ADC仍使用独立的 `u_hardware/u_ila_adc`；两者各用自己的时钟。

下表使用RTL信号名。实际LTX为了区分同时接入VIO的信号，会给部分ILA显示名称加 `_1`：例如probe0显示为 `w_capture_phase_1`，probe2为 `w_pd_adc_sample_corrected_1`，probe18为 `w_captured_seen_1`。它们仍是同一信号，按probe编号对应即可；VIO中的状态/历史名称仍没有此后缀。probe19在实际LTX显示为 `vio_pid_feedback_enable_1`。

| probe | 信号 | 位宽 | 用途 |
|---|---|---:|---|
| 0 | w_capture_phase | 2 | 主流程状态，0/1/2/3 |
| 1 | w_controller_state | 3 | 底层波形状态，见下文 |
| 2 | w_pd_adc_sample_corrected | 16 | PID实际使用的PD码，已减21 mV偏置 |
| 3 | w_pd_adc_sample_tick | 1 | 新PD样本有效脉冲 |
| 4 | w_pid_nkt_corr | 16 | PID NKT修正码 |
| 5 | w_pid_nkt_data | 16 | 最终NKT输出码 |
| 6 | w_pid_aom_data | 16 | 最终AOM输出码 |
| 7 | w_pid_active | 1 | PID是否使能，绕过模式下可早于状态3 |
| 8 | w_pd_step_found | 1 | 连续入窗检测结果 |
| 9 | w_capture_valid | 1 | 当前PID运行且捕获资格有效 |
| 10 | w_kick_sig | 1 | kick波形段有效 |
| 11 | w_pid_delay_done | 1 | 从kick开始计的独立PID延时已到达 |
| 12 | w_scan_stopped | 1 | 正向扫描已停且不在自动回扫 |
| 13 | w_pid_restart_scan | 1 | 失锁重扫请求，可作为失锁触发源 |
| 14 | w_sequence_start | 1 | 新一轮扫描开始 |
| 15 | ctrl_pid_target_code | 16 | PD目标码 |
| 16 | ctrl_pid_window_code | 16 | PD窗口半宽码 |
| 17 | w_capture_event | 1 | 每次进入状态3时脉冲一个周期，可作为成功触发源 |
| 18 | w_captured_seen | 1 | 曾成功捕获的历史标志 |
| 19 | ctrl_pid_feedback_enable | 1 | VIO反馈总开关 |
| 20 | vio_pid_require_window | 1 | PID启动是否要求连续入窗 |
| 21 | vio_pid_clear | 1 | 手动清除PID及捕获历史 |
| 22 | w_phase_change | 1 | 主流程状态变化脉冲 |

底层波形状态：0=IDLE，1=SCAN，2=KICK_FALL，3=KICK_RISE，4=DONE，5=RETURN，6=WAIT_STOP。它与probe0是两套编码，例如底层4=DONE时主流程完全可以是3=PID反馈；不要把底层3误认作PID状态。

probe2/4/5/6/15建议Signed Decimal；状态和窗口半宽用Unsigned Decimal。按当前程序标定，校正后PD约为 `probe2 × 875 / 32767 mV`，不要再次减21 mV；NKT修正及DAC码约为 `码 × 1500 / 32767 mV`。这些是现有程序系数，仍以板卡实测标定为准。

## 建议抓取方法

先使用本次 `bitstream/capture_state_20260921` 中的BIT和LTX配套下载，刷新器件，再选择 `u_ila_capture`。

1. 观察捕获全过程：触发源选 `w_kick_sig` 上升沿，触发位置约设在缓冲区前1/4处。可看到扫描→kick/捕获→PID以及PD变化。
2. 只抓成功事件：触发条件设 `w_capture_event == 1`，在下一轮开始前Run Trigger。每次成功都会产生新脉冲；不要用历史标志作为重复捕获触发源。
3. 分析失锁：触发条件设 `w_pid_restart_scan == 1`，触发位置放中间，比较失锁前后的PD、修正和状态。
4. 看当前值：Run Trigger Immediate立即抓取。

单帧327.68 μs不能覆盖毫秒级完整慢扫描；优先围绕kick、成功或失锁触发，避免把“时间窗口之外”误当成“没有发生”。原始ADC ILA与控制域ILA没有额外硬件交叉触发。

Tcl Console可使用以下工具（source本身不下载BIT、不改VIO输出）：

```tcl
source {D:/power-kicking_handoff_20260907/code/vio_stable/capture_ila_tools.tcl}
pk_capture_status
pk_capture_now
# 先建立目录，使用未存在的CSV文件名：
pk_capture_now {D:/measurements/capture_001.csv}
# 手动配置触发并Run Trigger后，可等待完成、读取并导出：
pk_capture_read {D:/measurements/capture_triggered_001.csv}
```

CSV进制以导出内容的Radix记录为准。`pk_capture_read`等待最多30秒；未触发时不会无限等待。本次只完成离线验证和构建，未上板验证实际抓取。构建及备份信息见 `CAPTURE_STATE_BUILD_RESULT.md`。
