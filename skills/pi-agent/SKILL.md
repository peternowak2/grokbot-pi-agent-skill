---
name: pi-agent
description: >-
  Use when a bot wants to hand heavier work (batch file edits, data cleanup,
  scripts/coding, long drafts, research, or a second model's opinion) to the Pi
  coding agent installed on the shared box, then verify and report the result.
---
# Delegate to Pi on the shared box

Pi is a CLI coding agent installed on the shared Linux box (from https://github.com/robbin/grokbot-local-agent), not on the user's own computer. Default model: `deepseek/deepseek-flash` with high thinking, using the user's own DeepSeek account (`DEEPSEEK_API_KEY`). Scripts: `~/tools/pi-call/`.

Reply to the user in their language.

## Before the first call in a session

```bash
export PATH=$HOME/.node22/bin:$HOME/.local/bin:$PATH
test -n "$DEEPSEEK_API_KEY" && echo key-ok   # never print the value
```
If `key-ok` doesn't print, Pi can't authenticate from your shell: tell the user (or the bot that set Pi up) instead of trying to log in or read `~/.pi/agent/auth.json`.

Your owner ID is the directory name under `/home/box/agent-data/agents/` that contains your `profile.json`. Always pass it as `--owner`.

## What to delegate
- Delegate: batch edits, data cleanup, format conversion, small programs/scripts/tests, long research or first drafts, explicit requests for Pi or a second opinion.
- Keep yourself: short questions, connector actions (Gmail, X, GitHub, etc.; Pi has none of them), anything needing user approval (sending, publishing, pushing, deploying, deleting important files), and reporting to the user.

## Workflow
1. Pick a narrow working directory (a project folder or `/tmp/<task-name>`), never `/` or all of home. It is not a sandbox.
2. Pick a short English kebab-case session name; reuse it for follow-ups.
3. Pick output paths (default `/tmp/pi-out/<session>/`, or the real project location).
4. Write a short, self-contained prompt: goal, background (Pi can't see your chat), input paths, output paths, acceptance criteria, and ask it to list files changed plus a short conclusion.
5. Longer work (more than a minute or two): run in the Shell tool's background mode (not nohup/&):
   ```text
   ~/tools/pi-call/pi-task run <cwd> "<prompt>" --session <name> --owner <YOUR_AGENT_ID> [--timeout sec] [--no-write] [--no-web]
   ```
   Keep the first stdout line (`TASK <ID>`). Exit codes: 0 done, 1 failed, 2 usage, 124 timeout, 130 cancelled.
   Short synchronous work: `~/tools/pi-call/pi-run <cwd> "<prompt>" --session <name> [--timeout sec]`.
   Model override / read-only: `~/tools/pi-call/pi-call.mjs <cwd> deepseek/deepseek-v4-pro "<prompt>" --thinking high [--allow-write] [--no-web] [--session <name>]`.
6. Completion notice: if `PI_NOTIFY_URL`/`PI_NOTIFY_SECRET` are set, a finished task POSTs `{source, id, owner, state, exit_code}` to a webhook routine. That routine belongs to whichever bot set up Pi; for tasks owned by another bot it forwards the ID to that owner. So on any wake where you had delegated work, run `~/tools/pi-call/pi-task pending --owner <YOUR_AGENT_ID>` yourself; disk state is the source of truth, never rerun just because a notice was missed.
7. Verify: Pi's reply is a claim. Read the artifacts / diff / test output before reporting. Then `~/tools/pi-call/pi-task ack <ID> --owner <YOUR_AGENT_ID>`.
8. Follow-ups: `~/tools/pi-call/pi-task reply <ID> "<changes>"` (keeps session, cwd, owner).

Other commands: `status <ID>`, `log <ID> [-n 30]`, `list [--all] [--owner ID]`, `cancel <ID>`. Records: `~/.pi/tasks/<ID>/` (status.json, events.jsonl, result.md, prompt-N.txt).

## Boundaries
- Never ack another bot's task or drop the `--owner` filter to bypass a mismatch.
- Never let Pi (or yourself) read or print `~/.pi/agent/auth.json`, secret files, or key env vars.
- Don't delegate pushes, deploys, production/DNS changes, external messages or email, or deleting important files.
- Use quota purposefully; at most one or two retries, with the user's OK, then take over and explain.
- Tell the user what Pi did and what you checked yourself.

## Troubleshooting
- `pi` not found / exit 127: fix PATH as above.
- "No API key found": the key isn't in your environment; report it, don't log in yourself.
- Timeout: split the work or raise `--timeout`.
