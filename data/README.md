# data — 实测数据与分析脚本

## ila/
`ila_capture_frame.csv`：控制域 ILA 一帧（8192 点，25 MHz，每点 40 ns），以状态码进入 PID（`w_capture_phase = 3`）为触发条件，完整记录扫描 → kick → 台阶识别 → PID → 失锁 → 重扫过程。对应设计报告 3.3.2–3.3.5 节。

## oscilloscope/
Siglent SDS5104X 导出的原始 CSV。CH1 AOM 驱动，CH2 激光调谐，CH3 透射功率（PD1），CH4 频梳功率（PD2）。

| 文件 | 条件 | 对应报告 |
|---|---|---|
| `01_no_kick_short_step.csv` | 不施加 kick | 图 3-8(a) |
| `02_kick_no_pid.csv` | 施加 kick、不进入 PID | 图 3-8(b) |
| `03_kick_pid_stable.csv` | kick 后进入 PID 伺服 | 图 3-8(c) |
| `04_unlock_auto_recovery.csv` | 台阶消失后自动重扫与重新捕获 | 图 3-9 |

## scripts/
- `verify_pid_from_ila.py`：按 Q8 定点公式由 ILA 帧复算 PID 修正量，并与 FPGA 记录值比对（报告表 3-6），输出 `RESULT=PASS`。
- `analyze_oscilloscope.py`：绘制三种条件的台阶对比与失锁自动恢复波形。
