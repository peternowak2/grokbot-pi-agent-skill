# pi-agent

[简体中文](README.md)

A Grok Bot skill that hands batch edits, scripts, data cleanup, and long drafts to the [Pi](https://github.com/earendil-works/pi) coding agent on the **same Linux machine** (default model `deepseek/deepseek-flash`). When a task finishes, the script POSTs only `{source, id, owner, state, exit_code}` to a webhook so the bot can wake up, verify, and report.

"Local" means the bot's Linux cloud computer, not a personal laptop. The task runner comes from [robbin/grokbot-local-agent](https://github.com/robbin/grokbot-local-agent) (MIT, Copyright 2026 Robbin Fan). This repo turns that into one install command and a skill you can drop onto a bot.

## What it does

1. The bot starts `pi-task` with its Shell tool's background mode. The task is stored under `~/.pi/tasks/<ID>/`.
2. Pi reads and writes files and runs commands in the directory you name. It cannot see the bot's chat, and it has no Gmail, X, or GitHub connectors.
3. On completion, if notification is configured, the runner sends metadata to a webhook routine. The prompt and the result stay on disk.
4. The bot reads that disk state, checks the diff, tests, or artifacts itself, tells the user, then `ack`s.

The webhook is a wakeup. Disk state is the source of truth. If a notice is missed, recover with `pending`. Do not rerun the task only because the notice did not arrive.

## Requirements

- A Grok Bot Linux computer, with a writable home directory for the current user. No sudo.
- Network access to nodejs.org and the npm registry during install.
- A DeepSeek account with balance. Pi reads `DEEPSEEK_API_KEY` from the environment.
- A bot that can trigger a routine from a webhook and store secrets as environment variables.

Pi needs Node.js 22.19 or newer. `install.sh` installs the official build into `~/.node22` when that directory does not already contain a new enough Node.

## Quick start

Run this on the bot's Linux computer.

### 1. Install

```bash
git clone https://github.com/peternowak2/grokbot-pi-agent-skill.git
cd grokbot-pi-agent-skill
bash install.sh
```

The script:

- downloads Node.js 22.19+ into `~/.node22` and checks SHA256, if a new enough build is not already there
- runs `npm install -g --prefix ~/.local @earendil-works/pi-coding-agent`
- copies `pi-call` / `pi-task` to `~/tools/pi-call`
- if `/home/box/agent-data/workflows` exists, copies the skill to `/home/box/agent-data/workflows/pi-agent/SKILL.md`

Run `bash install.sh` again any time. Node and Pi are left in place when they already work, and the scripts are refreshed from this clone.

Preview without downloads: `bash install.sh --dry-run`.

### 2. Add the DeepSeek key

On the bot that will call Pi, add a bot secret (environment variable). Do not put the value in the repo, a prompt, or a terminal log.

| Name | Value |
| --- | --- |
| `DEEPSEEK_API_KEY` | DeepSeek API key ([platform.deepseek.com](https://platform.deepseek.com/)) |

Start a new turn so the shell can see it. The installer prints `set` or `not set` and never prints the value.

### 3. Create the webhook routine

1. Create a webhook-triggered routine, for example named "Pi task completion".
2. Paste the instructions from [`routines/pi-task-notify.md`](routines/pi-task-notify.md). After install, the same file is at `~/tools/pi-call/pi-task-notify.md`.
3. Replace `YOUR_AGENT_ID` with this bot's id: the directory name in `/home/box/agent-data/agents/<your-bot-id>/profile.json`.
4. Add two more bot secrets:
   - `PI_NOTIFY_URL` — the routine's webhook URL
   - `PI_NOTIFY_SECRET` — the raw Bearer token, with no `Bearer ` prefix

Both variables must be set or the runner skips the POST. `PI_NOTIFY_OFF=1` turns notification off for a while.

## Usage example

```bash
export PATH="$HOME/.node22/bin:$HOME/.local/bin:$PATH"
test -n "$DEEPSEEK_API_KEY" && echo key-ok    # do not print the key

~/tools/pi-call/pi-task run <cwd> "<prompt>" --session <name> --owner <your-bot-id>
```

For example, ask Pi to write a short note in a temp directory (replace `<your-bot-id>` with the directory name above):

```bash
~/tools/pi-call/pi-task run /tmp/pi-demo \
  "Create notes.md with three bullets about idempotent shell scripts. List files you changed and a one-line conclusion." \
  --session demo-notes --owner <your-bot-id>
```

For anything longer than a minute or two, use the Shell tool's background mode, not `nohup` or `&`. Keep the first line, `TASK <ID>`.

When it finishes:

```bash
~/tools/pi-call/pi-task pending --owner <your-bot-id>
~/tools/pi-call/pi-task status <ID>
# Read result.md, the diff, or the tests yourself, tell the user, then ack.
~/tools/pi-call/pi-task ack <ID> --owner <your-bot-id>
```

Short synchronous work: `~/tools/pi-call/pi-run <cwd> "<prompt>" --session <name>`.

Exit codes: `0` done, `1` failed, `2` usage, `124` timeout, `130` cancelled. See `~/tools/pi-call/pi-task --help` for the other subcommands.

## Other bots on the same box

Node, Pi, and `~/tools/pi-call` live in the OS user's home. Other bots running as that same user do not need a second install. They do need to:

1. See the skill (once is enough when the workflow directory is shared; otherwise copy `skills/pi-agent/SKILL.md` into each bot's skill store).
2. Have `DEEPSEEK_API_KEY` in their environment (their own bot secret, or a variable already injected on the box).
3. Pass **their own** `--owner <your-bot-id>` when they dispatch work.

The webhook routine belongs to the bot that configured notification. For another bot's task it forwards the id, owner, and state. It does not verify or `ack` on their behalf. The owning bot runs `pending --owner`, checks the result, and `ack`s. Do not drop `--owner` to acknowledge someone else's task.

If a bot runs as a different OS user, run `bash install.sh` again as that user.

## Limitations

- The DeepSeek account needs balance (a top-up). A key with no credit cannot finish a call.
- The webhook routine is created by hand in the bot UI. The installer does not create it and does not write the URL or token.
- Pi's reply is a claim. The bot has to read the artifacts before reporting them to the user.
- The working directory is not a sandbox. Do not use `/` or all of home, and do not delegate sending, pushing, deploying, or deleting important files.
- Notices can be late or lost. Use `pending` to find unreported tasks. A missed notice is not a reason to rerun.
- This is a second pair of hands on the same cloud computer, not an isolated long-running worker.

## Troubleshooting

| What you see | What to do |
| --- | --- |
| `pi` not found, or exit 127 | `export PATH="$HOME/.node22/bin:$HOME/.local/bin:$PATH"`, then `pi --version` |
| `No API key found` | `DEEPSEEK_API_KEY` is not in this process. Add it as a bot secret and start a new turn. Do not read `~/.pi/agent/auth.json`, and do not have the bot run `/login` for you |
| Node is too old | Remove the unqualified `~/.node22` and run `bash install.sh` again. Pi needs 22.19+ |
| Timeout (exit 124) | Split the work, or raise `--timeout` (default 300 seconds; `0` disables it) |
| No webhook | Confirm both `PI_NOTIFY_*` variables report `set` (do not print the values) and the routine is enabled. The result is still under `~/.pi/tasks/<ID>/`; report it with `pending` |
| Session already has a running task | `status` / `cancel`, or pick another session name |
| Unsure the install finished | Run `bash install.sh` again. It is idempotent |

## Layout

| Path | Purpose |
| --- | --- |
| `install.sh` | One-command install |
| `skills/pi-agent/SKILL.md` | The bot skill |
| `bin/` | `pi-call` / `pi-task` from upstream |
| `routines/pi-task-notify.md` | Webhook routine template |
| `NOTICE` | Upstream copyright and MIT terms |

## Credit

The task scripts, on-disk records, and webhook notify flow come from Robbin Fan's [grokbot-local-agent](https://github.com/robbin/grokbot-local-agent) (Copyright 2026 Robbin Fan, MIT). Upstream copyright notices are kept; see [NOTICE](NOTICE).

Pi itself is [@earendil-works/pi-coding-agent](https://www.npmjs.com/package/@earendil-works/pi-coding-agent) ([earendil-works/pi](https://github.com/earendil-works/pi)).

The rest of this repository is [MIT](LICENSE), Copyright 2026 peternowak2.
