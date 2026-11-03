"""Audit the generated debug map and configured IP without hardware access."""
import json
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parent
run = root / "power-kicker-fast-feedback-v1.runs/impl_1"
ltx = json.loads((run / "top_power_kicker.ltx").read_text(encoding="utf-8"))
cores = [c for d in ltx["ltx_root"]["ltx_data"] for c in d.get("debug_cores", [])]

def core(suffix):
    found = [c for c in cores if c["name"].endswith(suffix)]
    assert len(found) == 1, (suffix, [c["name"] for c in found])
    return found[0]

def width(pin):
    return abs(pin["leftIndex"] - pin["rightIndex"]) + 1

adc = core("u_ila_adc")
pins = sorted(adc["pins"], key=lambda p: p["portIndex"])
assert [width(p) for p in pins] == [14, 14, 16], pins
for pin in pins:
    print(f'ADC {pin["name"]}: width={width(pin)}, nets={[n["name"] for n in pin["nets"]]}')
core("u_ila_dac")
pid = core("u_vio_pid")
for name, wanted in [("probe_out9", 32), ("probe_out10", 1)]:
    pin = next(p for p in pid["pins"] if p["name"] == name)
    assert width(pin) == wanted, pin
    print(f'PID {name}: width={width(pin)}, nets={[n["name"] for n in pin["nets"]]}')

ip_dir = root / "power-kicker-fast-feedback-v1.srcs/sources_1/ip"
with zipfile.ZipFile(ip_dir / "ila_adc.xcix") as z:
    candidates = [n for n in z.namelist() if n.endswith("/ila_adc.xci") or n == "ila_adc.xci"]
    assert len(candidates) == 1, candidates
    params = json.loads(z.read(candidates[0]))["ip_inst"]["parameters"]["component_parameters"]
    for name, value in {"C_NUM_OF_PROBES": "3", "C_PROBE0_WIDTH": "14", "C_PROBE1_WIDTH": "14",
                        "C_PROBE2_WIDTH": "16", "C_DATA_DEPTH": "8192", "C_INPUT_PIPE_STAGES": "1"}.items():
        assert params[name][0]["value"] == value, (name, params[name])
assert (run / "top_power_kicker.bit").stat().st_size > 1000000
print("ADC_DEBUG_ARTIFACTS=PASS (ADC 14/14/16, 8192 samples, pipeline 1; DAC retained; PID VIO 32/1)")
