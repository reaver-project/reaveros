from pathlib import Path
import sys
import time

root = Path(sys.argv[1])
project, operation = sys.argv[2:]
(root / (project + "-" + operation + "-entered")).touch()
if operation == "build":
    deadline = time.monotonic() + 15
    while not (root / (project + "-release")).exists():
        if time.monotonic() > deadline:
            raise RuntimeError("Timed out waiting for test release")
        time.sleep(0.02)
