# pi-agent

[English](README.en.md)

Grok Bot 技能：把批量改文件、写脚本、整理数据和长文起草交给**同一台 Linux 机器**上的 [Pi](https://github.com/earendil-works/pi) 编程代理（默认模型 `deepseek/deepseek-flash`）。任务结束后，脚本只把 `{source, id, owner, state, exit_code}` POST 到 webhook，唤醒 Bot 去核查并汇报。

这里的「本地」是 Bot 的 Linux 云电脑，不是用户自己的笔记本。实现来自 [robbin/grokbot-local-agent](https://github.com/robbin/grokbot-local-agent)（MIT，Copyright 2026 Robbin Fan）。本仓库把它收成一条安装命令和一份可直接装上的技能。

## 它做什么

1. Bot 用 Shell 的后台模式运行 `pi-task`。任务记在 `~/.pi/tasks/<ID>/`。
2. Pi 在指定目录里读写文件、跑命令。它看不到 Bot 的对话，也没有 Gmail / X / GitHub 这类连接器。
3. 任务结束时，若配置了通知，向 webhook 例行任务发送完成元数据（不含提示词和结果）。
4. Bot 醒来后读磁盘上的结果，自己核对 diff / 测试 / 产物，向用户汇报，再 `ack`。

通知只是为了尽快唤醒。磁盘记录才是事实来源。通知丢了，用 `pending` 补报，不要因此重跑。

## 环境要求

- Grok Bot 的 Linux 云电脑，当前用户可写家目录（不需要 sudo）。
- 能访问 nodejs.org 和 npm registry（安装 Node 与 Pi 时）。
- 一个有余额的 DeepSeek 账号。Pi 从环境变量 `DEEPSEEK_API_KEY` 读密钥。
- Bot 支持把 webhook 当作例行任务的触发器，并能把密钥存成 bot secret。

Pi 需要 Node.js 22.19 或更新。`install.sh` 会在 `~/.node22` 里安装官方二进制（已有合格版本则跳过）。

## 三步开始

在 Bot 的 Linux 电脑上：

### 1. 安装

```bash
git clone https://github.com/peternowak2/grokbot-pi-agent-skill.git
cd grokbot-pi-agent-skill
bash install.sh
```

脚本会：

- 若 `~/.node22` 里还没有 Node.js 22.19+，下载官方包并校验 SHA256
- `npm install -g --prefix ~/.local @earendil-works/pi-coding-agent`
- 把 `pi-call` / `pi-task` 装到 `~/tools/pi-call`
- 若 `/home/box/agent-data/workflows` 已存在，把技能复制到 `/home/box/agent-data/workflows/pi-agent/SKILL.md`

可以再跑一次 `bash install.sh`。已装好的 Node 和 Pi 会跳过，脚本会覆盖成仓库里的脚本副本。

只看计划、不下载：`bash install.sh --dry-run`。

### 2. 添加 DeepSeek 密钥

在**将要调用 Pi 的那个 Bot** 上添加 bot secret（环境变量），不要把值写进仓库、提示词或终端记录：

| 名字 | 内容 |
| --- | --- |
| `DEEPSEEK_API_KEY` | DeepSeek API key（[platform.deepseek.com](https://platform.deepseek.com/)） |

新开一轮对话后，密钥才会出现在 Bot 的 Shell 里。安装脚本只会打印 `set` 或 `not set`，不会打印值。

### 3. 创建 webhook 例行任务

1. 新建一个由 webhook 触发的例行任务，名称例如「Pi task completion」。
2. 把 [`routines/pi-task-notify.md`](routines/pi-task-notify.md) 里的说明贴进去（安装后同样位于 `~/tools/pi-call/pi-task-notify.md`）。
3. 把其中的 `YOUR_AGENT_ID` 换成这个 Bot 的 id：`/home/box/agent-data/agents/<your-bot-id>/profile.json` 的目录名。
4. 再添加两个 bot secret：
   - `PI_NOTIFY_URL`：该例行任务的 webhook URL
   - `PI_NOTIFY_SECRET`：原始 Bearer token，不要带 `Bearer ` 前缀

两个变量都在时，任务结束才会发通知。`PI_NOTIFY_OFF=1` 可临时关掉。

## 使用示例

```bash
export PATH="$HOME/.node22/bin:$HOME/.local/bin:$PATH"
test -n "$DEEPSEEK_API_KEY" && echo key-ok    # 不要打印密钥本身

~/tools/pi-call/pi-task run <cwd> "<prompt>" --session <name> --owner <your-bot-id>
```

例如，让 Pi 在临时目录写一份短笔记（把 `<your-bot-id>` 换成上面的目录名）：

```bash
~/tools/pi-call/pi-task run /tmp/pi-demo \
  "Create notes.md with three bullets about idempotent shell scripts. List files you changed and a one-line conclusion." \
  --session demo-notes --owner <your-bot-id>
```

长任务用 Bot Shell 自带的后台模式，不要用 `nohup` 或 `&`。记下第一行 `TASK <ID>`。

结束后：

```bash
~/tools/pi-call/pi-task pending --owner <your-bot-id>
~/tools/pi-call/pi-task status <ID>
# 自己读 result.md、diff 或测试输出，向用户汇报之后再 ack
~/tools/pi-call/pi-task ack <ID> --owner <your-bot-id>
```

短的同步调用：`~/tools/pi-call/pi-run <cwd> "<prompt>" --session <name>`。

退出码：`0` 完成，`1` 失败，`2` 用法错误，`124` 超时，`130` 取消。更多子命令见 `~/tools/pi-call/pi-task --help`。

## 同一台机器上的其他 Bot

Node、Pi 和 `~/tools/pi-call` 装在系统用户的家目录里。同一用户下的其他 Bot 不用再装一遍，只要：

1. 技能对它们可见（工作流目录是共享的就装一次；各自有技能目录则各复制一份 `skills/pi-agent/SKILL.md`）。
2. 它们的环境里能读到 `DEEPSEEK_API_KEY`（各自的 bot secret，或这台机器上已经注入的变量）。
3. 派活时带上**自己的** `--owner <your-bot-id>`。

Webhook 例行任务属于当初安装并配置通知的那个 Bot。别人的任务它只转发 id / owner / state，不替别人核查或 `ack`。被点名的 Bot 自己跑 `pending --owner`，核对之后再 `ack`。不要丢掉 `--owner` 去确认别人的任务。

若 Bot 使用不同的系统用户，就在那个用户下再执行一次 `bash install.sh`。

## 限制

- DeepSeek 账号需要有余额（要充值）。只有密钥、没有额度时，调用会失败。
- Webhook 例行任务要在 Bot 界面里手工创建。安装脚本不会创建它，也不会写入 URL 或 token。
- Pi 的回复是声明，不是证据。Bot 必须自己看过产物再向用户汇报。
- 工作目录不是沙箱。不要把 cwd 设成 `/` 或整个家目录，也不要让 Pi 发送消息、推送、部署或删除重要文件。
- 通知可能迟到或丢失。用 `pending` 找回未汇报的任务，不要因为没收到通知就重跑。
- 这是同一台云电脑上的第二双手，不是隔离的长期任务服务。

## 排错

| 现象 | 处理 |
| --- | --- |
| `pi` 找不到，或退出码 127 | `export PATH="$HOME/.node22/bin:$HOME/.local/bin:$PATH"`，再执行 `pi --version` |
| `No API key found` | `DEEPSEEK_API_KEY` 不在这个进程的环境里。把它加为 bot secret，新开一轮。不要去读 `~/.pi/agent/auth.json`，也不要让 Bot 代你 `/login` |
| Node 版本太旧 | 删掉不合格的 `~/.node22` 后重新 `bash install.sh`。Pi 需要 22.19+ |
| 超时（退出码 124） | 把工作拆小，或加大 `--timeout`（默认 300 秒，`0` 表示不限制） |
| 没有 webhook | 确认两个 `PI_NOTIFY_*` 都是 `set`（不要打印值），并且例行任务已启用。结果仍在 `~/.pi/tasks/<ID>/`，用 `pending` 补报 |
| 同一个 session 已有任务在跑 | `status` / `cancel`，或换一个 session 名 |
| 怀疑安装脚本没装干净 | 再跑一次 `bash install.sh`。它是幂等的 |

## 仓库布局

| 路径 | 作用 |
| --- | --- |
| `install.sh` | 一条命令安装 |
| `skills/pi-agent/SKILL.md` | Bot 技能 |
| `bin/` | 来自上游的 `pi-call` / `pi-task` |
| `routines/pi-task-notify.md` | webhook 例行任务模板 |
| `NOTICE` | 上游版权与 MIT 许可 |

## 致谢

脚本、任务记录和 webhook 通知流程来自 Robbin Fan 的 [grokbot-local-agent](https://github.com/robbin/grokbot-local-agent)（Copyright 2026 Robbin Fan，MIT）。本仓库保留上游版权声明，详见 [NOTICE](NOTICE)。

Pi 本体是 [@earendil-works/pi-coding-agent](https://www.npmjs.com/package/@earendil-works/pi-coding-agent)（[earendil-works/pi](https://github.com/earendil-works/pi)）。

本仓库其余部分以 [MIT](LICENSE) 发布，Copyright 2026 peternowak2。
