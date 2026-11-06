#!/usr/bin/env python3
"""Check the flits the chip sends back (streamed by the FPGA over UART) against the
expected values in a BSG trace (.tr) file.

Setup:        pip install pyserial
Find the port: Windows Device Manager > Ports (COMx);  Linux: /dev/ttyUSB0

Live:     python uart_compare.py benchmark5_recv_trace.tr --port COM5
Offline:  python uart_compare.py benchmark5_recv_trace.tr --log capture.txt
          (capture.txt = text saved from PuTTY/any terminal, one 8-hex-digit line per flit)

Start this script FIRST (it waits for data), then press KEY[0] on the board and flip SW[0].

Expected values = the last 32 bits of every trace line whose 4-bit opcode is 0010
(receive-and-check). Lines may contain '_' separators and '#' comments.
Each UART line from the FPGA is one 32-bit flit as 8 hex digits.
"""
import argparse
import re
import sys
import time

HEX8 = re.compile(r"^[0-9A-Fa-f]{8}$")


def load_expected(path):
    exp = []
    with open(path) as f:
        for n, raw in enumerate(f, 1):
            line = raw.split("#")[0].strip()
            if not line:
                continue
            bits = re.sub(r"[_\s]", "", line)
            if not re.fullmatch(r"[01]{36}", bits):
                print(f"warning: {path}:{n}: not a 36-bit binary line, skipped: {raw.strip()!r}")
                continue
            if bits[:4] == "0010":            # receive-and-check
                exp.append(int(bits[4:], 2))
    return exp


def parse_line(text):
    text = text.strip()
    return int(text, 16) if HEX8.match(text) else None


def show(idx, val, exp):
    if idx < len(exp):
        ok = "ok" if val == exp[idx] else f"MISMATCH (expected {exp[idx]:08X})"
    else:
        ok = "EXTRA (past end of expected data)"
    print(f"  [{idx + 1:4d}] {val:08X}  {ok}")


def collect_serial(ser, exp, idle_s, wait_s):
    """Read lines until all expected flits arrive, or the line goes quiet."""
    got, garbled = [], 0
    t_start, t_last = time.time(), None
    while True:
        raw = ser.readline()                     # b"" on timeout
        now = time.time()
        if raw:
            t_last = now
            val = parse_line(raw.decode("ascii", errors="replace"))
            if val is None:
                garbled += 1
                print(f"  garbled line: {raw!r}")
            else:
                show(len(got), val, exp)
                got.append(val)
        if exp and len(got) >= len(exp):
            break
        if t_last is not None and now - t_last > idle_s:
            break
        if t_last is None and now - t_start > wait_s:
            break
    return got, garbled


def collect_log(path, exp):
    got, garbled = [], 0
    with open(path) as f:
        for raw in f:
            if not raw.strip():
                continue
            val = parse_line(raw)
            if val is None:
                garbled += 1
                print(f"  garbled line: {raw.rstrip()!r}")
            else:
                show(len(got), val, exp)
                got.append(val)
    return got, garbled


def summarize(got, exp, garbled):
    n = min(len(got), len(exp))
    bad = [i for i in range(n) if got[i] != exp[i]]
    print("\n==== summary ====")
    print(f"expected flits : {len(exp)}")
    print(f"received flits : {len(got)}   (garbled lines: {garbled})")
    print(f"matched        : {n - len(bad)} of {n} compared")
    if bad:
        print(f"first mismatch : flit {bad[0] + 1}: got {got[bad[0]]:08X}, expected {exp[bad[0]]:08X}")
    if len(got) < len(exp):
        print(f"MISSING        : {len(exp) - len(got)} flits never arrived "
              f"(check the done and FIFO-overflow LEDs)")
    if len(got) > len(exp):
        print(f"EXTRA          : {len(got) - len(exp)} flits beyond the expected data")
    passed = (not bad) and len(got) == len(exp) and garbled == 0
    print("RESULT         :", "PASS" if passed else "FAIL")
    return passed


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("trace", help="receive trace file (.tr) holding the expected output")
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--port", help="serial port, e.g. COM5 or /dev/ttyUSB0")
    src.add_argument("--log", help="compare a saved text capture instead of reading live")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--idle", type=float, default=3.0, help="stop after this many seconds of silence")
    ap.add_argument("--wait", type=float, default=120.0, help="give up if nothing arrives within this many seconds")
    args = ap.parse_args()

    exp = load_expected(args.trace)
    print(f"loaded {len(exp)} expected flits from {args.trace}")

    if args.log:
        got, garbled = collect_log(args.log, exp)
    else:
        import serial
        with serial.Serial(args.port, args.baud, timeout=0.5) as ser:
            print(f"listening on {args.port} @ {args.baud} baud ... "
                  f"now press KEY[0] and flip SW[0]. Ctrl-C to stop.")
            try:
                got, garbled = collect_serial(ser, exp, args.idle, args.wait)
            except KeyboardInterrupt:
                got, garbled = [], 0
                print("\nstopped.")
    if not got:
        print("nothing received: check wiring/GND, the UART pin assignment, baud rate, and that SW[0] is on")
        sys.exit(2)
    sys.exit(0 if summarize(got, exp, garbled) else 1)


if __name__ == "__main__":
    main()
