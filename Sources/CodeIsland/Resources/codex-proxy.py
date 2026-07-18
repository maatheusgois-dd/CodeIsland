#!/usr/bin/env python3
"""
CodeIsland Codex proxy — monitors the Codex state database for thread activity.

The ChatGPT desktop app's app-server doesn't fire hooks (only the CLI/TUI does),
so we poll the threads table's updated_at_ms AND the JSONL transcript file size
to detect session activity and forward events to the CodeIsland bridge.

Installed by ConfigInstaller as a LaunchAgent at
~/Library/LaunchAgents/com.codeisland.codex-proxy.plist.
"""
import json, os, sqlite3, subprocess, time

CODEX_HOME = os.environ.get("CODEX_HOME", os.path.expanduser("~/.codex"))
STATE_DB = os.path.join(CODEX_HOME, "state_5.sqlite")
BRIDGE = os.path.expanduser("~/.codeisland/codeisland-bridge")
POLL_INTERVAL = 2
STALE_TIMEOUT_MS = 120000  # 2 min — Codex can go 60s+ between DB updates while working

def send(event, sid, cwd, **extra):
    payload = {"hook_event_name": event, "session_id": sid, "cwd": cwd,
               "_source": "codex", "source": "codex"}
    payload.update(extra)
    try:
        subprocess.run([BRIDGE, "--source", "codex"], input=json.dumps(payload),
                       capture_output=True, text=True, timeout=5)
    except Exception:
        pass

def get_threads():
    try:
        conn = sqlite3.connect("file:{}?mode=ro".format(STATE_DB), uri=True)
        conn.row_factory = sqlite3.Row
        rows = conn.execute(
            "SELECT id, rollout_path, cwd, created_at_ms, updated_at_ms, title, model "
            "FROM threads WHERE archived = 0 ORDER BY updated_at_ms DESC LIMIT 50"
        ).fetchall()
        conn.close()
        return rows
    except Exception:
        return []

def transcript_activity_ts(rollout_path):
    """Check the JSONL transcript file modification time as a secondary activity signal."""
    try:
        return int(os.path.getmtime(rollout_path) * 1000)
    except Exception:
        return 0

def main():
    tracked = {}
    for row in get_threads():
        tracked[row["id"]] = {
            "updated_at_ms": row["updated_at_ms"],
            "transcript_ts": transcript_activity_ts(row["rollout_path"]),
            "cwd": row["cwd"], "active": False
        }
    print("[codex-proxy] Started. Tracking {} threads.".format(len(tracked)), flush=True)

    while True:
        now_ms = int(time.time() * 1000)
        for row in get_threads():
            tid = row["id"]
            cwd = row["cwd"]
            updated = row["updated_at_ms"]
            title = row["title"] or ""
            model = row["model"] or "gpt-5.5"
            transcript_ts = transcript_activity_ts(row["rollout_path"])

            if tid not in tracked:
                tracked[tid] = {
                    "updated_at_ms": updated, "transcript_ts": transcript_ts,
                    "cwd": cwd, "active": True
                }
                send("SessionStart", tid, cwd, model=model)
                send("UserPromptSubmit", tid, cwd, model=model, prompt=title)
            else:
                prev_db = tracked[tid]["updated_at_ms"]
                prev_ts = tracked[tid]["transcript_ts"]
                if updated > prev_db or transcript_ts > prev_ts:
                    tracked[tid]["updated_at_ms"] = updated
                    tracked[tid]["transcript_ts"] = transcript_ts
                    tracked[tid]["active"] = True
                    send("UserPromptSubmit", tid, cwd, model=model, prompt=title)

        # Send Stop for sessions inactive for STALE_TIMEOUT_MS
        # Use the most recent of DB update and transcript mtime
        for tid, info in list(tracked.items()):
            last_activity = max(info["updated_at_ms"], info["transcript_ts"])
            if info["active"] and (now_ms - last_activity) > STALE_TIMEOUT_MS:
                send("Stop", tid, info["cwd"], last_assistant_message="")
                info["active"] = False

        time.sleep(POLL_INTERVAL)

if __name__ == "__main__":
    main()
