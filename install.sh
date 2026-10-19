#!/usr/bin/env bash
# Idempotent installer for the pi-agent skill on a Grok Bot Linux box.
#
# Installs Node.js 22.19+ into ~/.node22 (the location grokbot-local-agent
# expects), installs Pi with npm into ~/.local, and copies the pi-call / pi-task
# scripts to ~/tools/pi-call. Never prints secret values.
#
# Usage: bash install.sh [--dry-run]

# xtrace would echo secret values. Turn it off before doing anything else.
set +x
set -euo pipefail

DRY_RUN=0
case "${1:-}" in
  "")
    ;;
  --dry-run)
    DRY_RUN=1
    ;;
  -h|--help)
    cat <<'EOF'
Usage: bash install.sh [--dry-run]

Install Node.js 22.19+ into ~/.node22, Pi into ~/.local, and the pi-call /
pi-task scripts into ~/tools/pi-call. When /home/box/agent-data/workflows
exists, also copy skills/pi-agent/SKILL.md there.

--dry-run   print the plan and secret status only; download and copy nothing.

The script only reports whether DEEPSEEK_API_KEY, PI_NOTIFY_URL, and
PI_NOTIFY_SECRET are set. It never prints their values.
EOF
    exit 0
    ;;
  *)
    printf 'error: unknown argument (expected --dry-run or --help)\n' >&2
    exit 2
    ;;
esac

if [[ "$#" -gt 1 ]]; then
  printf 'error: too many arguments\n' >&2
  exit 2
fi

# Remember only set / not set, then drop the values so child processes
# (curl, npm, tar) cannot write them into logs.
DEEPSEEK_STATE="not set"
URL_STATE="not set"
SECRET_STATE="not set"
if [[ -n "${DEEPSEEK_API_KEY:-}" ]]; then
  DEEPSEEK_STATE="set"
fi
if [[ -n "${PI_NOTIFY_URL:-}" ]]; then
  URL_STATE="set"
fi
if [[ -n "${PI_NOTIFY_SECRET:-}" ]]; then
  SECRET_STATE="set"
fi
unset DEEPSEEK_API_KEY PI_NOTIFY_URL PI_NOTIFY_SECRET || true

if [[ -z "${HOME:-}" || "${HOME}" == "/" ]]; then
  printf 'error: HOME must be set to a user directory\n' >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NODE_HOME="${HOME}/.node22"
PI_BIN="${HOME}/.local/bin/pi"
TOOLS_DIR="${HOME}/tools/pi-call"
WORKFLOWS_DIR="${PI_AGENT_WORKFLOWS_DIR:-/home/box/agent-data/workflows}"
MIN_NODE="22.19.0"

log() {
  printf '%s\n' "$*"
}

require_file() {
  if [[ ! -f "${ROOT}/$1" ]]; then
    log "error: missing ${ROOT}/$1"
    log "Run install.sh from a clone of grokbot-pi-agent-skill."
    exit 1
  fi
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log "error: required command not found: $1"
    exit 1
  fi
}

node_is_new_enough() {
  "$1" -e 'const [maj, min, patch] = process.versions.node.split(".").map(Number); process.exit((maj > 22 || (maj === 22 && (min > 19 || (min === 19 && patch >= 0)))) ? 0 : 1);'
}

version_at_least() {
  printf '%s\n%s\n' "$1" "$2" | sort -C -V
}

node_platform() {
  case "$(uname -s)" in
    Linux) printf 'linux' ;;
    *)
      log "error: this installer supports Linux (found $(uname -s))"
      exit 1
      ;;
  esac
}

node_arch() {
  case "$(uname -m)" in
    x86_64|amd64) printf 'x64' ;;
    aarch64|arm64) printf 'arm64' ;;
    armv7l) printf 'armv7l' ;;
    ppc64le) printf 'ppc64le' ;;
    s390x) printf 's390x' ;;
    *)
      log "error: unsupported CPU architecture: $(uname -m)"
      exit 1
      ;;
  esac
}

install_node22() {
  local node_bin="${NODE_HOME}/bin/node"
  local npm_bin="${NODE_HOME}/bin/npm"
  if [[ -x "${node_bin}" && -x "${npm_bin}" ]] && node_is_new_enough "${node_bin}"; then
    local ver
    ver="$("${node_bin}" -v)"
    log "Node ${ver} already installed at ${NODE_HOME}"
    return 0
  fi
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "[dry-run] would install Node.js ${MIN_NODE}+ into ${NODE_HOME}"
    return 0
  fi

  require_cmd curl
  require_cmd tar
  require_cmd xz
  require_cmd sha256sum
  require_cmd awk
  require_cmd sort

  if [[ -e "${NODE_HOME}" && ! -d "${NODE_HOME}" ]]; then
    log "error: ${NODE_HOME} exists and is not a directory"
    exit 1
  fi

  local platform arch
  platform="$(node_platform)"
  arch="$(node_arch)"

  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/pi-agent-node.XXXXXX")"
  # Path is expanded now on purpose so cleanup still works after RETURN.
  # shellcheck disable=SC2064
  trap "rm -rf $(printf '%q' "${tmp}")" RETURN

  local base="https://nodejs.org/dist/latest-v22.x"
  log "Resolving Node.js ${MIN_NODE}+ for ${platform}-${arch}"
  curl -fsSL "${base}/SHASUMS256.txt" -o "${tmp}/SHASUMS256.txt"

  local suffix="-${platform}-${arch}.tar.xz"
  local node_file
  node_file="$(awk -v suffix="${suffix}" '
    index($2, "node-v") == 1 && length($2) >= length(suffix) && substr($2, length($2) - length(suffix) + 1) == suffix { print $2; exit }
  ' "${tmp}/SHASUMS256.txt")"
  if [[ -z "${node_file}" ]]; then
    log "error: no Node.js tarball for ${platform}-${arch} in ${base}"
    exit 1
  fi

  local ver="${node_file#node-v}"
  ver="${ver%%-*}"
  if ! version_at_least "${MIN_NODE}" "${ver}"; then
    log "error: resolved Node.js ${ver} is older than ${MIN_NODE}"
    exit 1
  fi

  log "Downloading ${node_file}"
  curl -fsSL "${base}/${node_file}" -o "${tmp}/${node_file}"
  awk -v file="${node_file}" '$2 == file { print }' "${tmp}/SHASUMS256.txt" > "${tmp}/SHASUMS256.selected"
  if [[ ! -s "${tmp}/SHASUMS256.selected" ]]; then
    log "error: checksum entry missing for ${node_file}"
    exit 1
  fi
  log "Verifying SHA256"
  (cd "${tmp}" && sha256sum -c SHASUMS256.selected)

  log "Extracting Node.js ${ver} into ${NODE_HOME}"
  tar -xJf "${tmp}/${node_file}" -C "${tmp}"
  local extracted="${tmp}/${node_file%.tar.xz}"
  if [[ ! -x "${extracted}/bin/node" ]]; then
    log "error: archive did not contain bin/node"
    exit 1
  fi

  local staging="${NODE_HOME}.new.$$"
  local backup=""
  rm -rf "${staging}"
  mkdir -p "${staging}"
  cp -a "${extracted}/." "${staging}/"
  if [[ -d "${NODE_HOME}" ]]; then
    backup="${NODE_HOME}.old.$$"
    rm -rf "${backup}"
    mv "${NODE_HOME}" "${backup}"
  fi
  if ! mv "${staging}" "${NODE_HOME}"; then
    if [[ -n "${backup}" && -d "${backup}" ]]; then
      mv "${backup}" "${NODE_HOME}" || true
    fi
    log "error: could not move Node.js into ${NODE_HOME}"
    exit 1
  fi
  if [[ -n "${backup}" ]]; then
    rm -rf "${backup}"
  fi

  if ! node_is_new_enough "${NODE_HOME}/bin/node"; then
    log "error: installed Node.js is older than ${MIN_NODE}"
    exit 1
  fi
  ver="$("${NODE_HOME}/bin/node" -v)"
  log "Node ${ver} installed at ${NODE_HOME}"
}

install_pi() {
  export PATH="${NODE_HOME}/bin:${HOME}/.local/bin:${PATH}"
  if [[ -x "${PI_BIN}" ]] && "${PI_BIN}" --version >/dev/null 2>&1; then
    local ver
    ver="$("${PI_BIN}" --version 2>/dev/null || true)"
    if [[ -z "${ver}" ]]; then
      ver="present"
    fi
    log "Pi already installed: ${ver}"
    return 0
  fi
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "[dry-run] would npm install @earendil-works/pi-coding-agent into ${HOME}/.local"
    return 0
  fi
  if [[ ! -x "${NODE_HOME}/bin/npm" ]]; then
    log "error: npm not found at ${NODE_HOME}/bin/npm"
    exit 1
  fi
  log "Installing Pi (@earendil-works/pi-coding-agent) into ${HOME}/.local"
  "${NODE_HOME}/bin/npm" install -g --prefix "${HOME}/.local" @earendil-works/pi-coding-agent
  if [[ ! -x "${PI_BIN}" ]]; then
    log "error: pi was not installed at ${PI_BIN}"
    exit 1
  fi
  local ver
  ver="$("${PI_BIN}" --version 2>/dev/null || true)"
  log "Pi installed: ${ver:-present}"
}

install_scripts() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "[dry-run] would copy scripts to ${TOOLS_DIR}"
    return 0
  fi
  mkdir -p "${TOOLS_DIR}"
  cp -a "${ROOT}/bin/." "${TOOLS_DIR}/"
  cp -a "${ROOT}/routines/pi-task-notify.md" "${TOOLS_DIR}/pi-task-notify.md"
  chmod +x "${TOOLS_DIR}/pi-run" "${TOOLS_DIR}/pi-call.mjs" "${TOOLS_DIR}/pi-task" "${TOOLS_DIR}/pi-task.mjs"
  log "Scripts installed: ${TOOLS_DIR}"
}

install_skill() {
  local dest="${WORKFLOWS_DIR}/pi-agent"
  if [[ ! -d "${WORKFLOWS_DIR}" && ! -d "${dest}" ]]; then
    log "Skill copy skipped: ${WORKFLOWS_DIR} does not exist."
    log "On a Grok Bot box that directory is the workflow store. Copy manually with:"
    log "  mkdir -p ${dest} && cp ${ROOT}/skills/pi-agent/SKILL.md ${dest}/SKILL.md"
    return 0
  fi
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "[dry-run] would copy skill to ${dest}/SKILL.md"
    return 0
  fi
  mkdir -p "${dest}"
  cp "${ROOT}/skills/pi-agent/SKILL.md" "${dest}/SKILL.md"
  log "Skill installed: ${dest}/SKILL.md"
}

self_check() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "[dry-run] skipping pi --version and pi-task --help"
    return 0
  fi
  export PATH="${NODE_HOME}/bin:${HOME}/.local/bin:${PATH}"
  local node_ver pi_ver help_text
  node_ver="$("${NODE_HOME}/bin/node" -v)"
  pi_ver="$("${PI_BIN}" --version)"
  help_text="$("${TOOLS_DIR}/pi-task" --help)"
  log "check node: ${node_ver}"
  log "check pi: ${pi_ver}"
  log "check pi-task --help: ${help_text%%$'\n'*}"
}

print_next_steps() {
  log ""
  log "Secrets (values are never printed):"
  log "  DEEPSEEK_API_KEY: ${DEEPSEEK_STATE}"
  log "  PI_NOTIFY_URL: ${URL_STATE}"
  log "  PI_NOTIFY_SECRET: ${SECRET_STATE}"
  log ""
  log "Next steps"
  log "1. On the Grok Bot that will call Pi, add bot secrets (environment variables)."
  log "   Do not paste the values into a file, a prompt, or this terminal log."
  log "   - DEEPSEEK_API_KEY   your DeepSeek API key (platform.deepseek.com)"
  log "   - PI_NOTIFY_URL      webhook URL of the completion routine"
  log "   - PI_NOTIFY_SECRET   raw Bearer token for that webhook, without a \"Bearer \" prefix"
  log "   A new bot turn picks up secrets. Pi reads DEEPSEEK_API_KEY from the environment."
  log "2. Create a webhook-triggered routine, for example named \"Pi task completion\"."
  log "   Paste the instructions from:"
  log "     ${ROOT}/routines/pi-task-notify.md"
  log "   After a real install the same file is also at:"
  log "     ${TOOLS_DIR}/pi-task-notify.md"
  log "   Replace YOUR_AGENT_ID with this bot's id: the directory name under"
  log "   /home/box/agent-data/agents/ that contains profile.json."
  log "   Save the routine's webhook URL and raw token as the two PI_NOTIFY_* secrets."
  log "3. Put Node and Pi on PATH in the bot shell, then dispatch with your own owner id:"
  log "     export PATH=\"\$HOME/.node22/bin:\$HOME/.local/bin:\$PATH\""
  log "     test -n \"\$DEEPSEEK_API_KEY\" && echo key-ok"
  log "     ~/tools/pi-call/pi-task run <cwd> \"<prompt>\" --session <name> --owner <your-bot-id>"
  log "   On wake, list your unfinished reports and acknowledge only after you verify:"
  log "     ~/tools/pi-call/pi-task pending --owner <your-bot-id>"
  log "     ~/tools/pi-call/pi-task ack <ID> --owner <your-bot-id>"
  log "   Other bots on this same box can use ~/tools/pi-call and pass their own --owner."
  log "   The routine above forwards their task ids; they should not ack anyone else's work."
  log "   Docs: ${ROOT}/README.md (中文) and ${ROOT}/README.en.md"
}

main() {
  local rel
  for rel in \
    bin/pi-call.mjs \
    bin/pi-run \
    bin/pi-task \
    bin/pi-task.mjs \
    skills/pi-agent/SKILL.md \
    routines/pi-task-notify.md
  do
    require_file "${rel}"
  done

  if [[ "$(uname -s)" != "Linux" ]]; then
    log "error: this installer supports Linux (found $(uname -s))"
    exit 1
  fi

  log "pi-agent installer"
  log "repo: ${ROOT}"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "mode: dry-run"
  else
    log "mode: install"
  fi

  install_node22
  install_pi
  install_scripts
  install_skill
  self_check
  print_next_steps
}

main "$@"
