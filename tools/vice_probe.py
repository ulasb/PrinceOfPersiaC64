#!/usr/bin/env python3
"""Poll VICE remote-monitor memory locations, print clean CSV rows.

Usage: vice_probe.py addr[:len] [addr[:len] ...] [--n N] [--dt SEC]
                     [--port P]
Each poll prints one line: hex bytes of every requested range, |-separated.
"""

import re
import socket
import sys
import time


def parse_args(argv):
    addrs, n, dt, port = [], 10, 1.0, 6510
    it = iter(argv)
    for a in it:
        if a == "--n":
            n = int(next(it))
        elif a == "--dt":
            dt = float(next(it))
        elif a == "--port":
            port = int(next(it))
        else:
            if ":" in a:
                s, ln = a.split(":")
                addrs.append((int(s, 16), int(ln)))
            else:
                addrs.append((int(a, 16), 1))
    return addrs, n, dt, port


def main():
    addrs, n, dt, port = parse_args(sys.argv[1:])
    for _ in range(n):
        try:
            sk = socket.create_connection(("127.0.0.1", port), timeout=2)
            sk.settimeout(0.5)
            out = []
            for start, ln in addrs:
                sk.sendall(f"m {start:04x} {start+ln-1:04x}\n".encode())
                time.sleep(0.08)
                data = b""
                try:
                    while True:
                        chunk = sk.recv(4096)
                        if not chunk:
                            break
                        data += chunk
                except socket.timeout:
                    pass
                vals = []
                for line in data.decode("latin1").splitlines():
                    m = re.search(r">C:([0-9a-f]{4})((?:\s+[0-9a-f]{2})+)",
                                  line)
                    if m:
                        vals += m.group(2).split()
                out.append(" ".join(vals[:ln]) or "??")
            sk.sendall(b"x\n")          # resume emulation
            sk.close()
            print(" | ".join(out), flush=True)
        except OSError as e:
            print(f"(probe error: {e})", flush=True)
        time.sleep(dt)


if __name__ == "__main__":
    main()
