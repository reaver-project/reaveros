import json
from pathlib import Path
import subprocess
import sys

# Generated installed artifacts for the real superbuild's stamp-layout fixture.
# Actual compilation, failure recovery, and legacy recovery have separate tests.
root = Path(sys.argv[1])
repository = Path(__file__).resolve().parents[5]
for path in (root / "toolchain").glob("*-lifecycle.json"):
    contract = json.loads(path.read_text())
    for output in contract["required_outputs"]:
        target = Path(contract["directories"]["install"]) / output
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text("completed fixture output\n")
        if Path(output).parts[0] in ("bin", "sbin"):
            target.chmod(0o755)
    order = ["mkdir", "download"] + [name for name in contract["stamps"]
        if name not in ("mkdir", "download", "prune")]
    for name in order:
        stamp = contract["stamps"][name]
        target = Path(stamp)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.touch()
    (root / "toolchain" / (contract["project"] + "-source-identity")).write_text(
        contract["identity"]["source"] + "\n")
    subprocess.run([sys.executable, str(repository / "toolchain/installed-state"),
                    "record", str(path)], check=True)
