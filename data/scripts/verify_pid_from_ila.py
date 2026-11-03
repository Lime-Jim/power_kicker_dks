#!/usr/bin/env python3
"""Recompute the Q8 fixed-point PID from the control-domain ILA frame and
compare with the correction value recorded by the FPGA.

    e[n] = P_ref - P[n]
    I[n] = sat_I(I[n-1] + Ki*e[n])
    u[n] = sat_u((Kp*e[n] + I[n] + Kd*(e[n]-e[n-1])) >>> 8)

Usage:  python3 verify_pid_from_ila.py [ila_csv] [--kp 256 --ki 8 --kd 0 --limit 1000]
Defaults reproduce Table 3-6 of the design report.
"""
import argparse, csv, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT = os.path.join(HERE, '..', 'ila', 'ila_capture_frame.csv')
SAT_I = 8388352


def s16(h):
    v = int(h, 16)
    return v - 0x10000 if v & 0x8000 else v


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('csv', nargs='?', default=DEFAULT)
    ap.add_argument('--kp', type=int, default=256)
    ap.add_argument('--ki', type=int, default=8)
    ap.add_argument('--kd', type=int, default=0)
    ap.add_argument('--limit', type=int, default=1000)
    a = ap.parse_args()
    with open(a.csv, newline='') as f:
        rows = list(csv.reader(f))
    head, data = rows[0], rows[2:]
    col = {name.split('[')[0]: i for i, name in enumerate(head)}
    get = lambda r, k: r[col[k]]
    integ, e_prev, ok, n = 0, 0, True, 0
    print(f"{'sample':>7} {'PD':>6} {'e':>5} {'Kp*e':>8} {'I':>7} {'u_calc':>7} {'u_ila':>6}")
    for i, r in enumerate(data):
        if get(r, 'w_pd_adc_sample_tick') != '1' or get(r, 'w_pid_active_1') != '1':
            continue
        target = s16(get(r, 'ctrl_pid_target_code'))
        pd = int(get(r, 'w_pd_adc_sample_corrected_1'))
        e = target - pd
        integ = max(-SAT_I, min(SAT_I, integ + a.ki * e))
        u = (a.kp * e + integ + a.kd * (e - e_prev)) >> 8
        u = max(-a.limit, min(a.limit, u))
        e_prev = e
        # the registered correction appears one control cycle later
        nxt = data[i + 1] if i + 1 < len(data) else r
        u_ila = s16(get(nxt, 'w_pid_nkt_corr_1'))
        active_next = get(nxt, 'w_pid_active_1') == '1'
        tag = '' if active_next else '  (PID released next cycle, not output)'
        if active_next and u != u_ila:
            ok = False
        n += 1
        print(f"{get(r, 'Sample in Buffer'):>7} {pd:>6} {e:>5} {a.kp * e:>8} {integ:>7} {u:>7} {u_ila if active_next else '-':>6}{tag}")
    print(f"\nPID updates checked: {n}")
    print('RESULT=PASS' if ok and n else 'RESULT=FAIL')
    sys.exit(0 if ok and n else 1)


if __name__ == '__main__':
    main()
