#!/usr/bin/env python3
"""
CodeIsland Codex proxy — monitors the Codex state database for thread activity.

Only tracks sessions that are ACTIVE (updated_at_ms or transcript mtime within
last 5 min). Sends SessionStart when a session becomes active, UserPromptSubmit
while working, and Stop when idle. After 5 min idle, the session is removed.

The ChatGPT desktop app's app-server doesn't fire hooks, so this proxy polls
the threads table to detect session activity.
"""
import json, os, sqlite3, subprocess, time

CODEX_HOME = os.environ.get("CODEX_HOME", os.path.expanduser("~/.codex"))
STATE_DB = os.path.join(CODEX_HOME, "state_5.sqlite")
BRIDGE = os.path.expanduser("~/.codeisland/codeisland-bridge")
POLL_INTERVAL = 2
ACTIVE_THRESHOLD_MS = 300000    # 5 min — only track recently active sessions
STALE_TIMEOUT_MS = 120000       # 2 min idle = send Stop
REMOVE_TIMEOUT_MS = 300000      # 5 min idle = remove from tracking

def send(event, sid, cwd, **extra):
    payload = {"hook_event_name": event, "session_id": sid, "cwd": cwd,
               "_source": "codex", "source": "codex"}
    payload.update(extra)
    try:
        subprocess.run([BRIDGE, "--source", "codex"], input=json.dumps(payload),
                       capture_output=True, text=True, timeout=5)
    except Exception:
        pass

def get_active_threads():
    """Get threads with recent activity (updated_at_ms within ACTIVE_THRESHOLD)."""
    try:
        conn = sqlite3.connect("file:{}?mode=ro".format(STATE_DB), uri=True)
        conn.row_factory = sqlite3.Row
        now_ms = int(time.time() * 1000)
        cutoff = now_ms - ACTIVE_THRESHOLD_MS
        rows = conn.execute(
            "SELECT id, rollout_path, cwd, updated_at_ms, title, model "
            "FROM threads WHERE archived = 0 AND updated_at_ms > ? "
            "ORDER BY updated_at_ms DESC LIMIT 50",
            (cutoff,)
        ).fetchall()
        conn.close()
        return rows
    except Exception:
        return []

def transcript_mtime_ms(rollout_path):
    try:
        return int(os.path.getmtime(rollout_path) * 1000)
    except Exception:
        return 0

def main():
    tracked = {}
    print("[codex-proxy] Started. Waiting for active sessions...", flush=True)

    while True:
        now_ms = int(time.time() * 1000)
        rows = get_active_threads()
        current = {}
        for row in rows:
            tid = row["id"]
            db_updated = row["updated_at_ms"]
            ts = transcript_mtime_ms(row["rollout_path"])
            last_activity = max(db_updated, ts)
            current[tid] = {
                "cwd": row["cwd"],
                "title": row["title"] or "",
                "model": row["model"] or "gpt-5.5",
                "last_activity": last_activity,
            }

        # Detect newly active sessions
        for tid, info in current.items():
            if tid not in tracked:
                tracked[tid] = {
                    "cwd": info["cwd"], "last_activity": info["last_activity"],
                    "active": True, "idle_since": 0
                }
                send("SessionStart", tid, info["cwd"], model=info["model"])
                send("UserPromptSubmit", tid, info["cwd"],
                     model=info["model"], prompt=info["title"])
                print("[codex-proxy] NEW active: {} cwd={}".format(
                    tid[:12], info["cwd"].split("/")[-1]), flush=True)
            else:
                if info["last_activity"] > tracked[tid]["last_activity"]:
                    tracked[tid]["last_activity"] = info["last_activity"]
                    if not tracked[tid]["active"]:
                        tracked[tid]["active"] = True
                        tracked[tid]["idle_since"] = 0
                        send("SessionStart", tid, info["cwd"], model=info["model"])
                    send("UserPromptSubmit", tid, info["cwd"],
                         model=info["model"], prompt=info["title"])

        # Detect idle and stale sessions
        for tid, info in list(tracked.items()):
            if info["active"] and (now_ms - info["last_activity"]) > STALE_TIMEOUT_MS:
                send("Stop", tid, info["cwd"], last_assistant_message="")
                info["active"] = False
                info["idle_since"] = now_ms
                print("[codex-proxy] IDLE: {}".format(tid[:12]), flush=True)

            # Remove sessions idle for too long or no longer active
            should_remove = False
            if not info["active"] and info["idle_since"] and \
               (now_ms - info["idle_since"]) > REMOVE_TIMEOUT_MS:
                should_remove = True
            if tid not in current and not info["active"]:
                should_remove = True

            if should_remove:
                send("SessionEnd", tid, info["cwd"])
                del tracked[tid]
                print("[codex-proxy] REMOVED: {}".format(tid[:12]), flush=True)

        time.sleep(POLL_INTERVAL)

if __name__ == "__main__":
    main()
