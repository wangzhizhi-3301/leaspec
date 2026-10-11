#!/usr/bin/env bash
# leaspec install/update — 安装或更新 leaspec 到目标项目
set -euo pipefail

# ============================================================
# 路径解析（支持通过根目录软链接调用）
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ "$(basename "$SCRIPT_DIR")" = "scripts" ]; then
  SOURCE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
else
  SOURCE_DIR="$SCRIPT_DIR"
fi

# ============================================================
# 元信息 — 从 SOURCE_DIR/VERSION 读取，单一真相源
# ============================================================
LEASPEC_VERSION=$(cat "$SOURCE_DIR/VERSION" 2>/dev/null || echo "0.0.0")

SKILLS_SRC="$SOURCE_DIR/skills"
TEMPLATES_SRC="$SOURCE_DIR/templates"
SCRIPTS_SRC="$SOURCE_DIR/scripts"

# ============================================================
# 颜色输出（fallback：helpers.sh 可能不可用）
# ============================================================
if declare -f green &>/dev/null; then
  : # helpers.sh 已加载
else
  red()    { echo -e "\033[31m$*\033[0m"; }
  green()  { echo -e "\033[32m$*\033[0m"; }
  yellow() { echo -e "\033[33m$*\033[0m"; }
  bold()   { echo -e "\033[1m$*\033[0m"; }
fi

# ============================================================
# 加载 helpers（如可用）
# ============================================================
HELPERS_SRC="$SOURCE_DIR/scripts/helpers.sh"
if [ -f "$HELPERS_SRC" ]; then
  source "$HELPERS_SRC"
fi

# ============================================================
# 打印用法
# ============================================================
_print_usage() {
  echo "用法: install.sh [选项] <project-root>"
  echo ""
  echo "选项:"
  echo "  --update            强制更新模式（要求 leaspec/ 已存在）"
  echo "  --non-interactive   跳过交互式提示（使用默认值）"
  echo "  --version           显示 leaspec 版本"
  echo "  --help              显示此帮助信息"
  echo ""
  echo "示例:"
  echo "  install.sh /path/to/my-project          # 安装或更新（自动检测）"
  echo "  install.sh --update /path/to/my-project # 强制更新"
  echo "  install.sh --version                    # 显示版本"
}

# ============================================================
# 参数解析
# ============================================================
MODE=""              # "" = 自动检测, "install" = 强制安装, "update" = 强制更新
NON_INTERACTIVE=false
PROJECT_ROOT=""

_parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --update)
        MODE="update"
        shift
        ;;
      --non-interactive)
        NON_INTERACTIVE=true
        shift
        ;;
      --version)
        echo "leaspec version $LEASPEC_VERSION"
        exit 0
        ;;
      --help)
        _print_usage
        exit 0
        ;;
      -*)
        red "未知选项: $1"
        _print_usage
        exit 1
        ;;
      *)
        if [ -z "$PROJECT_ROOT" ]; then
          PROJECT_ROOT="$1"
        else
          red "多余参数: $1"
          _print_usage
          exit 1
        fi
        shift
        ;;
    esac
  done

  if [ -z "$PROJECT_ROOT" ]; then
    red "缺少 <project-root> 参数"
    _print_usage
    exit 1
  fi

  PROJECT_ROOT="$(cd "$PROJECT_ROOT" 2>/dev/null && pwd)" || {
    red "目录不存在: $PROJECT_ROOT"
    exit 1
  }
}

# ============================================================
# 检测事件模式（安装 vs 更新）
# ============================================================
_detect_mode() {
  if [ "$MODE" = "install" ] || [ "$MODE" = "update" ]; then
    return 0
  fi

  if [ -d "$PROJECT_ROOT/leaspec" ]; then
    MODE="update"
  else
    MODE="install"
  fi
}

# ============================================================
# 检测 target 项目中的 agent
# ============================================================
_detect_target_agents() {
  local agents=()

  if [ -d "$PROJECT_ROOT/.claude" ] || [ -f "$PROJECT_ROOT/CLAUDE.md" ]; then
    agents+=("claude")
  fi
  if [ -d "$PROJECT_ROOT/.agents" ] || [ -f "$PROJECT_ROOT/AGENTS.md" ]; then
    agents+=("codex")
  fi

  echo "${agents[@]}"
}

_get_agent_skills_dir() {
  case "$1" in
    claude) echo ".claude/skills" ;;
    codex)  echo ".agents/skills" ;;
    *)      echo "" ;;
  esac
}

_get_agent_context_file() {
  case "$1" in
    claude) echo "CLAUDE.md" ;;
    codex)  echo "AGENTS.md" ;;
    *)      echo "" ;;
  esac
}

# ============================================================
# 更新：覆盖 agent skills 目录
# ============================================================
_update_skills() {
  local agent="$1"
  local skills_dir="$PROJECT_ROOT/$(_get_agent_skills_dir "$agent")"

  echo "  --> 更新 skills: $skills_dir/"

  # 清理旧 leaspec-* skills，保留其他 skill
  if [ -d "$skills_dir" ]; then
    for old_dir in "$skills_dir"/leaspec-*/; do
      [ -d "$old_dir" ] || continue
      rm -rf "$old_dir"
      echo "      移除旧: $(basename "$old_dir")"
    done
  fi

  # 复制最新 skills
  mkdir -p "$skills_dir"
  for skill_dir in "$SKILLS_SRC"/leaspec-*/; do
    [ -d "$skill_dir" ] || continue
    local skill_name
    skill_name=$(basename "$skill_dir")
    local target_dir="$skills_dir/$skill_name"
    mkdir -p "$target_dir"
    cp "$skill_dir/SKILL.md" "$target_dir/SKILL.md"
    echo "      安装: $skill_name"
  done
}

# ============================================================
# 更新：替换 context 文件中的 bootstrap 块
# ============================================================
_validate_bootstrap_markers() {
  awk '
    {
      line = $0
      sub(/^[[:space:]]*/, "", line)
      sub(/[[:space:]]*$/, "", line)
      if (line == "<!-- LEASPEC-BOOTSTRAP-START -->") {
        if (state != 0) invalid = 1
        state = 1
      } else if (line == "<!-- LEASPEC-BOOTSTRAP-END -->") {
        if (state != 1) invalid = 1
        state = 2
      }
    }
    END { exit (invalid || state == 1) ? 1 : 0 }
  ' "$1"
}

_update_bootstrap() (
  local agent="$1"
  local context_file="$(_get_agent_context_file "$agent")"
  local target_file="$PROJECT_ROOT/$context_file"
  local bootstrap_src="$SOURCE_DIR/agents/$agent/bootstrap.md"

  if [ ! -f "$bootstrap_src" ]; then
    yellow "  --> 跳过 bootstrap: 无 $agent bootstrap 源文件"
    return 0
  fi

  if [ ! -f "$target_file" ]; then
    # Context 文件不存在 — 直接创建
    cp "$bootstrap_src" "$target_file"
    echo "  --> 创建: $context_file (bootstrap)"
    return 0
  fi

  if ! _validate_bootstrap_markers "$target_file"; then
    red "  --> 更新失败: $context_file 的 bootstrap 标记不完整或重复，保留原文件" >&2
    return 1
  fi

  # 跟随 context 软链接，替换实际文件而不是破坏链接。
  while [ -L "$target_file" ]; do
    local link
    link=$(readlink "$target_file")
    case "$link" in
      /*) target_file="$link" ;;
      *) target_file="$(dirname "$target_file")/$link" ;;
    esac
  done

  # 检查是否已有 bootstrap 标记
  if grep -Eq '^[[:space:]]*<!-- LEASPEC-BOOTSTRAP-START -->[[:space:]]*$' "$target_file"; then
    # 替换已有 bootstrap 块
    local tmpfile
    tmpfile=$(mktemp "$target_file.leaspec.XXXXXX")
    trap 'rm -f "$tmpfile"' EXIT
    cp -p "$target_file" "$tmpfile"
    : > "$tmpfile"
    local in_block=false

    while :; do
      local line marker has_newline=true
      if ! IFS= read -r line; then
        has_newline=false
        [ -n "$line" ] || break
      fi
      marker="${line#"${line%%[![:space:]]*}"}"
      marker="${marker%"${marker##*[![:space:]]}"}"
      if [ "$marker" = '<!-- LEASPEC-BOOTSTRAP-START -->' ]; then
        # 到达旧块起始 — 跳过直到 END，插入新块
        in_block=true
        # 只插入标记块，避免每次更新重复追加模板的块外前言。
        sed -n '/^<!-- LEASPEC-BOOTSTRAP-START -->$/,/^<!-- LEASPEC-BOOTSTRAP-END -->$/p' "$bootstrap_src" >> "$tmpfile"
        continue
      elif [ "$marker" = '<!-- LEASPEC-BOOTSTRAP-END -->' ]; then
        if $in_block; then
          in_block=false
          continue
        fi
      fi

      if ! $in_block; then
        printf '%s' "$line" >> "$tmpfile"
        if $has_newline; then
          printf '\n' >> "$tmpfile"
        fi
      fi
    done < "$target_file"

    mv "$tmpfile" "$target_file"
    echo "  --> 更新: $context_file (bootstrap 已替换)"
  else
    # 无标记 — 追加到文件末尾
    echo "" >> "$target_file"
    cat "$bootstrap_src" >> "$target_file"
    echo "  --> 追加: bootstrap 到 $context_file"
  fi
)

# ============================================================
# 更新：覆盖 scripts
# ============================================================
_update_scripts() {
  local target="$PROJECT_ROOT/leaspec/scripts"
  mkdir -p "$target"

  echo "  --> 更新 scripts: $target/"
  for script in init.sh validate.sh status.sh helpers.sh install.sh; do
    if [ -f "$SCRIPTS_SRC/$script" ]; then
      cp "$SCRIPTS_SRC/$script" "$target/$script"
      echo "      $script"
    fi
  done
  chmod +x "$target/"*.sh
}

# ============================================================
# 更新：覆盖 templates
# ============================================================
_update_templates() {
  local target="$PROJECT_ROOT/leaspec/templates"
  mkdir -p "$target"

  echo "  --> 更新 templates: $target/"
  for tmpl in "$TEMPLATES_SRC"/*.md; do
    [ -f "$tmpl" ] || continue
    local name
    name=$(basename "$tmpl")
    cp "$tmpl" "$target/$name"
    echo "      $name"
  done

  yellow "  ⚠ 模板已覆盖，如果你对模板做过定制，请检查 git diff"
}

# ============================================================
# 安装：完整安装流程
# ============================================================
_do_install() {
  echo ""
  bold "============================================"
  bold " leaspec v$LEASPEC_VERSION — 安装"
  bold "============================================"
  echo ""
  echo "目标项目: $PROJECT_ROOT"
  echo ""

  # 1. 检测 agent
  local agents
  agents=($(_detect_target_agents))

  if [ ${#agents[@]} -eq 0 ]; then
    if $NON_INTERACTIVE; then
      red "未检测到已知 AI agent，非交互模式下无法继续"
      exit 1
    fi
    yellow "未检测到已知 AI agent"
    read -rp "选择 (claude/codex): " agent_choice
    if [ "$agent_choice" != "claude" ] && [ "$agent_choice" != "codex" ]; then
      red "无效选择"
      exit 1
    fi
    agents=("$agent_choice")
  fi

  echo "检测到 agent: ${agents[*]}"
  echo ""

  # 2. 安装 skills + bootstrap
  for agent in "${agents[@]}"; do
    echo "--- 安装到 $agent ---"

    # 2a. Skills
    local skills_dir="$PROJECT_ROOT/$(_get_agent_skills_dir "$agent")"
    mkdir -p "$skills_dir"
    for skill_dir in "$SKILLS_SRC"/leaspec-*/; do
      [ -d "$skill_dir" ] || continue
      local skill_name
      skill_name=$(basename "$skill_dir")
      local target_skill_dir="$skills_dir/$skill_name"
      mkdir -p "$target_skill_dir"
      cp "$skill_dir/SKILL.md" "$target_skill_dir/SKILL.md"
      echo "  $skill_name → $skills_dir/$skill_name/"
    done

    # 2b. Bootstrap
    local context_file="$PROJECT_ROOT/$(_get_agent_context_file "$agent")"
    local bootstrap_src="$SOURCE_DIR/agents/$agent/bootstrap.md"
    if [ -f "$bootstrap_src" ]; then
      if [ -f "$context_file" ]; then
        if ! grep -q "leaspec" "$context_file" 2>/dev/null; then
          echo "" >> "$context_file"
          cat "$bootstrap_src" >> "$context_file"
          echo "  bootstrap → $(_get_agent_context_file "$agent")"
        else
          echo "  bootstrap 已存在，跳过"
        fi
      else
        cp "$bootstrap_src" "$context_file"
        echo "  bootstrap → $(_get_agent_context_file "$agent")"
      fi
    fi
  done

  # 3. 复制 scripts
  echo "--- 安装 scripts ---"
  mkdir -p "$PROJECT_ROOT/leaspec/scripts"
  for script in init.sh validate.sh status.sh helpers.sh install.sh; do
    if [ -f "$SCRIPTS_SRC/$script" ]; then
      cp "$SCRIPTS_SRC/$script" "$PROJECT_ROOT/leaspec/scripts/"
      echo "  $script → leaspec/scripts/$script"
    fi
  done
  chmod +x "$PROJECT_ROOT/leaspec/scripts/"*.sh

  # 4. 复制 templates
  echo "--- 安装 templates ---"
  mkdir -p "$PROJECT_ROOT/leaspec/templates"
  cp "$TEMPLATES_SRC"/*.md "$PROJECT_ROOT/leaspec/templates/"
  echo "  全部模板 → leaspec/templates/"

  # 5. 写入 VERSION
  echo "$LEASPEC_VERSION" > "$PROJECT_ROOT/leaspec/VERSION"
  echo ""
  green "安装完成! leaspec v$LEASPEC_VERSION"
}

# ============================================================
# 更新：增量更新流程
# ============================================================
_do_update() {
  echo ""
  bold "============================================"
  bold " leaspec — 更新"
  bold "============================================"
  echo ""
  echo "目标项目: $PROJECT_ROOT"

  # 版本检查
  local old_version="<未知>"
  if [ -f "$PROJECT_ROOT/leaspec/VERSION" ]; then
    old_version=$(cat "$PROJECT_ROOT/leaspec/VERSION")
  fi
  echo "当前版本: $old_version → 新版本: $LEASPEC_VERSION"
  echo ""

  # 确认
  if ! $NON_INTERACTIVE; then
    read -rp "确认更新? [Y/n] " confirm
    if [[ "$confirm" =~ ^[Nn] ]]; then
      yellow "已取消"
      exit 0
    fi
  fi
  echo ""

  # 1. 检测 agent
  local agents
  agents=($(_detect_target_agents))

  if [ ${#agents[@]} -eq 0 ]; then
    if $NON_INTERACTIVE; then
      red "未检测到 agent，跳过 skills 更新"
    else
      read -rp "未检测到 agent，选择 (claude/codex/skip): " agent_choice
      if [ "$agent_choice" = "claude" ] || [ "$agent_choice" = "codex" ]; then
        agents=("$agent_choice")
      fi
    fi
  fi

  # 2. 更新 skills + bootstrap
  for agent in "${agents[@]}"; do
    echo "--- 更新 $agent ---"
    _update_skills "$agent"
    _update_bootstrap "$agent"
  done

  # 3. 更新 scripts
  echo "--- 更新 scripts ---"
  _update_scripts

  # 4. 更新 templates
  echo "--- 更新 templates ---"
  _update_templates

  # 5. 写入 VERSION
  echo "$LEASPEC_VERSION" > "$PROJECT_ROOT/leaspec/VERSION"

  # 6. 受保护的内容
  echo ""
  echo "--- 保持不变 ---"
  echo "  leaspec/config.yaml      (项目配置)"
  echo "  leaspec/constitution.md  (项目宪法)"
  echo "  leaspec/specs/           (规范文件)"
  echo "  leaspec/changes/         (活跃变更)"
  echo "  leaspec/archive/         (归档记录)"

  echo ""
  green "更新完成! leaspec $old_version → $LEASPEC_VERSION"
}

# ============================================================
# 打印后续步骤
# ============================================================
_print_next_steps() {
  echo ""
  echo "后续步骤:"
  echo "  1. 重启 AI agent 以加载最新 skills"
  if [ "$MODE" = "install" ]; then
    echo "  2. 运行 /leaspec-init 初始化项目规范结构"
  else
    echo "  2. 运行 /leaspec-new <描述> 开始使用"
  fi
}

# ============================================================
# 主流程
# ============================================================
main() {
  _parse_args "$@"

  local agents_src="$SOURCE_DIR/agents"
  if [ ! -d "$agents_src" ]; then
    red "无法找到 agents/ 目录，请确保从 leaspec 源码仓库运行"
    red "SOURCE_DIR=$SOURCE_DIR"
    exit 1
  fi

  _detect_mode

  if [ "$MODE" = "update" ]; then
    if [ ! -d "$PROJECT_ROOT/leaspec" ]; then
      red "更新失败: $PROJECT_ROOT/leaspec/ 不存在"
      red "请先运行 install.sh <project-root> 安装，或去掉 --update 标志"
      exit 1
    fi
    _do_update
  else
    if [ -d "$PROJECT_ROOT/leaspec" ]; then
      if $NON_INTERACTIVE; then
        _do_update
      else
        yellow "leaspec/ 已存在"
        read -rp "执行更新? [Y/n] " choice
        if [[ "$choice" =~ ^[Nn] ]]; then
          yellow "已取消"
          exit 0
        fi
        _do_update
      fi
    else
      _do_install
    fi
  fi

  _print_next_steps
}

main "$@"
