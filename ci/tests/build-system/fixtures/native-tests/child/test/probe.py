import os
from pathlib import Path
import sys

role, component = sys.argv[1:3]
marker = Path("state-" + component)
if role == "setup":
    marker.write_text(component)
elif role == "cleanup":
    assert marker.read_text() == component
    marker.unlink()
elif role == "dependent":
    assert Path("result-" + component).read_text() == component
elif role == "probe":
    configuration, working = sys.argv[3:5]
    assert configuration in ("Debug", "Release")
    assert Path.cwd() == Path(working)
    assert os.environ["PROBE_ENV"] == "value;with semi"
    assert os.environ["COMPONENT"] == component
    assert os.environ["MODIFIED"] == "initial suffix"
    assert marker.read_text() == component
    assert sys.argv[5:] == [
        "argument with space", "semicolon;argument", "back\\slash", "endswith\\",
        "unbalanced[;brackets", "literal ${variable} and $ENV{variable}",
        'embedded "quotes"', "", "\nleading newline", "carriage\rreturn", "tab\tvalue"]
    Path("result-" + component).write_text(component)
    print("PROBE_OK " + component)
else:
    raise AssertionError(role)
