#!/usr/bin/env python3

import json
import os
from pathlib import Path
import struct
import sys


tool = Path(sys.argv[0]).name
with open(os.environ["IMAGE_TEST_LOG"], "a") as log:
    log.write(json.dumps([tool, *sys.argv[1:]]) + "\n")
if os.environ.get("IMAGE_TEST_FAIL") == "bad-format" and tool == "mkfs.fat":
    with open(sys.argv[-1], "r+b") as image:
        image.write(bytes(512))
    sys.exit(0)
if os.environ.get("IMAGE_TEST_FAIL") == tool:
    if tool == "find":
        sys.stdout.buffer.write(b".\0")
    elif tool == "cpio":
        sys.stdout.buffer.write(b"partial archive")
    print("Intentional image tool failure: " + tool, file=sys.stderr)
    sys.exit(17)

real_tools = json.loads(os.environ.get("IMAGE_TEST_REAL_TOOLS", "{}"))
if tool in real_tools:
    os.execv(real_tools[tool], [real_tools[tool], *sys.argv[1:]])

# Mocks exercise the production Make rules and capacity check without requiring
# FAT/CPIO tools on the workflow-validation host. They do not produce real images.
if tool == "find":
    for root, directories, files in os.walk("."):
        for name in [root, *(str(Path(root) / name) for name in files)]:
            sys.stdout.buffer.write(os.fsencode(name) + b"\0")
elif tool == "cpio":
    names = sys.stdin.buffer.read().split(b"\0")
    sys.stdout.buffer.write(json.dumps([os.fsdecode(name) for name in names if name]).encode())
elif tool == "fallocate":
    with open(sys.argv[-1], "wb") as image:
        image.truncate(int(sys.argv[2]))
elif tool == "mkfs.fat":
    with open(sys.argv[-1], "r+b") as image:
        boot = bytearray(512)
        struct.pack_into("<HBHBHH", boot, 11, 512, 1, 1, 2, 224, 2880)
        struct.pack_into("<H", boot, 22, 9)
        boot[510:512] = b"\x55\xaa"
        image.write(boot)
elif tool == "mcopy":
    pass
else:
    raise AssertionError(tool)
