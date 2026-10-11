#!/usr/bin/env bash
# leaspec helpers — 公共函数库
set -euo pipefail

LEASPEC_DIR="${LEASPEC_DIR:-leaspec}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 尝试定位 skills 和 templates 目录
# 源码仓库中它们在 ../skills 和 ../templates
# 目标项目中它们在 ../../skills 和 ../../templates（从 leaspec/scripts/ 视角）
# 也可能在 ../../skills 和 ../../templates（从 leaspec/scripts/ 视角）
_find_adjacent_dir() {
  local dirname="$1"
  local candidate
  for candidate in \
    "$SCRIPT_DIR/../$dirname" \
    "$SCRIPT_DIR/../../$dirname" \
    "$SCRIPT_DIR/../../../$dirname"; do
    if [ -d "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done
  echo ""
}

SKILLS_DIR="$(_find_adjacent_dir "skills")"
TEMPLATES_DIR="$(_find_adjacent_dir "templates")"

# 颜色输出
red()    { echo -e "\033[31m$*\033[0m"; }
green()  { echo -e "\033[32m$*\033[0m"; }
yellow() { echo -e "\033[33m$*\033[0m"; }
bold()   { echo -e "\033[1m$*\033[0m"; }

# 检测当前目录是否为项目根目录
find_project_root() {
  local dir="$1"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/.git/config" ] || [ -f "$dir/package.json" ] || [ -f "$dir/Cargo.toml" ] || [ -f "$dir/go.mod" ] || [ -f "$dir/pyproject.toml" ]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  # 回退到当前目录
  pwd
}

# 检测项目使用的 AI agent
detect_agent() {
  local project_root="${1:-.}"

  # Claude Code
  if [ -d "$project_root/.claude" ] || [ -f "$project_root/CLAUDE.md" ]; then
    echo "claude"
    return 0
  fi

  # Codex (supports both .agents/ and .codex/)
  if [ -d "$project_root/.agents" ] || [ -d "$project_root/.codex" ] || [ -f "$project_root/AGENTS.md" ]; then
    echo "codex"
    return 0
  fi

  # 默认按优先级顺序检测目录存在性
  for agent_dir in ".claude" ".agents"; do
    if [ -d "$project_root/$agent_dir" ]; then
      case "$agent_dir" in
        ".claude") echo "claude"; return 0 ;;
        ".agents") echo "codex"; return 0 ;;
      esac
    fi
  done

  echo ""
}

# 检测项目中所有可用的 AI agent（返回多个）
detect_agents() {
  local project_root="${1:-.}"
  local agents=()

  # Claude Code
  if [ -d "$project_root/.claude" ] || [ -f "$project_root/CLAUDE.md" ]; then
    agents+=("claude")
  fi

  # Codex (supports both .agents/ and .codex/)
  if [ -d "$project_root/.agents" ] || [ -d "$project_root/.codex" ] || [ -f "$project_root/AGENTS.md" ]; then
    agents+=("codex")
  fi

  echo "${agents[@]}"
}

# 获取 agent 对应的 skills 目录
get_agent_skills_dir() {
  local agent="$1"
  case "$agent" in
    claude) echo ".claude/skills" ;;
    codex)  echo ".agents/skills" ;;
    *)      echo "" ;;
  esac
}

# 获取 agent 对应的 context 文件
get_agent_context_file() {
  local agent="$1"
  case "$agent" in
    claude) echo "CLAUDE.md" ;;
    codex)  echo "AGENTS.md" ;;
    *)      echo "" ;;
  esac
}

# 获取当前变更编号（从 leaspec/changes/ 中查找最大编号 + 1）
get_next_change_number() {
  local leaspec_root="${1:-$LEASPEC_DIR}"
  local max=0

  if [ -d "$leaspec_root/changes" ]; then
    for dir in "$leaspec_root/changes"/*/; do
      [ -d "$dir" ] || continue
      local name
      name=$(basename "$dir")
      local num
      num=$(printf '%s\n' "$name" | sed -n 's/^\([0-9][0-9]*\).*/\1/p')
      num="${num:-0}"
      num=$((10#$num))
      if [ "$num" -gt "$max" ]; then
        max=$num
      fi
    done
  fi

  printf "%03d" $((max + 1))
}

# 将名称转为 kebab-case
to_kebab_case() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//'
}

# 安全的文件写入（原子操作）
atomic_write() {
  local content="$1"
  local target="$2"
  local tmpfile
  tmpfile="$(mktemp)"
  echo "$content" > "$tmpfile"
  mv "$tmpfile" "$target"
}

# 直接运行时只分发公开的只读命令；source 时保持函数库行为。
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    get_next_change_number)
      shift
      if [ "$#" -gt 1 ]; then
        echo "用法: helpers.sh get_next_change_number [leaspec-dir]" >&2
        exit 1
      fi
      get_next_change_number "$@"
      ;;
    *)
      echo "用法: helpers.sh get_next_change_number [leaspec-dir]" >&2
      exit 1
      ;;
  esac
fi
