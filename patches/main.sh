#!/usr/bin/env bash
set -euo pipefail

# Hermes Agent 中文一键安装脚本
# 功能：自动下载源码 + 应用汉化补丁 + 完成安装
# Usage: curl -fsSL https://raw.githubusercontent.com/David8lang/hermes-agent-zh/main/install-zh.sh | bash

OFFICIAL_REPO_URL="https://github.com/nousresearch/hermes-agent.git"
GITCODE_REPO_URL="https://gitcode.com/hermes-go/hermes-agent.git"
REPO_SOURCE="${HERMES_ZH_REPO_SOURCE:-auto}"
REPO_SOURCE_EFFECTIVE="unknown"
REPO_URL=""
HERMES_ZH_CHANNEL="${HERMES_ZH_CHANNEL:-stable}"
HERMES_REF="${HERMES_REF:-}"
HERMES_ZH_MISMATCH_ACTION="${HERMES_ZH_MISMATCH_ACTION:-}"
HERMES_ZH_IMPORT_EXISTING_CONFIG="${HERMES_ZH_IMPORT_EXISTING_CONFIG:-}"
INSTALL_DIR="$HOME/.hermes/hermes-agent"
PATCH_REPO="https://raw.githubusercontent.com/David8lang/hermes-agent-zh/main"
DEFAULT_PATCH_VERSION="0.13"
GITHUB_SLOW_THRESHOLD_SECONDS="${HERMES_ZH_GITHUB_SLOW_THRESHOLD_SECONDS:-6}"
SELECTED_PATCH_VERSION=""
USER_DATA_PATHS="
config.yaml
.env
auth.json
SOUL.md
state.db
state.db-shm
state.db-wal
memories
skills
hooks
cron
pairing
.hermes_history
.skills_prompt_snapshot.json
models_dev_cache.json
"
RUNTIME_DATA_PATHS="
logs
sessions
sandboxes
audio_cache
image_cache
"

TMP_DIR=$(mktemp -d)
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

LOCALIZE_PYTHON=""
CURRENT_REPO_URL=""
CURRENT_REPO_STATUS="unknown"
REPO_SOURCE_FROM_ENV=0
PATCH_MANIFEST_FILE="$TMP_DIR/patch-manifest.json"
PATCH_ASSET_BASE_URL=""
PATCH_BASELINE_COMMIT=""
PATCH_BASE_REF=""
PATCH_BASE_CHANNEL=""
PATCH_SOURCE_REF=""
PATCH_HERMES_VERSION=""
CURRENT_REPO_COMMIT=""
STABLE_CLONE_URL=""
STABLE_GITHUB_COMMIT=""
STABLE_GITCODE_COMMIT=""
LAST_GIT_TAG_ERROR=""
LAST_GIT_TAG_ERROR_KIND=""
EXISTING_USER_DATA_SNAPSHOT=""
IMPORT_EXISTING_CONFIG_DECISION=""
EXISTING_USER_DATA_RESTORED=0
STABLE_TAG_NOTICE_EMITTED=0

if [ "${HERMES_ZH_REPO_SOURCE+x}" = "x" ]; then
  REPO_SOURCE_FROM_ENV=1
fi

find_python3_for_localizer() {
  local candidate
  for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1 && \
      "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info[0] >= 3 else 1)' >/dev/null 2>&1; then
      LOCALIZE_PYTHON="$candidate"
      return 0
    fi
  done
  return 1
}

validate_positive_integer() {
  local value="$1"
  local name="$2"
  case "$value" in
    ''|*[!0-9]*)
      echo "❌ 错误: $name 必须是大于 0 的整数，当前值: $value" >&2
      exit 2
      ;;
  esac
  if [ "$value" -le 0 ]; then
    echo "❌ 错误: $name 必须是大于 0 的整数，当前值: $value" >&2
    exit 2
  fi
}

patch_release_label() {
  printf 'Hermes Agent v%s 发行版\n' "${1:-$DEFAULT_PATCH_VERSION}"
}

detect_hermes_version() {
  local version
  version=$(
    awk '
      /^[[:space:]]*version[[:space:]]*=/ {
        value = $0
        sub(/^[[:space:]]*version[[:space:]]*=[[:space:]]*/, "", value)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
        gsub(/^["'"'"']|["'"'"']$/, "", value)
        print value
        exit
      }
    ' "$1"
  )
  [ -n "$version" ] || return 1
  printf '%s\n' "$version"
}

patch_version_from_hermes_version() {
  case "${1:-}" in
    0.9.*)
      printf '%s\n' "0.9"
      ;;
    0.10.*)
      printf '%s\n' "0.10"
      ;;
    0.11.*)
      printf '%s\n' "0.11"
      ;;
    0.12.*)
      printf '%s\n' "0.12"
      ;;
    0.13.*)
      printf '%s\n' "0.13"
      ;;
    *)
      return 1
      ;;
  esac
}

patch_manifest_available() {
  local patch_version="$1"

  curl -fsSL "$PATCH_REPO/patches/versions/$patch_version/manifest.json" -o /dev/null >/dev/null 2>&1
}

prompt_patch_version_selection() {
  local patch_version_selection=""

  if ! is_tty_interactive; then
    SELECTED_PATCH_VERSION="$DEFAULT_PATCH_VERSION"
    return 0
  fi

  echo "请选择要安装的汉化版本：" >/dev/tty
  echo "[1] Hermes Agent 中文汉化（针对 Releases v0.13.0）" >/dev/tty
  echo "[2] Hermes Agent 中文汉化（针对 Releases v0.12.0）" >/dev/tty
  echo "[3] Hermes Agent 中文汉化（针对 Releases v0.11.0）" >/dev/tty
  echo "[4] Hermes Agent 中文汉化（针对 Releases v0.10.0）" >/dev/tty
  echo "[5] Hermes Agent 中文汉化（针对 Releases v0.9.0）" >/dev/tty
  echo "" >/dev/tty
  prompt_via_tty patch_version_selection "默认：1 > "

  case "${patch_version_selection:-1}" in
    ""|1) SELECTED_PATCH_VERSION="0.13" ;;
    2) SELECTED_PATCH_VERSION="0.12" ;;
    3) SELECTED_PATCH_VERSION="0.11" ;;
    4) SELECTED_PATCH_VERSION="0.10" ;;
    5) SELECTED_PATCH_VERSION="0.9" ;;
    *)
      echo "⚠️ 输入无效，已默认选择最新汉化版本。" >/dev/tty
      SELECTED_PATCH_VERSION="$DEFAULT_PATCH_VERSION"
      ;;
  esac
}

prompt_existing_repo_patch_version_choice() {
  local current_patch_version="$1"
  local latest_patch_version="$2"
  local raw_choice=""

  echo "  检测到当前源码可汉化版本: $current_patch_version"
  if [ "$current_patch_version" = "$latest_patch_version" ]; then
    echo "  当前源码版本与汉化包版本一致，使用 $current_patch_version 版本汉化。"
    printf '%s\n' "$current_patch_version"
    return 0
  fi

  echo "请选择汉化方式"
  echo "[1] 汉化当前 $current_patch_version 版本"
  echo "[2] 升级到 $latest_patch_version 最新版后再汉化"

  if prompt_via_tty raw_choice "默认选1 [1]: "; then
    :
  fi

  case "${raw_choice:-1}" in
    ""|1)
      printf '%s\n' "$current_patch_version"
      ;;
    2)
      printf '%s\n' "$latest_patch_version"
      ;;
    *)
      echo "  输入无效，已默认使用当前版本汉化。"
      printf '%s\n' "$current_patch_version"
      ;;
  esac
}

select_patch_version_for_repo() {
  local current_version="${1:-}"
  local current_patch_version=""
  local latest_patch_version="$DEFAULT_PATCH_VERSION"

  if ! current_patch_version=$(patch_version_from_hermes_version "$current_version"); then
    echo "  未检测到可汉化版本，将使用 $latest_patch_version 最新版再汉化。"
    printf '%s\n' "$latest_patch_version"
    return 0
  fi

  if ! patch_manifest_available "$current_patch_version"; then
    echo "  当前源码版本 $current_version 暂无对应汉化包，将使用 $latest_patch_version 最新版再汉化。"
    printf '%s\n' "$latest_patch_version"
    return 0
  fi

  prompt_existing_repo_patch_version_choice "$current_patch_version" "$latest_patch_version"
}

localize_setup_hermes() {
  local target_root="$1"
  local python_bin="$2"

  "$python_bin" - "$target_root" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
path = root / "setup-hermes.sh"
if not path.exists():
    raise SystemExit(0)

replacements = (
    ('echo -e "${CYAN}⚕ Hermes Agent Setup${NC}"', 'echo -e "${CYAN}⚕ Hermes Agent 安装程序 / Setup${NC}"'),
    ('echo -e "${CYAN}→${NC} Checking for uv..."', 'echo -e "${CYAN}→${NC} 检查 uv..."'),
    ('echo -e "${GREEN}✓${NC} uv found ($UV_VERSION)"', 'echo -e "${GREEN}✓${NC} uv 已找到 ($UV_VERSION)"'),
    ('echo -e "${CYAN}→${NC} Checking Python $PYTHON_VERSION..."', 'echo -e "${CYAN}→${NC} 检查 Python $PYTHON_VERSION..."'),
    ('echo -e "${GREEN}✓${NC} $PYTHON_FOUND_VERSION found"', 'echo -e "${GREEN}✓${NC} 已找到 $PYTHON_FOUND_VERSION"'),
    ('echo -e "${CYAN}→${NC} Setting up virtual environment..."', 'echo -e "${CYAN}→${NC} 创建 Python 虚拟环境..."'),
    ('echo -e "${GREEN}✓${NC} venv created (Python $PYTHON_VERSION)"', 'echo -e "${GREEN}✓${NC} venv 已创建 (Python $PYTHON_VERSION)"'),
    ('echo -e "${CYAN}→${NC} Installing dependencies..."', 'echo -e "${CYAN}→${NC} 安装依赖..."'),
    ('echo -e "${CYAN}→${NC} Using uv.lock for hash-verified installation..."', 'echo -e "${CYAN}→${NC} 正在根据 uv.lock 安全安装依赖..."'),
    ('echo -e "${CYAN}→${NC} Installing optional submodules..."', 'echo -e "${CYAN}→${NC} 安装可选子模块..."'),
    ('echo -e "${CYAN}→${NC} Checking ripgrep (optional, for faster search)..."', 'echo -e "${CYAN}→${NC} 检查 ripgrep（可选，用于更快搜索）..."'),
    ('echo -e "${GREEN}✓${NC} Created .env from template"', 'echo -e "${GREEN}✓${NC} 已从模板创建 .env"'),
    ('echo -e "${GREEN}✓${NC} .env exists"', 'echo -e "${GREEN}✓${NC} .env 已存在"'),
    ('echo -e "${CYAN}→${NC} Setting up hermes command..."', 'echo -e "${CYAN}→${NC} 设置 hermes 命令..."'),
    ('echo "Syncing bundled skills to ~/.hermes/skills/ ..."', 'echo "正在同步内置 skills 到 ~/.hermes/skills/ ..."'),
    ('echo -e "${GREEN}✓ Setup complete!${NC}"', 'echo -e "${GREEN}✓ 安装完成！${NC}"'),
    ('echo "Next steps:"', 'echo "🔗 更多优化脚本访问：www.hermesgo.com"\necho "下一步："'),
    ('echo "  1. Reload your shell:"', 'echo "  1. 重新加载 shell："'),
    ('echo "  1. Run the setup wizard to configure API keys:"', 'echo "  1. 运行配置向导，配置 API keys："'),
    ('echo "  2. Run the setup wizard to configure API keys:"', 'echo "  2. 运行配置向导，配置 API keys："'),
    ('echo "  2. Start chatting:"', 'echo "  2. 开始聊天："'),
    ('echo "  3. Start chatting:"', 'echo "  3. 开始聊天："'),
    ('echo "Other commands:"', 'echo "其他常用命令："'),
    ('echo "  hermes status        # Check configuration"', 'echo "  hermes status        # 检查配置"'),
    ('echo "  hermes gateway       # Run gateway in foreground"', 'echo "  hermes gateway       # 前台运行 gateway"'),
    ('echo "  hermes gateway install # Install gateway service (messaging + cron)"', 'echo "  hermes gateway install # 安装 gateway 服务（消息 + cron）"'),
    ('echo "  hermes cron list     # View scheduled jobs"', 'echo "  hermes cron list     # 查看计划任务"'),
    ('echo "  hermes doctor        # Diagnose issues"', 'echo "  hermes doctor        # 诊断问题"'),
    ('read -p "Would you like to run the setup wizard now? [Y/n] " -n 1 -r', 'read -p "是否现在运行配置向导 hermes setup？[Y/n] " -n 1 -r'),
)

text = path.read_text(encoding="utf-8")
for old, new in replacements:
    text = text.replace(old, new)
path.write_text(text, encoding="utf-8")
PY
}

localize_main_startup_prompt() {
  local target_root="$1"
  local python_bin="$2"

  "$python_bin" - "$target_root" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
path = root / "hermes_cli" / "main.py"
if not path.exists():
    raise SystemExit(0)

text = path.read_text(encoding="utf-8")

replacements = (
    (
        '    if not _has_any_provider_configured():\n'
        '        print()\n'
        '        print(\n'
        '            "It looks like Hermes isn\'t configured yet -- no API keys or providers found."\n'
        '        )\n',
        '    if not _has_any_provider_configured():\n'
        '        from hermes_cli.zh_patch import zh\n'
        '        print()\n'
        '        print(\n'
        '            zh("It looks like Hermes isn\'t configured yet -- no API keys or providers found.")\n'
        '        )\n',
    ),
    (
        '            reply = input("Run setup now? [Y/n] ").strip().lower()',
        '            reply = input(zh("Run setup now?") + " [Y/n] ").strip().lower()',
    ),
    (
        '        print("You can run \'hermes setup\' at any time to configure.")',
        '        print(zh("You can run \'hermes setup\' at any time to configure."))',
    ),
)

updated = text
for old, new in replacements:
    updated = updated.replace(old, new)

if updated != text:
    path.write_text(updated, encoding="utf-8")
PY
}

is_tty_interactive() {
  [ -r /dev/tty ] && [ -w /dev/tty ]
}

prompt_via_tty() {
  local __var_name="$1"
  local __prompt="$2"
  local __reply=""

  if ! is_tty_interactive; then
    printf -v "$__var_name" '%s' ""
    return 1
  fi

  printf '%s' "$__prompt" >/dev/tty
  IFS= read -r __reply </dev/tty || true
  printf -v "$__var_name" '%s' "$__reply"
  return 0
}

default_mismatch_action() {
  case "${HERMES_ZH_MISMATCH_ACTION:-}" in
    "")
      if is_tty_interactive; then
        printf '%s\n' "ask"
      else
        printf '%s\n' "auto"
      fi
      ;;
    ask|auto|manual)
      printf '%s\n' "$HERMES_ZH_MISMATCH_ACTION"
      ;;
    *)
      echo "❌ 错误: HERMES_ZH_MISMATCH_ACTION 仅支持 ask / auto / manual，当前值: $HERMES_ZH_MISMATCH_ACTION" >&2
      exit 2
      ;;
  esac
}

default_import_existing_config_action() {
  case "${HERMES_ZH_IMPORT_EXISTING_CONFIG:-}" in
    "")
      if is_tty_interactive; then
        printf '%s\n' "ask"
      else
        printf '%s\n' "yes"
      fi
      ;;
    ask|yes|no)
      printf '%s\n' "$HERMES_ZH_IMPORT_EXISTING_CONFIG"
      ;;
    *)
      echo "❌ 错误: HERMES_ZH_IMPORT_EXISTING_CONFIG 仅支持 ask / yes / no，当前值: $HERMES_ZH_IMPORT_EXISTING_CONFIG" >&2
      exit 2
      ;;
  esac
}

prompt_repo_mismatch_action() {
  local default_action=""
  local raw_choice=""

  default_action=$(default_mismatch_action)
  if [ "$default_action" != "ask" ]; then
    printf '%s\n' "$default_action"
    return 0
  fi

  echo "检测到当前安装版本与汉化 stable 支持的官方发布版基线不一致。" >/dev/tty
  echo "这通常表示你之前通过官方脚本安装了最新 main 分支。" >/dev/tty
  echo "当前汉化 stable 只支持官方发布版基线，不直接跟随 main。" >/dev/tty
  echo "当前安装 commit: ${CURRENT_REPO_COMMIT:-unknown}" >/dev/tty
  echo "汉化目标版本: ${PATCH_HERMES_VERSION:-unknown}" >/dev/tty
  if [ -n "$PATCH_BASE_REF" ]; then
    echo "汉化基线 tag: $PATCH_BASE_REF" >/dev/tty
  fi
  if [ -n "$PATCH_BASELINE_COMMIT" ]; then
    echo "汉化基线 commit: $PATCH_BASELINE_COMMIT" >/dev/tty
  fi
  echo "" >/dev/tty
  echo "[1] 自动切换到汉化匹配的官方发布版后继续安装" >/dev/tty
  echo "[2] 先停止，我自己手动处理版本" >/dev/tty
  echo "" >/dev/tty
  prompt_via_tty raw_choice "默认：1 > "

  case "${raw_choice:-1}" in
    ""|1)
      printf '%s\n' "auto"
      ;;
    2)
      printf '%s\n' "manual"
      ;;
    *)
      echo "⚠️ 输入无效，已默认自动切换到汉化匹配的官方发布版。" >/dev/tty
      printf '%s\n' "auto"
      ;;
  esac
}

prompt_import_existing_config() {
  local default_action=""
  local raw_choice=""

  default_action=$(default_import_existing_config_action)
  if [ "$default_action" != "ask" ]; then
    printf '%s\n' "$default_action"
    return 0
  fi

  echo "检测到旧版 Hermes 配置快照。" >/dev/tty
  echo "是否导入已有配置到新的汉化安装？" >/dev/tty
  echo "[1] 是，导入已有配置（默认）" >/dev/tty
  echo "[2] 否，保留当前新安装生成的干净配置" >/dev/tty
  echo "" >/dev/tty
  prompt_via_tty raw_choice "默认：1 > "

  case "${raw_choice:-1}" in
    ""|1)
      printf '%s\n' "yes"
      ;;
    2)
      printf '%s\n' "no"
      ;;
    *)
      echo "⚠️ 输入无效，已默认导入已有配置。" >/dev/tty
      printf '%s\n' "yes"
      ;;
  esac
}

backup_existing_user_data() {
  local hermes_home=""
  local python_bin=""

  hermes_home="$(dirname "$INSTALL_DIR")"
  if find_python3_for_localizer; then
    python_bin="$LOCALIZE_PYTHON"
  elif [ -x "$INSTALL_DIR/venv/bin/python" ]; then
    python_bin="$INSTALL_DIR/venv/bin/python"
  else
    echo "⚠️ 未找到可用的 Python 3，无法为错版安装创建配置快照，将继续沿用现有 ~/.hermes 配置。"
    return 0
  fi

  USER_DATA_PATHS="$USER_DATA_PATHS" \
    RUNTIME_DATA_PATHS="$RUNTIME_DATA_PATHS" \
    "$python_bin" - "$hermes_home" <<'PY'
from __future__ import annotations

import os
import shutil
import sys
import time
from pathlib import Path

hermes_home = Path(sys.argv[1]).expanduser().resolve()
if not hermes_home.exists():
    raise SystemExit(0)

user_data_paths = [item.strip() for item in os.environ.get("USER_DATA_PATHS", "").splitlines() if item.strip()]
runtime_data_paths = [item.strip() for item in os.environ.get("RUNTIME_DATA_PATHS", "").splitlines() if item.strip()]

snapshot = hermes_home / f".user-data-backup-{time.strftime('%Y%m%d-%H%M%S')}"
if snapshot.exists():
    snapshot = hermes_home / f".user-data-backup-{time.strftime('%Y%m%d-%H%M%S')}-{os.getpid()}"
snapshot.mkdir(parents=True, exist_ok=True)

copied = False
for rel in user_data_paths:
    src = hermes_home / rel
    if not src.exists():
        continue
    dst = snapshot / rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    if src.is_dir():
        shutil.copytree(src, dst, dirs_exist_ok=True)
    else:
        shutil.copy2(src, dst)
    copied = True

if not copied:
    shutil.rmtree(snapshot, ignore_errors=True)
    raise SystemExit(0)

for rel in runtime_data_paths:
    target = hermes_home / rel
    if target.is_dir():
        shutil.rmtree(target, ignore_errors=True)
    elif target.exists():
        target.unlink()

for rel in user_data_paths:
    target = hermes_home / rel
    if target.is_dir():
        shutil.rmtree(target, ignore_errors=True)
    elif target.exists():
        target.unlink()

print(snapshot)
PY
}

restore_existing_user_data() {
  local snapshot_dir="$1"
  local hermes_home=""
  local python_bin=""

  [ -n "$snapshot_dir" ] || return 0

  hermes_home="$(dirname "$INSTALL_DIR")"
  if find_python3_for_localizer; then
    python_bin="$LOCALIZE_PYTHON"
  elif [ -x "$INSTALL_DIR/venv/bin/python" ]; then
    python_bin="$INSTALL_DIR/venv/bin/python"
  else
    echo "⚠️ 未找到可用的 Python 3，无法恢复旧配置快照。"
    return 0
  fi

  USER_DATA_PATHS="$USER_DATA_PATHS" \
    RUNTIME_DATA_PATHS="$RUNTIME_DATA_PATHS" \
    "$python_bin" - "$snapshot_dir" "$hermes_home" <<'PY'
from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path

snapshot = Path(sys.argv[1]).expanduser().resolve()
hermes_home = Path(sys.argv[2]).expanduser().resolve()

if not snapshot.exists():
    raise SystemExit(0)

user_data_paths = [item.strip() for item in os.environ.get("USER_DATA_PATHS", "").splitlines() if item.strip()]
runtime_data_paths = [item.strip() for item in os.environ.get("RUNTIME_DATA_PATHS", "").splitlines() if item.strip()]

hermes_home.mkdir(parents=True, exist_ok=True)

for rel in runtime_data_paths:
    target = hermes_home / rel
    if target.is_dir():
        shutil.rmtree(target, ignore_errors=True)
    elif target.exists():
        target.unlink()

for rel in user_data_paths:
    target = hermes_home / rel
    if target.is_dir():
        shutil.rmtree(target, ignore_errors=True)
    elif target.exists():
        target.unlink()

for rel in user_data_paths:
    src = snapshot / rel
    if not src.exists():
        continue
    dst = hermes_home / rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    if src.is_dir():
        shutil.copytree(src, dst, dirs_exist_ok=True)
    else:
        shutil.copy2(src, dst)
PY
}

get_epoch_seconds() {
  date +%s
}

detect_git_commit() {
  if [ -d "$INSTALL_DIR/.git" ] && command -v git >/dev/null 2>&1; then
    git -C "$INSTALL_DIR" rev-parse HEAD 2>/dev/null || true
  fi
}

extract_manifest_value() {
  local key="$1"
  local file="$2"

  sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$file" | head -n 1
}

manifest_base_commit() {
  local file="$1"
  local value=""

  value=$(extract_manifest_value "base_commit" "$file")
  if [ -z "$value" ]; then
    value=$(extract_manifest_value "generated_from" "$file")
  fi
  printf '%s\n' "$value"
}

manifest_base_ref() {
  local file="$1"
  local value=""

  value=$(extract_manifest_value "base_ref" "$file")
  if [ -z "$value" ]; then
    value=$(extract_manifest_value "source_ref" "$file")
  fi
  printf '%s\n' "$value"
}

is_hex_commit() {
  local value="${1:-}"

  case "$value" in
    ''|*[!0-9a-f]*)
      return 1
      ;;
  esac

  [ "${#value}" -ge 7 ] && [ "${#value}" -le 40 ]
}

use_latest_main_requested() {
  case "${HERMES_ZH_USE_LATEST_MAIN:-}" in
    1|true|TRUE|yes|YES|y|Y)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

candidate_channel_requested() {
  if use_latest_main_requested; then
    return 0
  fi
  [ "$HERMES_ZH_CHANNEL" = "candidate" ]
}

validate_channel() {
  if use_latest_main_requested; then
    HERMES_ZH_CHANNEL="candidate"
  fi

  case "$HERMES_ZH_CHANNEL" in
    stable|candidate) ;;
    dev)
      if [ -z "$HERMES_REF" ]; then
        echo "❌ 错误: HERMES_ZH_CHANNEL=dev 时必须设置 HERMES_REF" >&2
        exit 2
      fi
      ;;
    *)
      echo "❌ 错误: HERMES_ZH_CHANNEL 仅支持 stable / candidate / dev，当前值: $HERMES_ZH_CHANNEL" >&2
      exit 2
      ;;
  esac
}

download_patch_manifest() {
  local patch_version="$1"

  curl -fsSL "$PATCH_REPO/patches/versions/$patch_version/manifest.json" -o "$PATCH_MANIFEST_FILE"
  [ -s "$PATCH_MANIFEST_FILE" ] || {
    echo "❌ 补丁清单下载失败" >&2
    exit 1
  }

  PATCH_BASELINE_COMMIT=$(manifest_base_commit "$PATCH_MANIFEST_FILE")
  PATCH_BASE_REF=$(manifest_base_ref "$PATCH_MANIFEST_FILE")
  PATCH_BASE_CHANNEL=$(extract_manifest_value "base_channel" "$PATCH_MANIFEST_FILE")
  PATCH_SOURCE_REF=$(extract_manifest_value "source_ref" "$PATCH_MANIFEST_FILE")
  PATCH_HERMES_VERSION=$(extract_manifest_value "hermes_version" "$PATCH_MANIFEST_FILE")
  [ -n "$PATCH_BASE_CHANNEL" ] || PATCH_BASE_CHANNEL="$HERMES_ZH_CHANNEL"
  [ -n "$PATCH_BASE_REF" ] || PATCH_BASE_REF="$PATCH_SOURCE_REF"

  if ! candidate_channel_requested && [ "$HERMES_ZH_CHANNEL" != "dev" ] && ! is_hex_commit "$PATCH_BASELINE_COMMIT"; then
    echo "❌ 补丁清单缺少有效的 generated_from commit，无法确定汉化包支持的源码版本" >&2
    exit 1
  fi
}

check_git_repo_available() {
  local url="$1"
  GIT_TERMINAL_PROMPT=0 git \
    -c http.lowSpeedLimit=1024 \
    -c http.lowSpeedTime=8 \
    -c http.connectTimeout=8 \
    ls-remote "$url" HEAD >/dev/null 2>&1
}

check_git_repo_status() {
  local url="$1"
  local start end elapsed

  start=$(get_epoch_seconds)
  if GIT_TERMINAL_PROMPT=0 git \
    -c http.lowSpeedLimit=1024 \
    -c http.lowSpeedTime=8 \
    -c http.connectTimeout=8 \
    ls-remote "$url" HEAD >/dev/null 2>&1; then
    end=$(get_epoch_seconds)
    elapsed=$((end - start))

    if [ "$elapsed" -gt "$GITHUB_SLOW_THRESHOLD_SECONDS" ]; then
      printf '%s\n' "slow"
    else
      printf '%s\n' "ok"
    fi
  else
    printf '%s\n' "unavailable"
  fi
}

probe_git_repo_latency() {
  local url="$1"
  local start end elapsed

  start=$(get_epoch_seconds)
  if GIT_TERMINAL_PROMPT=0 git \
    -c http.lowSpeedLimit=1024 \
    -c http.lowSpeedTime=8 \
    -c http.connectTimeout=8 \
    ls-remote "$url" HEAD >/dev/null 2>&1; then
    end=$(get_epoch_seconds)
    elapsed=$((end - start))
    printf 'ok:%s\n' "$elapsed"
  else
    printf 'unavailable:\n'
  fi
}

select_fastest_repo_source() {
  local github_probe=""
  local gitcode_probe=""
  local github_status=""
  local gitcode_status=""
  local github_elapsed=0
  local gitcode_elapsed=0

  github_probe=$(probe_git_repo_latency "$OFFICIAL_REPO_URL")
  gitcode_probe=$(probe_git_repo_latency "$GITCODE_REPO_URL")

  github_status=${github_probe%%:*}
  gitcode_status=${gitcode_probe%%:*}
  github_elapsed=${github_probe#*:}
  gitcode_elapsed=${gitcode_probe#*:}
  [ -n "$github_elapsed" ] || github_elapsed=0
  [ -n "$gitcode_elapsed" ] || gitcode_elapsed=0

  if [ "$github_status" = "ok" ] && [ "$gitcode_status" = "ok" ]; then
    if [ "$gitcode_elapsed" -le "$github_elapsed" ]; then
      printf '%s\n' "gitcode"
    else
      printf '%s\n' "github"
    fi
    return 0
  fi

  if [ "$gitcode_status" = "ok" ]; then
    printf '%s\n' "gitcode"
    return 0
  fi

  if [ "$github_status" = "ok" ]; then
    printf '%s\n' "github"
    return 0
  fi

  printf '%s\n' "unavailable"
}

resolve_latest_stable_tag() {
  local url="${1:-$OFFICIAL_REPO_URL}"

  GIT_TERMINAL_PROMPT=0 git ls-remote --tags "$url" "refs/tags/v[0-9]*.[0-9]*.[0-9]*" |
    awk '
      $2 ~ /^refs\/tags\/v[1-9][0-9]*\.[0-9]+\.[0-9]+$/ {
        tag = $2
        sub(/^refs\/tags\/v/, "", tag)
        split(tag, parts, ".")
        printf "%08d %08d %08d %s\n", parts[1], parts[2], parts[3], $2
      }
    ' |
    sort -k1,1n -k2,2n -k3,3n |
    tail -n 1 |
    sed 's#.* refs/tags/##'
}

resolve_tag_commit() {
  local tag="$1"
  local url="${2:-$OFFICIAL_REPO_URL}"
  local peeled_ref="refs/tags/$tag^{}"
  local direct_ref="refs/tags/$tag"
  local git_output=""
  local git_error_file=""
  local parsed_commit=""
  local git_status=0

  LAST_GIT_TAG_ERROR=""
  LAST_GIT_TAG_ERROR_KIND=""
  git_error_file="$(mktemp)"

  git_output=$(
    GIT_TERMINAL_PROMPT=0 git ls-remote --tags "$url" "$direct_ref" "$peeled_ref" 2>"$git_error_file"
  )
  git_status=$?
  if [ "$git_status" -ne 0 ]; then
    LAST_GIT_TAG_ERROR_KIND="network"
    LAST_GIT_TAG_ERROR="$(cat "$git_error_file")"
    rm -f "$git_error_file"
    return "$git_status"
  fi

  rm -f "$git_error_file"
  parsed_commit=$(
    printf '%s\n' "$git_output" |
      awk -v peeled_ref="$peeled_ref" -v direct_ref="$direct_ref" '
        $2 == peeled_ref { peeled = $1 }
        $2 == direct_ref { direct = $1 }
        END {
          if (peeled != "") {
            print peeled
          } else if (direct != "") {
            print direct
          } else {
            exit 1
          }
        }
      '
  ) || true

  if [ -z "$parsed_commit" ]; then
    LAST_GIT_TAG_ERROR_KIND="missing"
    return 1
  fi

  printf '%s\n' "$parsed_commit"
}

verify_repo_tag_consistency() {
  local tag="$1"
  local github_commit=""
  local gitcode_commit=""
  local source_commit=""

  if [ "$PATCH_BASE_CHANNEL" = "stable" ] && [ "$STABLE_TAG_NOTICE_EMITTED" -eq 1 ]; then
    return 0
  fi

  if [ "$REPO_SOURCE" = "gitcode" ]; then
    source_commit=$(resolve_tag_commit "$tag" "$GITCODE_REPO_URL") || {
      if [ "$LAST_GIT_TAG_ERROR_KIND" = "network" ]; then
        echo "❌ 无法连接 GitCode 国内镜像源或获取 stable tag 信息，请稍后重试。" >&2
        if [ -n "$LAST_GIT_TAG_ERROR" ]; then
          printf '%s\n' "$LAST_GIT_TAG_ERROR" >&2
        fi
      else
        echo "❌ GitCode 镜像缺少 stable tag: $tag" >&2
      fi
      exit 1
    }
    gitcode_commit="$source_commit"
  else
    source_commit=$(resolve_tag_commit "$tag" "$OFFICIAL_REPO_URL") || {
      if [ "$LAST_GIT_TAG_ERROR_KIND" = "network" ]; then
        echo "❌ 无法连接 GitHub 官方源或获取 stable tag 信息，请稍后重试。" >&2
        if [ -n "$LAST_GIT_TAG_ERROR" ]; then
          printf '%s\n' "$LAST_GIT_TAG_ERROR" >&2
        fi
      else
        echo "❌ GitHub 官方源不存在 stable tag: $tag" >&2
      fi
      exit 1
    }
    github_commit="$source_commit"
  fi

  STABLE_GITHUB_COMMIT="$github_commit"
  STABLE_GITCODE_COMMIT="$gitcode_commit"
  STABLE_TAG_NOTICE_EMITTED=1
  if [ -n "$gitcode_commit" ]; then
    STABLE_CLONE_URL="$GITCODE_REPO_URL"
    REPO_SOURCE_EFFECTIVE="gitcode"
  else
    STABLE_CLONE_URL="$OFFICIAL_REPO_URL"
    REPO_SOURCE_EFFECTIVE="github"
  fi
}

resolve_stable_clone_source() {
  local tag="$1"
  local repo_status=""

  if [ "$REPO_SOURCE" = "auto" ]; then
    repo_status=$(select_fastest_repo_source)
    case "$repo_status" in
      github)
        REPO_SOURCE_EFFECTIVE="github"
        ;;
      gitcode)
        REPO_SOURCE_EFFECTIVE="gitcode"
        ;;
      unavailable)
        echo "❌ 错误: GitHub 与 GitCode 当前都不可用，请稍后重试。" >&2
        exit 2
        ;;
      *)
        echo "❌ 错误: 无法识别自动测速结果: $repo_status" >&2
        exit 2
        ;;
    esac
  fi

  case "$REPO_SOURCE" in
    github)
      verify_repo_tag_consistency "$tag"
      STABLE_CLONE_URL="$OFFICIAL_REPO_URL"
      REPO_SOURCE_EFFECTIVE="github"
      ;;
    gitcode)
      verify_repo_tag_consistency "$tag"
      if [ -z "$STABLE_GITCODE_COMMIT" ]; then
        echo "❌ GitCode 镜像缺少 stable tag $tag，无法按要求使用 GitCode 国内镜像源。" >&2
        exit 1
      fi
      STABLE_CLONE_URL="$GITCODE_REPO_URL"
      REPO_SOURCE_EFFECTIVE="gitcode"
      ;;
    auto)
      if [ "$REPO_SOURCE_EFFECTIVE" = "gitcode" ]; then
        REPO_SOURCE="gitcode"
        verify_repo_tag_consistency "$tag"
        REPO_SOURCE="auto"
        STABLE_CLONE_URL="$GITCODE_REPO_URL"
        REPO_SOURCE_EFFECTIVE="gitcode"
      else
        REPO_SOURCE="github"
        verify_repo_tag_consistency "$tag"
        REPO_SOURCE="auto"
        STABLE_CLONE_URL="$OFFICIAL_REPO_URL"
        REPO_SOURCE_EFFECTIVE="github"
      fi
      ;;
    custom)
      echo "❌ stable 通道暂不支持 custom 源，请改用 github / gitcode / auto。" >&2
      exit 2
      ;;
    *)
      echo "❌ 错误: 无法识别 stable 源选择: $REPO_SOURCE" >&2
      exit 2
      ;;
  esac
}

infer_repo_source_from_url() {
  local url="${1:-}"
  case "$url" in
    *github.com/nousresearch/hermes-agent.git*) printf '%s\n' "github" ;;
    *gitcode.com/hermes-go/hermes-agent.git*) printf '%s\n' "gitcode" ;;
    '') printf '%s\n' "existing" ;;
    *) printf '%s\n' "custom" ;;
  esac
}

effective_source_label() {
  case "${1:-unknown}" in
    github) printf '%s\n' "GitHub 官方源" ;;
    gitcode) printf '%s\n' "GitCode 国内镜像源" ;;
    custom) printf '%s\n' "自定义源码源" ;;
    existing) printf '%s\n' "现有仓库 origin" ;;
    *) printf '%s\n' "未知源码源" ;;
  esac
}

print_repo_source_message() {
  case "${1:-unknown}" in
    github)
      echo "🌐 源码下载源：GitHub 官方源"
      echo "说明：版本最新，优先推荐。"
      ;;
    gitcode)
      echo "🌐 源码下载源：GitCode 国内镜像源"
      echo "说明：国内访问通常更快，但可能存在同步延迟。如果后续出现补丁不匹配，请稍后重试官方源。"
      ;;
    custom)
      echo "🌐 源码下载源：自定义源码源"
      echo "说明：请自行确认该仓库版本与当前汉化补丁的兼容性。"
      ;;
    existing)
      echo "🌐 源码下载源：沿用现有仓库 origin"
      echo "说明：未强制覆盖当前仓库远程地址。"
      ;;
  esac
}

print_repo_source_strategy() {
  case "$REPO_SOURCE" in
    auto)
      echo "📋 源码下载策略：自动模式。"
      echo "   新安装会同时测速 GitHub 和 GitCode，并自动选择响应更快的源。"
      echo "   已存在仓库时，默认沿用当前 origin。"
      ;;
    github)
      echo "📋 源码下载策略：强制使用 GitHub 官方源。"
      ;;
    gitcode)
      echo "📋 源码下载策略：强制使用 GitCode 国内镜像源。"
      echo "   注意：镜像可能存在同步延迟。"
      ;;
    custom)
      echo "📋 源码下载策略：使用自定义源码源。"
      ;;
  esac
}

validate_repo_source() {
  case "$REPO_SOURCE" in
    auto|github|gitcode|custom) ;;
    *)
      echo "❌ 错误: HERMES_ZH_REPO_SOURCE 仅支持 auto / github / gitcode / custom，当前值: $REPO_SOURCE" >&2
      exit 2
      ;;
  esac
}

prompt_repo_source_if_needed() {
  local selection=""
  if [ "$REPO_SOURCE_FROM_ENV" -eq 1 ]; then
    return 0
  fi
  if ! is_tty_interactive; then
    REPO_SOURCE="auto"
    return 0
  fi

  echo "请选择Git 仓库地址" >/dev/tty
  echo "" >/dev/tty
  echo "[1] Github官方地址" >/dev/tty
  echo "    https://github.com/NousResearch/hermes-agent" >/dev/tty
  echo "" >/dev/tty
  echo "[2] 国内镜像加速站" >/dev/tty
  echo "    https://gitcode.com/hermes-go/hermes-agent" >/dev/tty
  echo "" >/dev/tty
  echo "[3] 自动测速并选择" >/dev/tty
  echo "    先测速再决定使用 GitHub 或 GitCode。" >/dev/tty
  echo "" >/dev/tty
  prompt_via_tty selection "默认：2 > "
  case "${selection:-2}" in
    1) REPO_SOURCE="github" ;;
    ""|2) REPO_SOURCE="gitcode" ;;
    3) REPO_SOURCE="auto" ;;
    *)
      echo "⚠️ 输入无效，已使用默认 GitCode 国内镜像源。" >/dev/tty
      REPO_SOURCE="gitcode"
      ;;
  esac
}

get_repo_url_for_source() {
  case "$1" in
    github) printf '%s\n' "$OFFICIAL_REPO_URL" ;;
    gitcode) printf '%s\n' "$GITCODE_REPO_URL" ;;
    custom) printf '%s\n' "${HERMES_ZH_REPO_URL:-}" ;;
    *) printf '%s\n' "" ;;
  esac
}

select_repo_url() {
  local repo_status=""
  case "$REPO_SOURCE" in
    github)
      REPO_URL="$OFFICIAL_REPO_URL"
      REPO_SOURCE_EFFECTIVE="github"
      print_repo_source_message "$REPO_SOURCE_EFFECTIVE"
      ;;
    gitcode)
      REPO_URL="$GITCODE_REPO_URL"
      REPO_SOURCE_EFFECTIVE="gitcode"
      print_repo_source_message "$REPO_SOURCE_EFFECTIVE"
      ;;
    custom)
      if [ -z "${HERMES_ZH_REPO_URL:-}" ]; then
        echo "❌ 错误: 当 HERMES_ZH_REPO_SOURCE=custom 时，必须设置 HERMES_ZH_REPO_URL" >&2
        exit 2
      fi
      REPO_URL="$HERMES_ZH_REPO_URL"
      REPO_SOURCE_EFFECTIVE="custom"
      print_repo_source_message "$REPO_SOURCE_EFFECTIVE"
      ;;
    auto)
      repo_status=$(select_fastest_repo_source)
      case "$repo_status" in
        github)
          REPO_URL="$OFFICIAL_REPO_URL"
          REPO_SOURCE_EFFECTIVE="github"
          echo "✅ 自动测速完成，当前使用 GitHub 官方源。"
          print_repo_source_message "$REPO_SOURCE_EFFECTIVE"
          ;;
        gitcode)
          REPO_URL="$GITCODE_REPO_URL"
          REPO_SOURCE_EFFECTIVE="gitcode"
          echo "✅ 自动测速完成，当前使用 GitCode 国内镜像源。"
          print_repo_source_message "$REPO_SOURCE_EFFECTIVE"
          ;;
        unavailable)
          echo "❌ 错误: GitHub 与 GitCode 当前都不可用，请稍后重试。" >&2
          exit 2
          ;;
        *)
          echo "❌ 错误: 无法识别自动测速结果: $repo_status" >&2
          exit 2
          ;;
      esac
      ;;
  esac
}

get_existing_origin_url() {
  git remote get-url origin 2>/dev/null || true
}

print_gitcode_switch_back_hint() {
  echo "如需切回 GitHub 官方源，可执行："
  echo "  git -C \"$INSTALL_DIR\" remote set-url origin \"$OFFICIAL_REPO_URL\""
}

print_patch_guidance_for_source() {
  local reason="$1"
  local version_text="${2:-未知}"

  case "$REPO_SOURCE_EFFECTIVE" in
    github)
      echo "⚠️ 当前 Hermes 版本未被汉化补丁识别。"
      if [ "$reason" = "patch" ]; then
        echo "当前汉化补丁无法应用到版本 $version_text。"
      fi
      echo "你当前使用的是 GitHub 官方源，可能是 Hermes 官方刚发布了新版本，而汉化补丁尚未适配。"
      echo "建议："
      echo "1. 稍后等待汉化补丁更新；"
      echo "2. 或临时使用 GitCode 镜像源，安装可能仍处于旧版本的 Hermes："
      echo ""
      echo "curl -fsSL $PATCH_REPO/install-zh.sh | HERMES_ZH_REPO_SOURCE=gitcode bash"
      ;;
    gitcode)
      echo "⚠️ 当前 Hermes 版本未被汉化补丁识别。"
      if [ "$reason" = "patch" ]; then
        echo "当前汉化补丁无法应用到版本 $version_text。"
      fi
      echo "你当前使用的是 GitCode 国内镜像源。该镜像可能不是最新版本，但如果汉化补丁长期未更新，或者镜像已同步到新版本，也仍可能出现不匹配。"
      echo "建议："
      echo "1. 检查当前 Hermes 版本是否在汉化补丁支持范围内；"
      echo "2. 如果你希望安装官方最新源码，请强制使用 GitHub 官方源："
      echo ""
      echo "curl -fsSL $PATCH_REPO/install-zh.sh | HERMES_ZH_REPO_SOURCE=github bash"
      ;;
    custom|existing|*)
      echo "⚠️ 当前 Hermes 版本未被汉化补丁识别。"
      if [ "$reason" = "patch" ]; then
        echo "当前汉化补丁无法应用到版本 $version_text。"
      fi
      echo "你当前使用的是自定义源码源，请确认该源码版本是否在汉化补丁支持范围内。"
      ;;
  esac
}

verify_checked_out_base_commit() {
  local expected="$1"
  local actual=""

  actual=$(detect_git_commit)
  if [ "$actual" != "$expected" ]; then
    echo "❌ 源码 checkout 结果与 manifest 不一致。" >&2
    echo "  manifest base_commit: $expected" >&2
    echo "  当前 HEAD: ${actual:-unknown}" >&2
    exit 1
  fi
}

clone_with_stable_base() {
  local clone_url=""

  if [ -z "$PATCH_BASE_REF" ] || [ -z "$PATCH_BASELINE_COMMIT" ]; then
    echo "❌ stable manifest 必须包含 base_ref 和 base_commit" >&2
    exit 1
  fi
  if [ "$PATCH_BASE_REF" = "main" ]; then
    echo "❌ stable 通道绝不会使用 main，请检查 manifest。" >&2
    exit 1
  fi

  resolve_stable_clone_source "$PATCH_BASE_REF"
  clone_url="$STABLE_CLONE_URL"
  echo "  stable tag: $PATCH_BASE_REF"
  echo "  stable commit: $PATCH_BASELINE_COMMIT"
  echo "  克隆 stable 源码仓库..."
  if git clone --branch "$PATCH_BASE_REF" "$clone_url" "$INSTALL_DIR"; then
    cd "$INSTALL_DIR"
    verify_checked_out_base_commit "$PATCH_BASELINE_COMMIT"
    print_repo_source_message "$REPO_SOURCE_EFFECTIVE"
    return 0
  fi

  if [ "$clone_url" = "$GITCODE_REPO_URL" ]; then
    echo "⚠️ GitCode stable 克隆失败，正在回退到 GitHub 官方源..."
    rm -rf "$INSTALL_DIR"
    if git clone --branch "$PATCH_BASE_REF" "$OFFICIAL_REPO_URL" "$INSTALL_DIR"; then
      REPO_SOURCE_EFFECTIVE="github"
      cd "$INSTALL_DIR"
      verify_checked_out_base_commit "$PATCH_BASELINE_COMMIT"
      print_repo_source_message "$REPO_SOURCE_EFFECTIVE"
      return 0
    fi
  fi

  return 1
}

clone_with_selected_repo() {
  local fallback_available=0

  echo "  克隆源码仓库..."
  if git clone "$REPO_URL" "$INSTALL_DIR"; then
    return 0
  fi

  echo "⚠️ 当前源码克隆失败：$REPO_URL"
  if [ "$REPO_SOURCE_EFFECTIVE" != "gitcode" ] && check_git_repo_available "$GITCODE_REPO_URL"; then
    fallback_available=1
  fi

  if [ "$fallback_available" -eq 1 ]; then
    echo "⚠️ 当前源克隆失败，正在尝试使用 GitCode 国内镜像源兜底..."
    echo "⚠️ 注意：GitCode 镜像可能不是最新版本。"
    rm -rf "$INSTALL_DIR"
    if git clone "$GITCODE_REPO_URL" "$INSTALL_DIR"; then
      REPO_URL="$GITCODE_REPO_URL"
      REPO_SOURCE_EFFECTIVE="gitcode"
      echo "⚠️ 当前安装已切换到 GitCode 国内镜像源。"
      print_repo_source_message "$REPO_SOURCE_EFFECTIVE"
      return 0
    fi
  fi

  return 1
}

prepare_repo_source_selection() {
  validate_positive_integer "$GITHUB_SLOW_THRESHOLD_SECONDS" "HERMES_ZH_GITHUB_SLOW_THRESHOLD_SECONDS"
  validate_channel
  prompt_repo_source_if_needed
  validate_repo_source
  print_repo_source_strategy
}

prepare_existing_repo() {
  local current_origin=""
  local inferred_source=""
  local target_url=""

  current_origin=$(get_existing_origin_url)
  CURRENT_REPO_URL="$current_origin"

  if [ "$REPO_SOURCE_FROM_ENV" -eq 1 ] && [ "$REPO_SOURCE" != "auto" ]; then
    target_url=$(get_repo_url_for_source "$REPO_SOURCE")
    if [ -z "$target_url" ]; then
      echo "❌ 错误: 无法确定强制源对应的仓库地址" >&2
      exit 2
    fi
    git remote set-url origin "$target_url"
    CURRENT_REPO_URL="$target_url"
    REPO_SOURCE_EFFECTIVE="$REPO_SOURCE"
    print_repo_source_message "$REPO_SOURCE_EFFECTIVE"
    return 0
  fi

  if [ "$REPO_SOURCE" = "auto" ]; then
    inferred_source=$(infer_repo_source_from_url "$current_origin")
    REPO_SOURCE_EFFECTIVE="$inferred_source"
    print_repo_source_message "existing"
    echo "当前 origin: ${current_origin:-未设置}"
    return 0
  fi

  if [ "$REPO_SOURCE_FROM_ENV" -eq 1 ]; then
    target_url=$(get_repo_url_for_source "$REPO_SOURCE")
    if [ -n "$target_url" ]; then
      git remote set-url origin "$target_url"
      CURRENT_REPO_URL="$target_url"
      REPO_SOURCE_EFFECTIVE="$REPO_SOURCE"
      print_repo_source_message "$REPO_SOURCE_EFFECTIVE"
      return 0
    fi
  fi

  inferred_source=$(infer_repo_source_from_url "$current_origin")
  REPO_SOURCE_EFFECTIVE="$inferred_source"
  print_repo_source_message "existing"
  echo "当前 origin: ${current_origin:-未设置}"
}

repo_has_local_changes() {
  [ -n "$(git status --porcelain --untracked-files=all 2>/dev/null)" ]
}

ensure_existing_user_data_snapshot() {
  if [ -n "$EXISTING_USER_DATA_SNAPSHOT" ]; then
    return 0
  fi

  EXISTING_USER_DATA_SNAPSHOT="$(backup_existing_user_data || true)"
  if [ -n "$EXISTING_USER_DATA_SNAPSHOT" ]; then
    echo "  已保存旧配置快照: $EXISTING_USER_DATA_SNAPSHOT"
    echo "  安装过程会先使用干净配置继续；安装完成后再询问是否导入旧配置。"
  fi
}

print_manual_repo_mismatch_instructions() {
  echo "⚠️ 当前安装大概率来自官方脚本的 main 分支，与当前汉化 stable 基线不匹配。"
  echo "汉化 stable 只支持官方发布版基线，不直接跟随 main。"
  echo "当前安装 commit: ${CURRENT_REPO_COMMIT:-unknown}"
  echo "汉化目标版本: ${PATCH_HERMES_VERSION:-unknown}"
  if [ -n "$PATCH_BASE_REF" ]; then
    echo "汉化基线 tag: $PATCH_BASE_REF"
  fi
  if [ -n "$PATCH_BASELINE_COMMIT" ]; then
    echo "汉化基线 commit: $PATCH_BASELINE_COMMIT"
  fi
  echo ""
  echo "如需手动处理，请先切换到匹配的官方发布版，再重新运行汉化安装："
  echo "  cd $INSTALL_DIR"
  echo "  git fetch origin \"$PATCH_BASE_REF\""
  echo "  git checkout \"$PATCH_BASELINE_COMMIT\""
  echo "  curl -fsSL $PATCH_REPO/install-zh.sh | bash"
  echo ""
  echo "你现有的 ~/.hermes 配置不会被改动。"
}

handle_existing_repo_mismatch() {
  local action=""

  action=$(prompt_repo_mismatch_action)
  case "$action" in
    auto)
      ensure_existing_user_data_snapshot
      return 0
      ;;
    manual)
      print_manual_repo_mismatch_instructions
      exit 0
      ;;
    *)
      echo "❌ 错误: 无法识别版本错配处理策略: $action" >&2
      exit 2
      ;;
  esac
}

recreate_repo_from_selected_source() {
  local repo_parent=""

  repo_parent="$(dirname "$INSTALL_DIR")"
  cd "$repo_parent"
  echo "  正在备份当前目录并重新获取干净源码..."
  mv "$INSTALL_DIR" "${INSTALL_DIR}.backup-$(date +%Y%m%d-%H%M%S)"

  if [ "$PATCH_BASE_CHANNEL" = "stable" ]; then
    if ! clone_with_stable_base; then
      echo "❌ stable 源码克隆失败，无法继续安装" >&2
      exit 1
    fi
  else
    select_repo_url
    if ! clone_with_selected_repo; then
      echo "❌ 源码克隆失败，无法继续安装" >&2
      exit 1
    fi
  fi

  if [ ! -d "$INSTALL_DIR/.git" ]; then
    echo "❌ 源码克隆失败，无法继续安装" >&2
    exit 1
  fi

  cd "$INSTALL_DIR"
  CURRENT_REPO_URL="$(get_existing_origin_url)"
}

existing_repo_needs_recreation_before_checkout() {
  CURRENT_REPO_COMMIT=$(detect_git_commit)

  if [ "$CURRENT_REPO_COMMIT" = "$PATCH_BASELINE_COMMIT" ]; then
    return 1
  fi

  repo_has_local_changes
}

ensure_supported_commit_available() {
  local commit="$1"

  if git cat-file -e "$commit^{commit}" >/dev/null 2>&1; then
    return 0
  fi

  if git fetch origin "$commit"; then
    return 0
  fi

  if [ "$REPO_SOURCE_EFFECTIVE" = "gitcode" ]; then
    echo "⚠️ GitCode 镜像暂未同步该汉化包对应版本，正在回退到 GitHub 官方源。"
    git remote set-url origin "$OFFICIAL_REPO_URL"
    CURRENT_REPO_URL="$OFFICIAL_REPO_URL"
    REPO_SOURCE_EFFECTIVE="github"
    if git fetch origin "$commit"; then
      return 0
    fi
  fi

  return 1
}

checkout_manifest_supported_commit() {
  if [ "$HERMES_ZH_CHANNEL" = "dev" ]; then
    echo "⚠️ dev 通道使用用户指定 HERMES_REF，不保证汉化补丁兼容。"
    git fetch origin "$HERMES_REF" 2>/dev/null || true
    if git checkout "$HERMES_REF"; then
      CURRENT_REPO_COMMIT=$(detect_git_commit)
      return 0
    fi
    echo "❌ 无法 checkout HERMES_REF: $HERMES_REF" >&2
    exit 1
  fi

  if candidate_channel_requested; then
    echo "⚠️ 已按 HERMES_ZH_USE_LATEST_MAIN 跳过固定版本切换，可能需要更新汉化补丁。"
    echo "⚠️ 当前将尝试使用仓库当前 main，不能保证汉化补丁兼容。"
    return 0
  fi

  if [ "$PATCH_BASE_CHANNEL" = "stable" ]; then
    if [ "$PATCH_BASE_REF" = "main" ]; then
      echo "❌ stable 通道绝不会使用 main，请检查 manifest。" >&2
      exit 1
    fi
    verify_repo_tag_consistency "$PATCH_BASE_REF"
  fi

  if ! is_hex_commit "$PATCH_BASELINE_COMMIT"; then
    echo "❌ 补丁清单缺少有效的 generated_from commit，无法确定汉化包支持的源码版本" >&2
    exit 1
  fi

  CURRENT_REPO_COMMIT=$(detect_git_commit)
  if [ "$CURRENT_REPO_COMMIT" = "$PATCH_BASELINE_COMMIT" ]; then
    echo "  当前源码已位于 $(patch_release_label "$PATCH_VERSION") 的汉化支持版本。"
    return 0
  fi

  if [ "$PATCH_BASE_CHANNEL" = "stable" ]; then
    handle_existing_repo_mismatch
  fi

  if existing_repo_needs_recreation_before_checkout; then
    echo "⚠️ 检测到现有 Hermes 仓库包含本地修改，无法安全切换到新的汉化基线版本。"
    recreate_repo_from_selected_source
    CURRENT_REPO_COMMIT=$(detect_git_commit)
    if [ "$CURRENT_REPO_COMMIT" = "$PATCH_BASELINE_COMMIT" ]; then
      echo "  已重新获取干净源码，并切换到 $(patch_release_label "$PATCH_VERSION") 的汉化支持版本。"
      return 0
    fi
  fi

  if ! ensure_supported_commit_available "$PATCH_BASELINE_COMMIT"; then
    echo "❌ 无法获取汉化包对应版本所需的源码内容" >&2
    exit 1
  fi

  echo "  当前源码属于 $(patch_release_label "$PATCH_VERSION")，将自动切换到汉化补丁支持的固定版本。"
  if git checkout "$PATCH_BASELINE_COMMIT"; then
    CURRENT_REPO_COMMIT=$(detect_git_commit)
    verify_checked_out_base_commit "$PATCH_BASELINE_COMMIT"
    return 0
  fi

  echo "❌ 无法切换到汉化补丁支持的固定版本" >&2
  echo "如需继续使用最新 main，请设置 HERMES_ZH_USE_LATEST_MAIN=1 后重试，但汉化补丁可能无法应用。" >&2
  exit 1
}

prepare_patch_assets() {
  PATCH_ASSET_BASE_URL="$PATCH_REPO/patches/versions/$PATCH_VERSION"
  CURRENT_REPO_COMMIT=$(detect_git_commit)

  if is_hex_commit "$PATCH_BASELINE_COMMIT"; then
    PATCH_ASSET_BASE_URL="$PATCH_REPO/patches/versions/$PATCH_VERSION/$PATCH_BASELINE_COMMIT"
  fi
}

echo "========================================"
echo "    Hermes Agent 中文一键安装"
echo "========================================"
echo "🔗 更多优化脚本访问：www.hermesgo.com"
echo ""
echo "📋 第 1 步：选择汉化版本"
prompt_patch_version_selection
PATCH_VERSION="$SELECTED_PATCH_VERSION"
download_patch_manifest "$PATCH_VERSION"
echo "  已选择：Hermes Agent 中文汉化（针对 Releases v$PATCH_HERMES_VERSION）"
echo ""
echo "🔍 第 2 步：检查系统环境..."

if ! command -v git >/dev/null 2>&1; then
  echo "❌ 错误: 需要安装 git" >&2
  exit 1
fi
echo "  ✅ Git 已安装"

if ! command -v curl >/dev/null 2>&1; then
  echo "❌ 错误: 需要安装 curl" >&2
  exit 1
fi
echo "  ✅ curl 已安装"

if ! command -v bash >/dev/null 2>&1; then
  echo "❌ 错误: 需要安装 bash" >&2
  exit 1
fi
echo "  ✅ Bash 已安装"

echo ""
prepare_repo_source_selection

echo ""
echo "📦 准备 Hermes Agent 源码..."
mkdir -p "$(dirname "$INSTALL_DIR")"

if [ -d "$INSTALL_DIR/.git" ]; then
  cd "$INSTALL_DIR"
  prepare_existing_repo
else
  if [ -d "$INSTALL_DIR" ]; then
    echo "  备份现有目录..."
    mv "$INSTALL_DIR" "${INSTALL_DIR}.backup-$(date +%Y%m%d-%H%M%S)"
  fi
  if [ "$PATCH_BASE_CHANNEL" = "stable" ]; then
    if ! clone_with_stable_base; then
      echo "❌ stable 源码克隆失败，无法继续安装" >&2
      exit 1
    fi
  else
    select_repo_url
    if ! clone_with_selected_repo; then
      echo "❌ 源码克隆失败，无法继续安装" >&2
      exit 1
    fi
  fi
  if [ ! -d "$INSTALL_DIR/.git" ]; then
    echo "❌ 源码克隆失败，无法继续安装" >&2
    exit 1
  fi
  cd "$INSTALL_DIR"
fi

CURRENT_REPO_URL=${CURRENT_REPO_URL:-$(get_existing_origin_url)}
if [ -z "${REPO_SOURCE_EFFECTIVE:-}" ] || [ "$REPO_SOURCE_EFFECTIVE" = "unknown" ]; then
  REPO_SOURCE_EFFECTIVE=$(infer_repo_source_from_url "$CURRENT_REPO_URL")
fi

echo ""
echo "🔒 按汉化包锁定源码版本..."
checkout_manifest_supported_commit
prepare_patch_assets

echo ""
echo "🔍 检测 Hermes 版本..."
if VERSION=$(detect_hermes_version "pyproject.toml"); then
  echo "  当前版本: $VERSION"
  if [ -n "$PATCH_HERMES_VERSION" ] && [ "$VERSION" != "$PATCH_HERMES_VERSION" ]; then
    echo "⚠️ 当前源码版本与汉化包声明的版本不同，继续以汉化包对应版本为准。"
  fi
else
  echo "⚠️ 未能检测 Hermes 版本，继续以汉化包对应版本为准。"
fi

echo ""
echo "📥 下载汉化补丁 v$PATCH_VERSION..."
curl -fsSL "$PATCH_ASSET_BASE_URL/hermes-setup-zh.patch" -o "$TMP_DIR/hermes-setup-zh.patch"
curl -fsSL "$PATCH_ASSET_BASE_URL/zh_patch.py" -o "$TMP_DIR/zh_patch.py"
[ -s "$TMP_DIR/hermes-setup-zh.patch" ] || { echo "❌ 补丁文件下载失败" >&2; exit 1; }
[ -s "$TMP_DIR/zh_patch.py" ] || { echo "❌ 汉化模块下载失败" >&2; exit 1; }

echo ""
echo "🔄 备份原文件..."
BACKUP_DIR="$INSTALL_DIR/patches/backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
for f in hermes_cli/setup.py hermes_cli/tools_config.py hermes_cli/gateway.py hermes_cli/main.py hermes_cli/auth.py hermes_cli/config.py setup-hermes.sh; do
  if [ -f "$f" ]; then
    mkdir -p "$BACKUP_DIR/$(dirname "$f")"
    cp "$f" "$BACKUP_DIR/$f"
  fi
done

echo ""
echo "🔧 应用汉化补丁..."
if git apply --check --exclude=hermes_cli/main.py "$TMP_DIR/hermes-setup-zh.patch" >/dev/null 2>&1; then
  git apply --exclude=hermes_cli/main.py "$TMP_DIR/hermes-setup-zh.patch"
elif git apply --reverse --check --exclude=hermes_cli/main.py "$TMP_DIR/hermes-setup-zh.patch" >/dev/null 2>&1; then
  echo "ℹ️ Patch already applied, skipping."
else
  print_patch_guidance_for_source "patch" "${VERSION:-未知}"
  echo "❌ 补丁应用失败：当前源码与汉化补丁版本不匹配" >&2
  exit 1
fi

echo "📦 安装汉化模块..."
cp "$TMP_DIR/zh_patch.py" "$INSTALL_DIR/hermes_cli/zh_patch.py"

echo "🌐 汉化 hermes_cli/main.py 首次启动提示..."
if find_python3_for_localizer; then
  localize_main_startup_prompt "$INSTALL_DIR" "$LOCALIZE_PYTHON"
else
  echo "⚠️ 未找到可用的 Python 3，本轮先跳过 hermes_cli/main.py 启动提示汉化"
fi

echo "🌐 汉化 setup-hermes.sh..."
if find_python3_for_localizer; then
  localize_setup_hermes "$INSTALL_DIR" "$LOCALIZE_PYTHON"
else
  echo "⚠️ 未找到可用的 Python 3，本轮跳过 setup-hermes.sh 文案汉化"
fi

echo ""
echo "🚀 执行官方安装脚本..."
if [ -f "setup-hermes.sh" ]; then
  if [ -t 0 ]; then
    bash setup-hermes.sh
  else
    printf 'n\nn\n' | bash setup-hermes.sh
  fi
else
  echo "⚠️ 未找到 setup-hermes.sh，跳过官方安装步骤"
  echo "  请手动运行: hermes setup"
fi

if [ -z "$LOCALIZE_PYTHON" ] && [ -x "$INSTALL_DIR/venv/bin/python" ]; then
  echo ""
  echo "🌐 使用安装后的 Python 补做 hermes_cli/main.py 启动提示汉化..."
  localize_main_startup_prompt "$INSTALL_DIR" "$INSTALL_DIR/venv/bin/python"
  echo ""
  echo "🌐 使用安装后的 Python 补做 setup-hermes.sh 汉化..."
  localize_setup_hermes "$INSTALL_DIR" "$INSTALL_DIR/venv/bin/python"
fi

if [ -n "$EXISTING_USER_DATA_SNAPSHOT" ]; then
  echo ""
  IMPORT_EXISTING_CONFIG_DECISION=$(prompt_import_existing_config)
  if [ "$IMPORT_EXISTING_CONFIG_DECISION" = "yes" ]; then
    restore_existing_user_data "$EXISTING_USER_DATA_SNAPSHOT"
    EXISTING_USER_DATA_RESTORED=1
    echo "  已导入旧配置快照，运行时日志和缓存不会恢复。"
  else
    echo "  已保留旧配置快照，当前不会导入到新的汉化安装。"
  fi
fi

echo ""
echo "🎉 恭喜！Hermes Agent 中文版本安装完成！"
echo "🔗 更多优化脚本与更新说明：www.hermesgo.com"
echo "💡 如需查看更多安装优化方案，请访问：www.hermesgo.com"
echo ""
echo "========================================"
echo "安装目录: $INSTALL_DIR"
echo "源码来源: $(effective_source_label "$REPO_SOURCE_EFFECTIVE")"
if [ -n "$EXISTING_USER_DATA_SNAPSHOT" ]; then
  if [ "$EXISTING_USER_DATA_RESTORED" -eq 1 ]; then
    echo "配置导入: 已从快照恢复"
  else
    echo "配置导入: 未导入，旧配置快照保留在 $EXISTING_USER_DATA_SNAPSHOT"
  fi
fi
echo "========================================"
echo "常用命令:"
echo "  cd $INSTALL_DIR"
echo "  hermes setup      # 配置向导（中文界面）"
echo "  hermes chat       # 开始聊天"
echo "  hermes gateway install  # 安装消息网关"
echo ""
echo "如果提示 hermes 命令不存在，请重启终端或运行:"
echo "  source ~/.bashrc  或  source ~/.zshrc"
