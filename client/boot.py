import sys


def ensure_paths():
    for entry in ("", ".", "/lib", "lib"):
        if entry not in sys.path:
            sys.path.append(entry)


ensure_paths()
