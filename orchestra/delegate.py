#!/usr/bin/env python3
"""Dispatch a task brief to an opencode worker and print a compact summary.

The full event stream is kept on disk so the orchestrator only reads what it needs.

Usage:
  orchestra/delegate.py BRIEF.md [--model provider/model] [--session ses_...|last]
                        [--message "extra instructions"] [--timeout SECONDS]

With --session the same worker session is resumed (e.g. for a correction cycle);
--message carries the findings and the brief, if given, only decides where logs go.
"""
import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path.cwd()  # run from the project root
DEFAULT_MODEL = os.environ.get("ORCHESTRA_WORKER_MODEL", "opencode/big-pickle")
# free models tried in order when the current one is rate-limited (they have separate quotas)
FALLBACK_MODELS = os.environ.get(
    "ORCHESTRA_FALLBACK_MODELS",
    "opencode/big-pickle,opencode/nemotron-3-ultra-free,opencode/ling-3.0-flash-fin-free,"
    "opencode/mimo-v2.6-flash-free").split(",")
RATE_LIMIT_MARKERS = ("rate limit", "429", "too many requests", "quota")
# errors that end the run but say nothing about the task: worth resuming on another model
TRANSIENT_MARKERS = ("503", "502", "504", "overloaded", "temporarily", "cannot connect",
                     "socket connection was closed", "upstream error", "timeout")
RESUME_PROMPT = ("Continue exactly where you stopped: the model provider failed (rate limit or outage) "
                 "for the previous model, so you were switched to another one. Do not redo finished steps; "
                 "check your todo list and the files you already wrote, then carry on.")

sys.path.insert(0, str(Path(__file__).resolve().parent))
from watch import _iso_ms, provider_errors  # noqa: E402  (sibling script)


def pid_alive(pid) -> bool:
    try:
        os.kill(int(pid), 0)
        return True
    except (ProcessLookupError, TypeError, ValueError):
        return False
    except PermissionError:
        return True


def first_session(log: Path) -> str | None:
    with log.open() as fh:
        for line in fh:
            try:
                sid = json.loads(line).get("sessionID")
            except json.JSONDecodeError:
                continue
            if sid:
                return sid
    return None


def runs(log_dir: Path, stem: str = "*") -> list[dict]:
    """Every delegate run logged in log_dir (optionally of one brief), newest START first."""
    out = []
    for log in log_dir.glob(f"{stem}.*.jsonl"):
        try:
            st = json.loads(log.with_suffix(".status.json").read_text())
        except (OSError, json.JSONDecodeError):
            st = {}  # logs from before status files existed
        out.append({
            "log": log,
            "started": st.get("started") or log.stat().st_mtime,
            "running": st.get("state") == "running" and pid_alive(st.get("pid")),
            "session": first_session(log),
        })
    return sorted(out, key=lambda r: r["started"], reverse=True)


def last_session_for(brief: Path) -> str | None:
    """Session id of the most recently STARTED run of this brief (logs live beside it)."""
    return next((r["session"] for r in runs(brief.resolve().parent, brief.stem) if r["session"]), None)


def session_exists(session: str) -> bool:
    try:
        out = subprocess.run(["opencode", "session", "list", "--format", "json"],
                             capture_output=True, text=True, timeout=60).stdout
        return any(s.get("id") == session for s in json.loads(out))
    except (OSError, subprocess.TimeoutExpired, json.JSONDecodeError):
        return True  # can't check: let opencode decide rather than block the run


def run_worker(cmd: list[str], log_path: Path, args, append: bool = False) -> int | str:
    """Run opencode into log_path. Returns its exit code, "timeout", "startup-hang"
    (no event at all within --startup-timeout s) or "rate-limited" (the provider refused
    the session's requests: opencode then hangs silently instead of exiting)."""
    run_start_ms = time.time() * 1000 - 5000  # tolerance: log timestamps may be coarser than ours
    deadline = time.time() + args.timeout
    with log_path.open("a" if append else "w") as log:
        start_size = log_path.stat().st_size
        proc = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT, cwd=args.dir)
        boot_deadline = time.time() + args.startup_timeout
        next_check = time.time() + 10
        while proc.poll() is None:
            if time.time() > deadline:
                return stop(proc, "timeout")
            if boot_deadline and time.time() > boot_deadline:
                if log_path.stat().st_size == start_size:
                    return stop(proc, "startup-hang")
                boot_deadline = 0  # it started: no more startup checks
            if time.time() > next_check:
                next_check = time.time() + 10
                session = first_session(log_path)
                for ts, _model, msg in provider_errors(session):
                    if _iso_ms(ts) >= run_start_ms and any(m in msg.lower() for m in RATE_LIMIT_MARKERS):
                        print(f"warning:  provider: {msg}", flush=True)
                        return stop(proc, "rate-limited")
            time.sleep(1)
        if proc.returncode != 0 and transient_error_since(log_path, start_size):
            return "provider-error"
        return proc.returncode


def transient_error_since(log_path: Path, offset: int) -> bool:
    """True when this attempt's part of the log ends in a provider-side error event."""
    with log_path.open() as fh:
        fh.seek(offset)
        errors = [line for line in fh if '"type":"error"' in line]
    return bool(errors) and any(m in errors[-1].lower() for m in TRANSIENT_MARKERS)


def stop(proc: subprocess.Popen, reason: str) -> str:
    proc.kill()
    proc.wait()
    return reason


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("brief", nargs="?", type=Path)
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--session")
    ap.add_argument("--message", default="")
    ap.add_argument("--timeout", type=int, default=1800)
    ap.add_argument("--startup-timeout", type=int, default=120,
                    help="restart once if opencode writes no event at all within this many seconds")
    ap.add_argument("--dir", type=Path, default=ROOT)
    args = ap.parse_args()

    if not args.brief and not args.session:
        ap.error("need BRIEF.md and/or --session")
    if args.session and not args.message:
        ap.error("--session needs --message")
    # Concurrency guards: never two opencode processes on the same brief or session,
    # they would interleave one conversation and write the same files.
    if args.brief:
        busy = [r for r in runs(args.brief.resolve().parent, args.brief.stem) if r["running"]]
        if busy:
            ap.error(f"{args.brief} is already being worked on ({os.path.relpath(busy[0]['log'], ROOT)}); "
                     "wait for it to finish (orchestra/watch.py) or stop it first")
    if args.session == "last":
        if not args.brief:
            ap.error("--session last needs BRIEF.md")
        args.session = last_session_for(args.brief)
        if not args.session:
            ap.error(f"no previous run of {args.brief} found")
    if args.session:
        if not session_exists(args.session):
            ap.error(f"unknown opencode session {args.session} (see: opencode session list)")
        work = ROOT / "docs/agent-work"
        live = [r for d in {work, *(p.parent for p in work.rglob("*.jsonl"))}
                for r in runs(d) if r["running"] and r["session"] == args.session]
        if live:
            ap.error(f"session {args.session} is still running ({os.path.relpath(live[0]['log'], ROOT)})")

    if args.brief and args.session:
        # correction cycle: same session already has the brief, keep logs beside it
        prompt, files = "", []
        log_dir = args.brief.resolve().parent
        task = f"{args.brief.stem}.fix"
    elif args.brief:
        prompt = (
            f"Execute the task brief in {args.brief} exactly. Read it first, "
            "follow AGENTS.md, and write the report to the path it names.\n"
        )
        files = ["-f", str(args.brief)]
        log_dir = args.brief.resolve().parent
        task = args.brief.stem
    else:
        prompt, files, log_dir, task = "", [], ROOT / "docs/agent-work", "resume"
    prompt += args.message

    log_dir.mkdir(parents=True, exist_ok=True)
    log_path = log_dir / f"{task}.{time.strftime('%Y%m%d-%H%M%S')}.jsonl"

    cmd = ["opencode", "run", "-m", args.model, "--format", "json", "--auto",
           "--dir", str(args.dir), *files]
    if args.session:
        cmd += ["--session", args.session]
    cmd += ["--", prompt]

    # status file lets orchestra/watch.py tell a running worker from a finished one
    status_path = log_path.with_suffix(".status.json")
    status = {"task": task, "model": args.model, "pid": os.getpid(),
              "started": time.time(), "state": "running", "exit": None}
    status_path.write_text(json.dumps(status))
    print(f"log:      {os.path.relpath(log_path, ROOT)}  (watch: orchestra/watch.py)", flush=True)

    started = status["started"]
    models = [args.model] + [m for m in FALLBACK_MODELS if m and m != args.model]
    exit_code = run_worker(cmd, log_path, args)
    for next_model in models[1:]:
        if exit_code not in ("startup-hang", "rate-limited", "provider-error"):
            break
        session = first_session(log_path)
        if exit_code == "startup-hang" or not session:
            # never got going: the run is empty, so the same prompt can start over
            print(f"warning:  no worker event in {args.startup_timeout}s, retrying with {next_model}", flush=True)
            retry = [c if c != cmd[cmd.index("-m") + 1] else next_model for c in cmd]
        else:
            print(f"warning:  {status['model']} {exit_code}, resuming {session} with {next_model}", flush=True)
            retry = ["opencode", "run", "-m", next_model, "--format", "json", "--auto",
                     "--dir", str(args.dir), "--session", session, "--", RESUME_PROMPT]
        status["model"] = next_model
        status_path.write_text(json.dumps(status))
        args.model = next_model
        exit_code = run_worker(retry, log_path, args, append=True)
    status.update(state="done", exit=exit_code, finished=time.time(), session=first_session(log_path))
    status_path.write_text(json.dumps(status))

    session, texts, tools, errors = None, [], {}, []
    tokens = {"input": 0, "output": 0, "reasoning": 0, "cache_read": 0}
    cost = 0.0
    for line in log_path.read_text().splitlines():
        try:
            ev = json.loads(line)
        except json.JSONDecodeError:
            continue
        session = session or ev.get("sessionID")
        part = ev.get("part") or {}
        kind = ev.get("type")
        if kind == "text" and part.get("text"):
            texts.append(part["text"])
        elif kind == "tool_use":
            name = part.get("tool", "?")
            tools[name] = tools.get(name, 0) + 1
        elif kind == "step_finish":
            t = part.get("tokens") or {}
            tokens["input"] += t.get("input", 0)
            tokens["output"] += t.get("output", 0)
            tokens["reasoning"] += t.get("reasoning", 0)
            tokens["cache_read"] += (t.get("cache") or {}).get("read", 0)
            cost += part.get("cost") or 0
        elif kind == "error":
            errors.append(json.dumps(ev.get("error"))[:400])

    print(f"model:    {args.model}")
    print(f"session:  {session}")
    print(f"exit:     {exit_code}  ({time.time() - started:.0f}s)")
    print(f"log:      {os.path.relpath(log_path, ROOT)}")
    print(f"tools:    {', '.join(f'{k}x{v}' for k, v in sorted(tools.items())) or '-'}")
    print(f"tokens:   {tokens}  cost=${cost:.4f}")
    for e in errors:
        print(f"ERROR:    {e}")
    print("--- worker final message ---")
    print(texts[-1][-3000:] if texts else "(none)")
    return 0 if exit_code == 0 and not errors else 1


if __name__ == "__main__":
    sys.exit(main())
