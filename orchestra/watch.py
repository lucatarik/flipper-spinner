#!/usr/bin/env python3
"""Watch what an opencode worker launched by delegate.py is doing.

Usage:
  orchestra/watch.py [LOG.jsonl | DIR]        live feed until the worker finishes
  orchestra/watch.py --status [LOG | DIR]     one-shot snapshot (progress, last actions, tokens)
  orchestra/watch.py --events [LOG | DIR]     milestones only, one line each (for Claude's Monitor)

Without a path, picks the most recent log under docs/agent-work/ (a DIR narrows the search).
"""
import argparse
import json
import os
import re
import sys
import time
from pathlib import Path

ROOT = Path.cwd()
STALL_SECONDS = 300
TEST_LINE = re.compile(
    r"^(Ran \d+ tests?.*|OK.*|FAILED.*|.*\b\d+ (passed|failed)\b.*|Tests?:.*)$", re.M)
QUIET_TOOLS = {"read", "glob", "grep", "list", "webfetch"}


OPENCODE_LOG = Path(os.environ.get("ORCHESTRA_OPENCODE_LOG",
                         Path.home() / ".local/share/opencode/log/opencode.log"))
ERR_LINE = re.compile(r'^timestamp=(\S+) level=ERROR .*?modelID=(\S+) session\.id=(\S+) small=false .*?error\.error="(.*)"$')


def provider_errors(session: str | None) -> list[tuple[str, str, str]]:
    """(timestamp, model, message) of provider errors opencode logged for this session.
    They never reach the JSON event stream: a rate-limited run just goes silent."""
    if not session or not OPENCODE_LOG.exists():
        return []
    with OPENCODE_LOG.open("rb") as fh:
        fh.seek(max(0, OPENCODE_LOG.stat().st_size - 4_000_000))
        tail = fh.read().decode("utf-8", "replace")
    out = []
    for line in tail.splitlines():
        if session in line and "level=ERROR" in line:
            m = ERR_LINE.match(line)
            if m and m.group(3) == session:
                out.append((m.group(1), m.group(2), m.group(4)))
    return out


def find_log(target: str | None) -> Path:
    if target and Path(target).is_file():
        return Path(target)
    base = Path(target) if target else ROOT / "docs/agent-work"
    logs = sorted(base.rglob("*.jsonl"), key=lambda p: p.stat().st_mtime)
    if not logs:
        sys.exit(f"no worker logs under {base}")
    return logs[-1]


def read_status(log: Path) -> dict:
    try:
        st = json.loads(log.with_suffix(".status.json").read_text())
    except (OSError, json.JSONDecodeError):
        return {"state": "unknown"}
    if st.get("state") == "running":
        try:
            os.kill(st["pid"], 0)
        except (ProcessLookupError, KeyError):
            st["state"] = "dead"  # delegate.py was killed before writing its final status
        except PermissionError:
            pass
    return st


def rel(path: str) -> str:
    try:
        return os.path.relpath(path, ROOT) if os.path.isabs(path) else path
    except ValueError:
        return path


def short(s: str, n: int = 90) -> str:
    s = " ".join(str(s).split())
    return s if len(s) <= n else s[: n - 1] + "…"


class Tracker:
    """Folds the event stream into a progress state and human-readable lines."""

    def __init__(self):
        self.t0 = self.t_last = None
        self.last_event = time.time()
        self.todos: list[dict] = []
        self.files: dict[str, int] = {}
        self.actions: list[str] = []
        self.last_test = None
        self.last_text = ""
        self.tokens = {"in": 0, "out": 0, "cache": 0}
        self.cost = 0.0
        self.errors: list[str] = []
        self.session = None

    def clock(self, ts_ms) -> str:
        if ts_ms is None:
            return "  --:--"
        if self.t0 is None:
            self.t0 = ts_ms
        self.t_last = ts_ms
        s = int((ts_ms - self.t0) / 1000)
        return f"{s // 60:3d}:{s % 60:02d}"

    def progress(self) -> str:
        if not self.todos:
            return "no todo list yet"
        done = sum(t.get("status") == "completed" for t in self.todos)
        now = next((t["content"] for t in self.todos if t.get("status") == "in_progress"), None)
        return f"{done}/{len(self.todos)} steps" + (f" · now: {short(now, 60)}" if now else "")

    def feed(self, ev: dict) -> list[tuple[str, str]]:
        """Return (kind, text) lines for this event. kind: milestone | detail."""
        self.last_event = time.time()
        self.session = self.session or ev.get("sessionID")
        clock = self.clock(ev.get("timestamp"))
        part = ev.get("part") or {}
        kind = ev.get("type")
        out = []

        if kind == "tool_use":
            tool = part.get("tool", "?")
            st = part.get("state") or {}
            inp = st.get("input") or {}
            failed = st.get("status") == "error"
            if tool == "todowrite":
                before = self.progress()
                self.todos = inp.get("todos") or []
                if self.progress() != before:
                    out.append(("milestone", f"{clock}  ☑ {self.progress()}"))
            elif tool in ("write", "edit", "patch", "multiedit"):
                path = rel(inp.get("filePath") or st.get("title") or "?")
                self.files[path] = self.files.get(path, 0) + 1
                verb = "created" if tool == "write" else "edited"
                line = f"{clock}  ✎ {verb} {path}" + ("  ✖ FAILED" if failed else "")
                out.append(("milestone", line))
            elif tool == "bash":
                cmd = inp.get("command", "")
                meta = st.get("metadata") or {}
                code = meta.get("exit")
                tests = [m.group(0) for m in TEST_LINE.finditer(str(st.get("output") or ""))]
                line = f"{clock}  $ {short(cmd, 70)}  → exit {code}"
                if tests:
                    self.last_test = f"{short(' · '.join(tests[-2:]), 60)} (exit {code})"
                    line += f"  [{self.last_test}]"
                is_milestone = bool(tests) or (code not in (0, None))
                out.append(("milestone" if is_milestone else "detail", line))
            else:
                target = inp.get("filePath") or inp.get("pattern") or inp.get("path") or st.get("title") or ""
                out.append(("detail" if tool in QUIET_TOOLS else "milestone",
                            f"{clock}  · {tool} {short(rel(str(target)), 70)}"))
            self.actions.append(out[-1][1].strip() if out else f"{tool}")
        elif kind == "text" and part.get("text"):
            self.last_text = part["text"]
            out.append(("detail", f"{clock}  💬 {short(part['text'], 110)}"))
        elif kind == "step_finish":
            t = part.get("tokens") or {}
            self.tokens["in"] += t.get("input", 0)
            self.tokens["out"] += t.get("output", 0)
            self.tokens["cache"] += (t.get("cache") or {}).get("read", 0)
            self.cost += part.get("cost") or 0
        elif kind == "error":
            msg = short(json.dumps(ev.get("error")), 200)
            self.errors.append(msg)
            out.append(("milestone", f"{clock}  ✖ ERROR {msg}"))
        return out


def events(log: Path):
    """Yield parsed events; follows the file while the worker is running."""
    with log.open() as fh:
        buf = ""
        while True:
            chunk = fh.readline()
            if chunk:
                buf += chunk
                if not buf.endswith("\n"):
                    continue  # partial line, wait for the rest
                line, buf = buf, ""
                try:
                    yield json.loads(line)
                except json.JSONDecodeError:
                    continue
            else:
                yield None  # idle tick


def _iso_ms(ts: str) -> float:
    from datetime import datetime
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp() * 1000
    except ValueError:
        return 0


def snapshot(log: Path) -> str:
    tr = Tracker()
    for line in log.read_text().splitlines():
        try:
            tr.feed(json.loads(line))
        except json.JSONDecodeError:
            pass
    st = read_status(log)
    if "started" in st:
        started, end = st["started"], st.get("finished") or time.time()
    else:  # older log without status file: use the event timestamps
        started, end = (tr.t0 or 0) / 1000, (tr.t_last or 0) / 1000
    idle = time.time() - log.stat().st_mtime
    state = st.get("state", "unknown")
    if state == "done":
        state = f"done (exit {st.get('exit')})"
    elif state == "running" and idle > STALL_SECONDS:
        state = f"running — ⚠ no activity for {int(idle // 60)} min"
    lines = [
        f"task:     {st.get('task', log.stem)}  [{st.get('model', '?')}]",
        f"state:    {state}   elapsed {int((end - started) // 60)}m{int((end - started) % 60):02d}s",
        f"progress: {tr.progress()}",
    ]
    for t in tr.todos:
        mark = {"completed": "x", "in_progress": ">"}.get(t.get("status"), " ")
        lines.append(f"            [{mark}] {short(t.get('content', ''), 70)}")
    lines += [
        f"files:    {', '.join(tr.files) or '-'}",
        f"tests:    {tr.last_test or '-'}",
        f"tokens:   in {tr.tokens['in']}  out {tr.tokens['out']}  cache {tr.tokens['cache']}  cost ${tr.cost:.4f}",
        "last actions:",
        *[f"   {a}" for a in tr.actions[-6:]],
    ]
    if tr.last_text:
        lines.append(f"last message: {short(tr.last_text, 200)}")
    for e in tr.errors:
        lines.append(f"ERROR: {e}")
    last_ms = tr.t_last or 0
    for ts, model, msg in provider_errors(tr.session):
        if _iso_ms(ts) >= last_ms:
            lines.append(f"PROVIDER ERROR {ts} [{model}]: {msg}"
                         + ("  ← worker likely stuck; stop it and resume with another model" if state.startswith("running") else ""))
    lines.append(f"log:      {rel(str(log))}")
    return "\n".join(lines)


def follow(log: Path, milestones_only: bool) -> int:
    tr = Tracker()
    color = sys.stdout.isatty() and not milestones_only
    dim, reset = ("\033[2m", "\033[0m") if color else ("", "")
    st = read_status(log)
    print(f"▶ watching {st.get('task', log.stem)} [{st.get('model', '?')}]  {rel(str(log))}", flush=True)
    warned = finishing = False
    seen_errors: set[tuple] = set()
    next_err_check = 0.0
    for ev in events(log):
        if ev is not None:
            warned = False
            for kind, text in tr.feed(ev):
                if kind == "milestone":
                    print(text, flush=True)
                elif not milestones_only:
                    print(f"{dim}{text}{reset}", flush=True)
            continue
        if finishing:
            summary = {"done": f"exit {st.get('exit')}", "dead": "delegate.py died",
                       "unknown": "no status file"}[st["state"]]
            print(f"■ finished: {summary} · {tr.progress()} · "
                  f"files {len(tr.files)} · tests {tr.last_test or '-'}", flush=True)
            return 0
        if read_status(log).get("state") in ("done", "dead", "unknown"):
            # one more pass: lines written just before the status flipped get read first
            finishing, st = True, read_status(log)
            continue
        if time.time() > next_err_check:
            next_err_check = time.time() + 15
            for err in provider_errors(tr.session):
                if err not in seen_errors and _iso_ms(err[0]) >= (tr.t0 or 0):
                    seen_errors.add(err)
                    print(f"✖ provider error [{err[1]}]: {short(err[2], 120)}", flush=True)
        idle = time.time() - tr.last_event
        if idle > STALL_SECONDS and not warned:
            print(f"⚠ no worker activity for {int(idle // 60)} min (still running)", flush=True)
            warned = True
        time.sleep(0.5)
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("target", nargs="?")
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--status", action="store_true")
    mode.add_argument("--events", action="store_true")
    args = ap.parse_args()
    log = find_log(args.target)
    if args.status:
        print(snapshot(log))
        return 0
    return follow(log, milestones_only=args.events)


if __name__ == "__main__":
    sys.exit(main())
