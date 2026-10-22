"""Shared config loader for tmp_lifecycle.py and archive.py.

Config file (all keys optional):
  $FILE_LIFECYCLE_CONFIG, else ~/.claude/groundwork/file-lifecycle.json

A config file that exists but is invalid — unparseable, a wrong type, an unsafe root — is reported as
an error instead of falling back to defaults: defaults have no registry entries, so sweeping with
them would delete items the user registered as `keep`, and a value like "false" for a boolean must
never read as true.
"""
import json
import os

HOME = os.path.expanduser("~")
POLICIES = ("keep", "ttl", "ttl-contents")

DEFAULTS = {
    "tmp_root": "~/.claude/tmp",
    "archive_root": "~/claude-archive",
    "log": "~/.claude/groundwork/state/file-lifecycle.log",
    "sweep_top_level": False,
    "default_ttl_days": 7,
    "session_grace_hours": 24,
    "session_idle_days": 7,
    "throttle_hours": 6,
    "entries": [],
}
PATH_KEYS = ("tmp_root", "archive_root", "log")
BOOL_KEYS = ("sweep_top_level",)
NUMBER_KEYS = ("default_ttl_days", "session_grace_hours", "session_idle_days", "throttle_hours")


def config_path():
    return os.environ.get("FILE_LIFECYCLE_CONFIG") or os.path.join(HOME, ".claude", "groundwork", "file-lifecycle.json")


def expand(path):
    return os.path.realpath(os.path.expanduser(path))


def is_positive_number(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool) and v > 0


def unsafe_root(path):
    """Why a directory may not be used as a root the tools create in and delete from, or None."""
    if not os.path.isabs(os.path.expanduser(path)):
        return "must be an absolute path (or start with ~)"
    real = expand(path)
    if real in (os.sep, os.path.realpath(HOME)):
        return "must not be / or the home directory"
    if os.path.exists(os.path.join(real, ".git")):
        return "must not be a git checkout"
    return None


def validate(user):
    if not isinstance(user, dict):
        return "top level is not an object"
    for k in PATH_KEYS:
        if k in user and (not isinstance(user[k], str) or not user[k].strip()):
            return f"{k} must be a non-empty string"
    for k in ("tmp_root", "archive_root"):
        if k in user:
            why = unsafe_root(user[k])
            if why:
                return f"{k} {why}"
    for k in BOOL_KEYS:
        if k in user and not isinstance(user[k], bool):
            return f"{k} must be true or false (not a string)"
    for k in NUMBER_KEYS:
        if k in user and not is_positive_number(user[k]):
            return f"{k} must be a positive number"
    entries = user.get("entries", [])
    if not isinstance(entries, list):
        return "entries must be a list"
    for i, e in enumerate(entries):
        if not isinstance(e, dict) or not isinstance(e.get("pattern"), str) or not e["pattern"]:
            return f"entries[{i}] needs a non-empty string pattern"
        if "ttl_days" in e and not is_positive_number(e["ttl_days"]):
            return f"entries[{i}].ttl_days must be a positive number"
    return None


def load_config():
    """Return (config, error). On error the config holds defaults and callers must not delete anything."""
    cfg = dict(DEFAULTS)
    path = config_path()
    if not os.path.exists(path):
        return cfg, None
    try:
        with open(path, encoding="utf-8") as f:
            user = json.load(f)
    except (OSError, ValueError) as e:
        return cfg, f"{path}: {e}"
    err = validate(user)
    if err:
        return cfg, f"{path}: {err}"
    cfg.update({k: v for k, v in user.items() if k in DEFAULTS})
    return cfg, None
