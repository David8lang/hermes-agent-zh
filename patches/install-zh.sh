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
INSTALL_DIR="$HOME/.hermes/hermes-agent"
PATCH_REPO="https://raw.githubusercontent.com/David8lang/hermes-agent-zh/main"
DEFAULT_PATCH_VERSION="0.13"
GITHUB_SLOW_THRESHOLD_SECONDS="${HERMES_ZH_GITHUB_SLOW_THRESHOLD_SECONDS:-6}"

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

  GIT_TERMINAL_PROMPT=0 git ls-remote --tags "$url" "$direct_ref" "$peeled_ref" |
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
}

verify_repo_tag_consistency() {
  local tag="$1"
  local github_commit=""
  local gitcode_commit=""

  github_commit=$(resolve_tag_commit "$tag" "$OFFICIAL_REPO_URL") || {
    echo "❌ GitHub 官方源不存在 stable tag: $tag" >&2
    exit 1
  }

  gitcode_commit=$(resolve_tag_commit "$tag" "$GITCODE_REPO_URL" 2>/dev/null || true)
  if [ -n "$gitcode_commit" ] && [ "$gitcode_commit" != "$github_commit" ]; then
    echo "❌ GitCode 与 GitHub 的同名 tag 指向不同 commit，已终止安装。" >&2
    echo "  tag: $tag" >&2
    echo "  GitHub:  $github_commit" >&2
    echo "  GitCode: $gitcode_commit" >&2
    echo "请等待 GitCode 镜像同步后重试，或临时强制使用 GitHub 官方源。" >&2
    exit 1
  fi

  STABLE_GITHUB_COMMIT="$github_commit"
  STABLE_GITCODE_COMMIT="$gitcode_commit"
  if [ -n "$gitcode_commit" ]; then
    STABLE_CLONE_URL="$GITCODE_REPO_URL"
    REPO_SOURCE_EFFECTIVE="gitcode"
  else
    STABLE_CLONE_URL="$OFFICIAL_REPO_URL"
    REPO_SOURCE_EFFECTIVE="github"
    echo "⚠️ GitCode 镜像缺少 stable tag $tag，回退到 GitHub 官方源。"
  fi
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
      echo "   新安装会优先尝试 GitHub 官方源；如果不可用或连接较慢，则自动切换到 GitCode 国内镜像源。"
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
  echo "    默认选项，先测速再决定使用 GitHub 或 GitCode。" >/dev/tty
  echo "" >/dev/tty
  prompt_via_tty selection "默认：3 > "
  case "${selection:-3}" in
    ""|3) REPO_SOURCE="auto" ;;
    1) REPO_SOURCE="github" ;;
    2) REPO_SOURCE="gitcode" ;;
    *)
      echo "⚠️ 输入无效，已使用默认自动测速模式。" >/dev/tty
      REPO_SOURCE="auto"
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
      repo_status=$(check_git_repo_status "$OFFICIAL_REPO_URL")
      case "$repo_status" in
        ok)
          REPO_URL="$OFFICIAL_REPO_URL"
          REPO_SOURCE_EFFECTIVE="github"
          echo "✅ GitHub 官方源连接正常，使用官方源。"
          print_repo_source_message "$REPO_SOURCE_EFFECTIVE"
          ;;
        slow)
          echo "⚠️ 检测到 GitHub 连接较慢，正在切换到 GitCode 国内镜像源..."
          echo "⚠️ 注意：GitCode 镜像可能不是最新版本。"
          REPO_URL="$GITCODE_REPO_URL"
          REPO_SOURCE_EFFECTIVE="gitcode"
          print_repo_source_message "$REPO_SOURCE_EFFECTIVE"
          ;;
        unavailable)
          echo "⚠️ GitHub 官方源暂时不可用，正在切换到 GitCode 国内镜像源..."
          echo "⚠️ 注意：GitCode 镜像可能不是最新版本。"
          REPO_URL="$GITCODE_REPO_URL"
          REPO_SOURCE_EFFECTIVE="gitcode"
          print_repo_source_message "$REPO_SOURCE_EFFECTIVE"
          ;;
        *)
          echo "❌ 错误: 无法识别 GitHub 连接状态: $repo_status" >&2
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

  verify_repo_tag_consistency "$PATCH_BASE_REF"
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
  if [ "$HERMES_ZH_CHANNEL" = "stable" ]; then
    echo "📋 汉化通道：stable。stable 通道绝不会使用 main，只使用官方日期 tag。"
    return 0
  fi
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
echo "🔍 检查系统环境..."

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

if VERSION=$(detect_hermes_version "pyproject.toml"); then
  PATCH_VERSION=$(select_patch_version_for_repo "$VERSION")
else
  PATCH_VERSION="$DEFAULT_PATCH_VERSION"
fi
download_patch_manifest "$PATCH_VERSION"

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
if git apply --check "$TMP_DIR/hermes-setup-zh.patch" >/dev/null 2>&1; then
  git apply "$TMP_DIR/hermes-setup-zh.patch"
elif git apply --reverse --check "$TMP_DIR/hermes-setup-zh.patch" >/dev/null 2>&1; then
  echo "ℹ️ Patch already applied, skipping."
else
  print_patch_guidance_for_source "patch" "${VERSION:-未知}"
  echo "❌ 补丁应用失败：当前源码与汉化补丁版本不匹配" >&2
  exit 1
fi

echo "📦 安装汉化模块..."
cp "$TMP_DIR/zh_patch.py" "$INSTALL_DIR/hermes_cli/zh_patch.py"

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
  echo "🌐 使用安装后的 Python 补做 setup-hermes.sh 汉化..."
  localize_setup_hermes "$INSTALL_DIR" "$INSTALL_DIR/venv/bin/python"
fi

echo ""
echo "🎉 恭喜！Hermes Agent 中文版本安装完成！"
echo "🔗 更多优化脚本与更新说明：www.hermesgo.com"
echo "💡 如需查看更多安装优化方案，请访问：www.hermesgo.com"
echo ""
echo "========================================"
echo "安装目录: $INSTALL_DIR"
echo "源码来源: $(effective_source_label "$REPO_SOURCE_EFFECTIVE")"
echo "========================================"
echo "常用命令:"
echo "  cd $INSTALL_DIR"
echo "  hermes setup      # 配置向导（中文界面）"
echo "  hermes chat       # 开始聊天"
echo "  hermes gateway install  # 安装消息网关"
echo ""
echo "如果提示 hermes 命令不存在，请重启终端或运行:"
echo "  source ~/.bashrc  或  source ~/.zshrc"
