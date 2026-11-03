#!/usr/bin/env python3
"""Load Siglent SDS-series oscilloscope CSV exports.

Usage as a module:
    from siglent_csv import load
    t, ch = load('record.csv')       # t in seconds, ch[1..4] in volts

Usage from the command line (prints header info and basic statistics):
    python3 siglent_csv.py record.csv
"""
import sys
import numpy as np


def load(path):
    meta, header_line = {}, None
    with open(path, encoding='utf-8', errors='replace') as f:
        for i, line in enumerate(f):
            if line.startswith('Second'):
                header_line = i
                break
            parts = [p.strip() for p in line.strip().split(',') if p.strip()]
            if parts:
                meta[parts[0]] = parts[1:]
    if header_line is None:
        raise ValueError('Not a Siglent CSV export: no "Second" header row found')
    data = np.loadtxt(path, delimiter=',', skiprows=header_line + 1)
    t = data[:, 0]
    ch = {k + 1: data[:, k + 1] for k in range(data.shape[1] - 1)}
    return t, ch, meta


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return
    t, ch, meta = load(sys.argv[1])
    dt = np.median(np.diff(t))
    print(f'points={len(t)}  span={t[-1] - t[0]:.6g} s  sample_interval={dt:.6g} s')
    for k, v in ch.items():
        print(f'CH{k}: min={v.min():.4g} V  max={v.max():.4g} V  mean={v.mean():.4g} V')
    for key in ('Model Number', 'Sample Interval', 'Record Length'):
        if key in meta:
            print(f'{key}: {", ".join(meta[key])}')


if __name__ == '__main__':
    main()
