import os
from pathlib import Path
import re
import stat


def packaging_environment():
    value = os.environ.get("SOURCE_DATE_EPOCH", "315532800")  # 1980-01-01 UTC
    if not re.fullmatch(r"[0-9]+", value) or not 315532800 <= int(value) <= 4294967295:
        raise ValueError("SOURCE_DATE_EPOCH must be an integer from 315532800 to 4294967295 (the common FAT/newc range)")
    return dict(os.environ, SOURCE_DATE_EPOCH=str(int(value)), TZ="UTC", LC_ALL="C")


def normalize_paths(root, names, epoch):
    for name in names:
        path = Path(name)
        if path.is_absolute() or ".." in path.parts:
            raise ValueError(f"staged path must be relative: {name!r}")
        path = root / path
        mode = path.lstat().st_mode
        if stat.S_ISDIR(mode):
            os.chmod(path, 0o755)
        elif stat.S_ISREG(mode):
            # Component installers express executable intent through owner-x.
            os.chmod(path, 0o755 if mode & stat.S_IXUSR else 0o644)
        elif not stat.S_ISLNK(mode):
            raise ValueError(f"unsupported staged file kind: {name!r}")
        os.utime(path, (epoch, epoch), follow_symlinks=False)
