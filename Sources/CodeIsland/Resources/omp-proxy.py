#!/usr/bin/env python3
"""
CodeIsland OMP proxy — monitors OMP session JSONL transcripts for activity.

OMP sessions started before the CodeIsland extension was installed don't get
native hook events. This proxy polls the session transcript files for changes
and forwards events to the CodeIsland bridge, so they appear in the panel.
"""
import json, os, glob, time, subprocess

OMP_SESSIONS_DIR = os.path.join(os.path.expanduser("~/.omp/agent/sessions"))
BRIDGE = os.path.expanduser("~/.codeisland/codeisland-bridge")
POLL_INTERVAL = 2
STALE_TIMEOUT_S = 120  # 2 min

def send(event, sid, cwd, **extra):
    payload = {"hook_event_name": event, "session_id": sid, "cwd": cwd,
               "_source": "pi", "source": "pi"}
    payload.update(extra)
    try:
        subprocess.run([BRIDGE, "--source", "pi"], input=json.dumps(payload),
                       capture_output=True, text=True, timeout=5)
    except Exception:
        pass

def get_sessions():
    """Find all OMP session JSONL files with their mtime."""
    sessions = {}
    if not os.path.isdir(OMP_SESSIONS_DIR):
        return sessions
    for d in os.listdir(OMP_SESSIONS_DIR):
        dir_path = os.path.join(OMP_SESSIONS_DIR, d)
        if not os.path.isdir(dir_path):
            continue
        jsonls = glob.glob(os.path.join(dir_path, "*.jsonl"))
        if not jsonls:
            continue
        latest = max(jsonls, key=lambda p: os.path.getmtime(p))
        # Extract session ID from filename: timestamp_uuid.jsonl
        basename = os.path.basename(latest)
        parts = basename.replace(".jsonl", "").split("_", 1)
        sid = parts[1] if len(parts) > 1 else basename
        # Convert dir name (-Projects-DebugSwift) to path (~/Projects/DebugSwift)
        # Read cwd from the JSONL transcript (more accurate than guessing from dir name)
        cwd = ""
        try:
            import subprocess
            result = subprocess.run(["grep", "-m1", '"cwd"', latest],
                                   capture_output=True, text=True, timeout=2)
            if result.stdout:
                import json as _json
                _d = _json.loads(result.stdout.strip())
                cwd = _d.get("cwd", "")
        except Exception:
            pass
        if not cwd:
            # Fallback: guess from dir name (replace first dash with /)
            if d.startswith("-"):
                cwd = os.path.expanduser("~") + "/" + d[1:]
            else:
                cwd = os.path.expanduser("~/" + d)
        sessions[sid] = {
            "cwd": cwd,
            "mtime": os.path.getmtime(latest),
            "path": latest,
        }
    return sessions

def main():
    tracked = get_sessions()
    for sid, info in tracked.items():
        info["active"] = True
        send("SessionStart", sid, info["cwd"])
    print("[omp-proxy] Started. Sent SessionStart for {} sessions.".format(len(tracked)), flush=True)

    while True:
        now = time.time()
        current = get_sessions()

        for sid, info in current.items():
            cwd = info["cwd"]
            mtime = info["mtime"]

            if sid not in tracked:
                tracked[sid] = {"cwd": cwd, "mtime": mtime, "active": True}
                send("SessionStart", sid, cwd)
            else:
                prev_mtime = tracked[sid]["mtime"]
                if mtime > prev_mtime:
                    tracked[sid]["mtime"] = mtime
                    tracked[sid]["active"] = True
                    send("PostToolUse", sid, cwd)

        # Send Stop for stale sessions
        for sid, info in list(tracked.items()):
            if info["active"] and (now - info["mtime"]) > STALE_TIMEOUT_S:
                send("Stop", sid, info["cwd"], last_assistant_message="")
                info["active"] = False

        time.sleep(POLL_INTERVAL)

if __name__ == "__main__":
    main()
