#!/usr/bin/env python3
"""Wrapper that runs an OCI CLI command with a hard socket timeout.

The OCI CLI (Python SDK) doesn't honour a connect timeout when the
network is unreachable (e.g. Render Oregon -> OCI Johannesburg).
Forcing socket.setdefaulttimeout() before any HTTP call is made
guarantees the TCP connect will fail within N seconds.
"""
import socket, subprocess, sys, os

TIMEOUT = int(os.environ.get("OCI_SOCKET_TIMEOUT", "60"))

def main():
    socket.setdefaulttimeout(TIMEOUT)
    cmd = sys.argv[1:]
    result = subprocess.run(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=TIMEOUT + 30,   # hard wall beyond socket timeout
    )
    sys.stdout.buffer.write(result.stdout)
    sys.exit(result.returncode)

if __name__ == "__main__":
    main()