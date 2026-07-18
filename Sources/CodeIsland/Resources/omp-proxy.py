#!/usr/bin/env python3
"""
CodeIsland OMP proxy — monitors OMP session JSONL transcripts for activity.

Only tracks sessions that are ACTIVE (transcript modified in the last 5 min).
Sends SessionStart when a session becomes active, PostToolUse while working,
and Stop when it goes idle. After 5 min of inactivity the session is removed
from tracking (CodeIsland will clean it up from the panel).

Sessions that are already idle on startup are NOT tracked — only newly active
ones get reported.
"""
import json, os, glob, time, subprocess

OMP_SESSIONS_DIR = os.path.join(os.path.expanduser("~/.omp/agent/sessions"))
BRIDGE = os.path.expanduser("~/.codeisland/codeisland-bridge")
POLL_INTERVAL = 2
ACTIVE_THRESHOLD_S = 300   # transcript modified within last 5 min = active
STALE_TIMEOUT_S = 120       # 2 min of no activity = idle (send Stop)
REMOVE_TIMEOUT_S = 300      # 5 min idle = remove from tracking

def send(event, sid, cwd, **extra):
    payload = {"hook_event_name": event, "session_id": sid, "cwd": cwd,
               "_source": "pi", "source": "pi"}
    payload.update(extra)
    try:
        subprocess.run([BRIDGE, "--source", "pi"], input=json.dumps(payload),
                       capture_output=True, text=True, timeout=5)
    except Exception:
        pass

def get_active_sessions():
    """Find OMP sessions with recently modified JSONL transcripts."""
    sessions = {}
    if not os.path.isdir(OMP_SESSIONS_DIR):
        return sessions
    now = time.time()
    for d in os.listdir(OMP_SESSIONS_DIR):
        dir_path = os.path.join(OMP_SESSIONS_DIR, d)
        if not os.path.isdir(dir_path):
            continue
        jsonls = glob.glob(os.path.join(dir_path, "*.jsonl"))
        if not jsonls:
            continue
        latest = max(jsonls, key=lambda p: os.path.getmtime(p))
        mtime = os.path.getmtime(latest)
        # Only track sessions active in the last 5 min
        if (now - mtime) > ACTIVE_THRESHOLD_S:
            continue
        # Extract session ID from filename: timestamp_uuid.jsonl
        basename = os.path.basename(latest)
        parts = basename.replace(".jsonl", "").split("_", 1)
        sid = parts[1] if len(parts) > 1 else basename
        # Read cwd from JSONL
        cwd = ""
        try:
            result = subprocess.run(["grep", "-m1", '"cwd"', latest],
                                   capture_output=True, text=True, timeout=2)
            if result.stdout:
                _d = json.loads(result.stdout.strip())
                cwd = _d.get("cwd", "")
        except Exception:
            pass
        if not cwd:
            if d.startswith("-"):
                cwd = os.path.expanduser("~") + "/" + d[1:]
            else:
                cwd = os.path.expanduser("~/" + d)
        sessions[sid] = {"cwd": cwd, "mtime": mtime, "path": latest}
    return sessions

def main():
    tracked = {}  # {sid: {cwd, mtime, active, idle_since}}
    print("[omp-proxy] Started. Waiting for active sessions...", flush=True)

    while True:
        now = time.time()
        current = get_active_sessions()

        # Detect newly active sessions
        for sid, info in current.items():
            if sid not in tracked:
                tracked[sid] = {
                    "cwd": info["cwd"], "mtime": info["mtime"],
                    "active": True, "idle_since": 0
                }
                send("SessionStart", sid, info["cwd"])
                print("[omp-proxy] NEW active: {} cwd={}".format(
                    sid[:12], info["cwd"].split("/")[-1]), flush=True)
            else:
                if info["mtime"] > tracked[sid]["mtime"]:
                    tracked[sid]["mtime"] = info["mtime"]
                    if not tracked[sid]["active"]:
                        # Session became active again
                        tracked[sid]["active"] = True
                        tracked[sid]["idle_since"] = 0
                        send("SessionStart", sid, info["cwd"])
                    send("PostToolUse", sid, info["cwd"])

        # Detect idle and stale sessions
        for sid, info in list(tracked.items()):
            if info["active"] and (now - info["mtime"]) > STALE_TIMEOUT_S:
                send("Stop", sid, info["cwd"], last_assistant_message="")
                info["active"] = False
                info["idle_since"] = now
                print("[omp-proxy] IDLE: {}".format(sid[:12]), flush=True)

            # Remove sessions idle for too long
            if not info["active"] and info["idle_since"] and \
               (now - info["idle_since"]) > REMOVE_TIMEOUT_S:
                send("SessionEnd", sid, info["cwd"])
                del tracked[sid]
                print("[omp-proxy] REMOVED: {}".format(sid[:12]), flush=True)

            # Remove sessions no longer in current active list and already idle
            if sid not in current and not info["active"]:
                send("SessionEnd", sid, info["cwd"])
                del tracked[sid]
                print("[omp-proxy] REMOVED (gone): {}".format(sid[:12]), flush=True)

        time.sleep(POLL_INTERVAL)

if __name__ == "__main__":
    main()
