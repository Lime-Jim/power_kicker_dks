#!/usr/bin/env python3
"""Plot the four Siglent SDS5104X records used in Section 3.3.6 of the report.

CH1: AOM drive voltage   CH2: laser tuning voltage
CH3: transmission (PD1)  CH4: comb power (PD2, feedback channel)

Usage:  python3 analyze_oscilloscope.py [--out figures]
Requires numpy and matplotlib.
"""
import argparse, os
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

HERE = os.path.dirname(os.path.abspath(__file__))
SCOPE = os.path.join(HERE, '..', 'oscilloscope')
FILES = [
    ('01_no_kick_short_step.csv', 'No kick', 1e6, 'us', (-2, 4)),
    ('02_kick_no_pid.csv', 'Kick, no PID', 1e6, 'us', (-2, 4)),
    ('03_kick_pid_stable.csv', 'Kick + PID servo', 1e3, 'ms', (-0.5, 9.48)),
]


def load(name):
    """Return array [t(s), CH1, CH2, CH3, CH4]."""
    path = os.path.join(SCOPE, name)
    with open(path) as f:
        for i, line in enumerate(f):
            if line.startswith('Second'):
                break
    return np.loadtxt(path, delimiter=',', skiprows=i + 1)


def smooth(x, n):
    return np.convolve(x, np.ones(n) / n, mode='same')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default=os.path.join(HERE, 'figures'))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)

    fig, axs = plt.subplots(2, 3, figsize=(13, 5.5), sharex='col', gridspec_kw={'height_ratios': [1, 1.6]})
    for j, (name, title, scale, unit, xl) in enumerate(FILES):
        d = load(name)
        t = d[:, 0] * scale
        m = (t >= xl[0]) & (t <= xl[1])
        n = 125 if unit == 'us' else 25
        axs[0, j].plot(t[m], smooth(d[:, 1], 25)[m], color='tab:orange')
        axs[0, j].set_title(title)
        axs[1, j].plot(t[m], d[m, 4], color='tab:purple', lw=0.4, alpha=0.3)
        axs[1, j].plot(t[m], smooth(d[:, 4], n)[m], color='tab:purple')
        axs[1, j].set_xlabel(f'Time ({unit})')
        axs[1, j].set_xlim(*xl)
    axs[0, 0].set_ylabel('CH1 AOM (V)')
    axs[1, 0].set_ylabel('CH4 comb power (V)')
    fig.tight_layout()
    p1 = os.path.join(a.out, 'step_comparison.png')
    fig.savefig(p1, dpi=150)

    d = load('04_unlock_auto_recovery.csv')
    t = d[:, 0] * 1e3
    fig, ax = plt.subplots(3, 1, figsize=(10, 6), sharex=True)
    for k, (ch, lab) in enumerate([(1, 'CH1 AOM (V)'), (2, 'CH2 laser tuning (V)'), (4, 'CH4 comb power (V)')]):
        ax[k].plot(t, smooth(d[:, ch], 25))
        ax[k].set_ylabel(lab)
    ax[-1].set_xlabel('Time (ms)')
    fig.tight_layout()
    p2 = os.path.join(a.out, 'auto_recovery.png')
    fig.savefig(p2, dpi=150)
    print('Saved', p1, 'and', p2)


if __name__ == '__main__':
    main()
