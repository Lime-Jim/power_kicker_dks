"""Audit the new state ILA plus the retained ADC/DAC debug interfaces."""
import json
import zipfile
import verify_adc_debug_artifacts as adc

widths = [2, 3, 16, 1, 16, 16, 16, 1, 1, 1, 1, 1, 1, 1, 1, 16, 16, 1, 1, 1, 1, 1, 1]
core = adc.core("u_ila_capture")
pins = sorted(core["pins"], key=lambda p: p["portIndex"])
assert [adc.width(p) for p in pins] == widths
for pin in pins:
    print(f'CAPTURE {pin["name"]}: width={adc.width(pin)}, nets={[n["name"] for n in pin["nets"]]}')
for number, name in [(0, "w_capture_phase"), (17, "w_capture_event"), (18, "w_captured_seen")]:
    # Vivado adds _1 to distinguish the ILA display name from the same VIO net.
    assert pins[number]["nets"][0]["name"] in (name, name + "_1")
for probe, width, name in [("probe_in8", 2, "w_capture_phase"), ("probe_in9", 1, "w_captured_seen")]:
    pin = next(p for p in adc.pid["pins"] if p["name"] == probe)
    assert adc.width(pin) == width and pin["nets"][0]["name"] == name, pin
with zipfile.ZipFile(adc.ip_dir / "ila_capture.xcix") as z:
    name = next(n for n in z.namelist() if n.endswith("/ila_capture.xci"))
    params = json.loads(z.read(name))["ip_inst"]["parameters"]["component_parameters"]
    for key, wanted in {"C_NUM_OF_PROBES": "23", "C_DATA_DEPTH": "8192", "C_INPUT_PIPE_STAGES": "1"}.items():
        assert params[key][0]["value"] == wanted
print("CAPTURE_DEBUG_ARTIFACTS=PASS (23 probes; 8192 samples; VIO phase/history; ADC and DAC retained)")
