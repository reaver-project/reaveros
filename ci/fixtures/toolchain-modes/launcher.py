import json
import os
from pathlib import Path
import sys

with Path(sys.argv[1]).open("a") as log:
    log.write(json.dumps(sys.argv[2:]) + "\n")
os.execv(sys.argv[2], sys.argv[2:])
