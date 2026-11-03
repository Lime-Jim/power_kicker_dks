# scope_csv_tools — 示波器 CSV 读取

## 适用场景
用 Siglent SDS 系列示波器（本项目为 SDS5104X）导出波形 CSV，需要在 Python 中绘图、测量台阶持续时间或与 ILA 数据对照。

## 使用方法
```bash
python3 siglent_csv.py ../../data/oscilloscope/01_no_kick_short_step.csv   # 查看记录长度、采样间隔、各通道范围
```
```python
from siglent_csv import load
t, ch, meta = load('record.csv')   # t 单位为秒，ch[1]~ch[4] 单位为伏
```
本项目完整绘图实例见 `../../data/scripts/analyze_oscilloscope.py`。

## 处理经验
- 文件头有十余行元数据，数据从 `Second,Value,...` 之后开始，不能固定跳过行数。
- 窄脉冲细节（μs 级）与长时间趋势（ms 级）不要画在同一坐标里，用主图 + 放大小窗，并在主图上框出放大区间。
- 噪声较大的通道先做滑动平均再判断台阶，但测量持续时间时应回到原始数据确认边沿。
- 不同通道之间存在探头与线缆延迟差，几百 ns 以内的先后顺序不宜直接用于因果判断。

## 失效条件
其他品牌示波器的 CSV 头格式不同，需要修改 `load()` 中的表头识别规则。

## 已验证的效果
本项目 4 组记录（5 万～12.5 万点）均用此方法读取，生成报告图 3-7～3-9。

## 来源
在分析"无 kick / kick / kick + PID"三组记录时发现，CH1 的 AOM 下降比 CH4 频梳功率变化早约 0.2 μs，但这一差值与通道延迟在同一量级，因此报告中没有据此写出先后关系，并把这条经验写入"处理经验"。
