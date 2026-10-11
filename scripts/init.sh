#!/usr/bin/env bash
# leaspec init — 在目标项目中初始化 leaspec/ 目录结构
set -euo pipefail

# Require Bash 4+ (macOS default is 3.2)
if [ -z "${BASH_VERSION:-}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
  echo "错误: leaspec 需要 Bash 4+，当前版本: ${BASH_VERSION:-unknown}" >&2
  echo "请使用 Homebrew 安装: brew install bash" >&2
  exit 1
fi

# Detect gum for rich terminal UI (proper UTF-8 handling)
_HAS_GUM="false"
if command -v gum &>/dev/null && [ -t 0 ]; then
  _HAS_GUM="true"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh" 2>/dev/null || true

# Fallback color functions if helpers.sh not available
type yellow &>/dev/null || yellow() { echo -e "\033[33m$*\033[0m"; }
type green &>/dev/null  || green()  { echo -e "\033[32m$*\033[0m"; }
type red &>/dev/null   || red()    { echo -e "\033[31m$*\033[0m"; }

# ============================================================
# Default values
# ============================================================
CFG_VERSION="1.0"
CFG_NAME=""
CFG_DESC=""
CFG_TRACK_LEASPEC="true"
CFG_TRACK_AGENT_DIRS="false"
CFG_IGNORE_METHOD="gitignore"
CFG_CONSTITUTION_FILE=""
CFG_NON_INTERACTIVE="false"
CFG_YES="false"

# Default constitution principles (3 parallel arrays, indexed 0-4)
_DEFAULT_PRINCIPLE_TITLES=(
  "Spec-as-Truth"
  "Trigger-by-Need"
  "Incremental-First"
  "Design-Before-Code"
  "Simplicity"
  "Respect-Comments"
)
_DEFAULT_PRINCIPLE_DESCS=(
  "specs/ 目录是系统行为的权威描述（source of truth），代码是规范的实现。所有功能行为必须以规范文件为准。"
  "根据项目状态和需求类型，自动选择最合适的流程。不强制走全流程，允许灵活裁剪。"
  "已有规范时优先走增量变更（spec diff），避免重复生成完整规范。仅在全新领域时使用 0→1 流程。"
  "禁止未经设计直接编写代码。设计必须产出可审查的方案（spec、plan、设计文档）。"
  "选择最简单的方案。反对过度抽象和过早优化。Templates 和 scripts 保持最小化，skill 职责单一。"
  "不修改任何已有注释，除非修改了对应的代码段。注释是代码上下文的一部分，即使是 TODO 类注释也不得删除。"
)
_DEFAULT_PRINCIPLE_CHECKS=(
  "新功能是否有对应的规范文件？|代码变更是否与规范保持一致？|规范是否被正确地反映在审查中？"
  "流程选择是否符合当前需求类型？|是否跳过了不必要的能力步骤？|是否在需要时触发了正确的 skill？"
  "是否复用了已有规范而非重新生成？|增量变更（ADDED/MODIFIED/REMOVED）是否精确、最小化？|是否避免了不必要的全量规范重写？"
  "设计文档是否在代码之前完成？|设计是否通过了审查？|设计是否充分考虑了替代方案？"
  "当前方案是否是最简单的可行方案？|是否引入了不必要的抽象层？|是否有充分的理由增加复杂度？"
  "是否误删或修改了与代码变更无关的注释？|修改代码时是否同步更新了对应的注释？|新增代码是否包含了必要的注释？"
)

# ============================================================
# T001: _print_usage
# ============================================================
_print_usage() {
  cat <<USAGE
Usage: init.sh [OPTIONS] <project-root>

Options:
  --version VERSION              leaspec config version (default: "1.0")
  --name NAME                    Project name (default: basename of project-root)
  --description DESC             Project description (default: "")
  --track-leaspec true|false     Git-track leaspec/ directory (default: true)
  --track-agent-dirs true|false  Git-track .claude/ .agents/ etc. (default: false)
  --ignore-method METHOD         Ignore mechanism: gitignore (team) or exclude (local) (default: gitignore)
  --git-track true|false         [deprecated] Shortcut for --track-leaspec
  --constitution-file PATH       Pre-written constitution.md file
  --non-interactive              Skip all interactive prompts, use defaults
  --yes                          Auto-accept all defaults (non-interactive alias)
  --help                         Show this help message

Examples:
  init.sh /path/to/project
  init.sh --name "myapp" --track-leaspec false --ignore-method exclude /path/to/project
  init.sh --non-interactive /path/to/project
  init.sh --name "myapp" --constitution-file /tmp/constitution.md /path/to/project
  init.sh --yes /path/to/project
USAGE
}

# ============================================================
# T002: _parse_args
# ============================================================
_parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --help)
        _print_usage
        exit 0
        ;;
      --version)
        CFG_VERSION="$2"
        CFG_VERSION_SET="true"
        shift 2
        ;;
      --name)
        CFG_NAME="$2"
        CFG_NAME_SET="true"
        shift 2
        ;;
      --description)
        CFG_DESC="$2"
        CFG_DESC_SET="true"
        shift 2
        ;;
      --track-leaspec)
        CFG_TRACK_LEASPEC="$2"
        CFG_TRACK_LEASPEC_SET="true"
        shift 2
        ;;
      --track-agent-dirs)
        CFG_TRACK_AGENT_DIRS="$2"
        CFG_TRACK_AGENT_DIRS_SET="true"
        shift 2
        ;;
      --ignore-method)
        CFG_IGNORE_METHOD="$2"
        CFG_IGNORE_METHOD_SET="true"
        shift 2
        ;;
      --git-track)
        CFG_TRACK_LEASPEC="$2"
        shift 2
        ;;
      --constitution-file)
        CFG_CONSTITUTION_FILE="$2"
        shift 2
        ;;
      --non-interactive)
        CFG_NON_INTERACTIVE="true"
        shift
        ;;
      --yes|-y)
        CFG_YES="true"
        shift
        ;;
      -*)
        echo "Error: Unknown option: $1"
        _print_usage
        exit 1
        ;;
      *)
        PROJECT_ROOT="$1"
        shift
        ;;
    esac
  done

  PROJECT_ROOT="${PROJECT_ROOT:-.}"
  PROJECT_ROOT="$(cd "$PROJECT_ROOT" 2>/dev/null && pwd || echo "$PROJECT_ROOT")"

  # Default project name from directory
  if [ -z "$CFG_NAME" ]; then
    CFG_NAME="$(basename "$PROJECT_ROOT")"
  fi
}

# ============================================================
# T003: _validate_args
# ============================================================
_validate_args() {
  local errs=0

  if [ -z "${PROJECT_ROOT:-}" ]; then
    echo "Error: <project-root> is required"
    errs=$((errs + 1))
  elif [ ! -d "$PROJECT_ROOT" ]; then
    echo "Error: Project root '$PROJECT_ROOT' does not exist or is not a directory"
    errs=$((errs + 1))
  fi

  # Validate --track-leaspec
  case "$CFG_TRACK_LEASPEC" in
    true|false) ;;
    *)
      echo "Error: --track-leaspec must be 'true' or 'false', got '$CFG_TRACK_LEASPEC'"
      errs=$((errs + 1))
      ;;
  esac

  # Validate --track-agent-dirs
  case "$CFG_TRACK_AGENT_DIRS" in
    true|false) ;;
    *)
      echo "Error: --track-agent-dirs must be 'true' or 'false', got '$CFG_TRACK_AGENT_DIRS'"
      errs=$((errs + 1))
      ;;
  esac

  # Validate --ignore-method
  case "$CFG_IGNORE_METHOD" in
    gitignore|exclude) ;;
    *)
      echo "Error: --ignore-method must be 'gitignore' or 'exclude', got '$CFG_IGNORE_METHOD'"
      errs=$((errs + 1))
      ;;
  esac

  # Validate --constitution-file
  if [ -n "$CFG_CONSTITUTION_FILE" ] && [ ! -f "$CFG_CONSTITUTION_FILE" ]; then
    echo "Error: --constitution-file '$CFG_CONSTITUTION_FILE' does not exist or is not readable"
    errs=$((errs + 1))
  fi

  # Default version
  if [ -z "$CFG_VERSION" ]; then
    CFG_VERSION="1.0"
  fi

  if [ $errs -gt 0 ]; then
    exit 1
  fi
}

# ============================================================
# T013-T016: TTY interaction functions
# ============================================================

# T013: Check if stdin is a terminal
_is_tty() {
  [ -t 0 ]
}

# Gum-aware output helpers — ensure consistent rendering in both modes
_say() {
  if [ "$_HAS_GUM" = "true" ]; then
    gum style "$1" >&2
  else
    echo "$1" >&2
  fi
}
_say_bold() {
  if [ "$_HAS_GUM" = "true" ]; then
    gum style --bold "$1" >&2
  else
    echo -e "\033[1m$1\033[0m" >&2
  fi
}
_say_green() {
  if [ "$_HAS_GUM" = "true" ]; then
    gum style --foreground 212 --bold "▸ $1" >&2
  else
    green "▸ $1" >&2
  fi
}
_say_yellow() {
  if [ "$_HAS_GUM" = "true" ]; then
    gum style --foreground 214 "$1" >&2
  else
    yellow "$1" >&2
  fi
}
_say_heading() {
  if [ "$_HAS_GUM" = "true" ]; then
    gum style --bold --border double --padding "0 2" --margin "1 0" --align center "$1" >&2
  else
    echo "" >&2
    echo "============================================" >&2
    echo "        $1" >&2
    echo "============================================" >&2
  fi
}

# T014: Prompt for text input with default value
# Uses gum input when available (proper UTF-8), falls back to read
# Label is rendered separately via gum style to keep Chinese chars out of gum's line-editor
_prompt() {
  local label="$1"
  local default="$2"

  if [ "$_HAS_GUM" = "true" ]; then
    gum style --bold "$label" >&2
    gum input --value "$default" --prompt "> "
  else
    local input
    printf "%s [%s]: " "$label" "$default" >&2
    IFS= read -r input
    echo "${input:-$default}"
  fi
}

# yes/no prompt — returns "true" or "false"
# Uses gum confirm when available, falls back to read
_prompt_yn() {
  local label="$1"
  local default="$2"

  if [ "$_HAS_GUM" = "true" ]; then
    local def_flag="--default=false"
    case "$default" in
      y|Y|yes|YES|true) def_flag="--default=true" ;;
    esac
    if gum confirm ${def_flag} --affirmative "Yes" --negative "No" "${label}"; then
      echo "true"
    else
      echo "false"
    fi
  else
    case "$default" in
      y|Y|yes|YES|true) printf "%s [Y/n]: " "$label" >&2 ;;
      *)                printf "%s [y/N]: " "$label" >&2 ;;
    esac
    IFS= read -r answer
    case "${answer:-$default}" in
      y|Y|yes|YES|true)  echo "true"  ;;
      n|N|no|NO|false)   echo "false" ;;
      *)                 echo "false" ;;
    esac
  fi
}

# T014b: Numbered option selection — returns selected option TEXT
# Automatically appends a "自定义输入..." option as the last choice.
# Uses gum choose + gum input when available, falls back to numbered read
_prompt_choice() {
  local prompt="$1"
  shift
  local options=("$@")

  if [ "$_HAS_GUM" = "true" ]; then
    local result
    # Build option list including custom input
    local gum_opts=("${options[@]}" "✏️  自定义输入...")
    result=$(printf '%s\n' "${gum_opts[@]}" | gum choose --header "${prompt}") || true
    # User cancelled (Esc/Ctrl-C) → use first option as default
    if [ -z "$result" ]; then
      echo "${options[0]}"
      return 0
    fi
    if [ "$result" = "✏️  自定义输入..." ]; then
      result=$(gum input --prompt "自定义输入: ") || true
      # Cancelled custom input → fall back to first option
      if [ -z "$result" ]; then
        echo "${options[0]}"
        return 0
      fi
    fi
    echo "${result}"
  else
    echo "" >&2
    echo -e "\033[1m${prompt}\033[0m" >&2
    echo "" >&2

    local i=1
    for opt in "${options[@]}"; do
      printf "  \033[36m%d)\033[0m %s\n" "$i" "$opt" >&2
      ((i++))
    done
    local custom_idx=$i
    printf "  \033[36m%d)\033[0m \033[2m✏️  自定义输入...\033[0m\n" "$custom_idx" >&2
    echo "" >&2

    local choice
    while true; do
      printf "请输入编号 [1-%d]: " "$custom_idx" >&2
      IFS= read -r choice
      if [ "$choice" = "$custom_idx" ]; then
        printf "请输入自定义值: " >&2
        IFS= read -r custom_val
        echo "$custom_val"
        return 0
      elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -lt "$custom_idx" ]; then
        echo "${options[$((choice-1))]}"
        return 0
      fi
      red "无效选择，请输入 1-${custom_idx}" >&2
    done
  fi
}

# T015: Collect config fields via TTY (only for fields not provided via CLI)
_collect_config_tty() {
  if ! _is_tty || [ "$CFG_NON_INTERACTIVE" = "true" ] || [ "$CFG_YES" = "true" ]; then
    return 0
  fi

  _say_heading "leaspec 初始化 — 配置采集"

  # --- Section 1: 项目元信息 ---
  _say_green "项目元信息"

  if [ -z "${CFG_VERSION_SET:-}" ]; then
    CFG_VERSION="$(_prompt "  配置版本" "${CFG_VERSION:-1.0}")"
  fi

  if [ -z "${CFG_NAME_SET:-}" ]; then
    CFG_NAME="$(_prompt "  项目名称" "${CFG_NAME:-$(basename "$PROJECT_ROOT")}")"
  fi

  if [ -z "${CFG_DESC_SET:-}" ]; then
    CFG_DESC="$(_prompt "  项目描述（可选）" "")"
  fi

  # --- Section 2: Git 追踪设置 ---
  _say_green "Git 追踪设置"

  # track_leaspec
  if [ -z "${CFG_TRACK_LEASPEC_SET:-}" ]; then
    local choice
    choice=$(_prompt_choice \
      "leaspec/ 目录是否纳入 git 追踪？" \
      "追踪 — leaspec/ 规范文件提交到仓库，团队共享 (推荐)" \
      "不追踪 — 个人使用 leaspec 但团队尚未采用")
    case "$choice" in
      追踪*) CFG_TRACK_LEASPEC="true" ;;
      不追踪*) CFG_TRACK_LEASPEC="false" ;;
      *) CFG_TRACK_LEASPEC="$choice" ;;  # 自定义输入
    esac
    _say "  → track_leaspec = $CFG_TRACK_LEASPEC"
  fi

  # track_agent_dirs
  if [ -z "${CFG_TRACK_AGENT_DIRS_SET:-}" ]; then
    local choice
    choice=$(_prompt_choice \
      ".claude/ .agents/ 等 agent 目录是否纳入 git 追踪？" \
      "不追踪 — 每个开发者独立维护 (推荐)" \
      "追踪 — 团队统一 agent 配置时需要")
    case "$choice" in
      不追踪*) CFG_TRACK_AGENT_DIRS="false" ;;
      追踪*) CFG_TRACK_AGENT_DIRS="true" ;;
      *) CFG_TRACK_AGENT_DIRS="$choice" ;;  # 自定义输入
    esac
    _say "  → track_agent_dirs = $CFG_TRACK_AGENT_DIRS"
  fi

  # ignore_method (only relevant if something is not tracked)
  if [ -z "${CFG_IGNORE_METHOD_SET:-}" ]; then
    if [ "$CFG_TRACK_LEASPEC" = "false" ] || [ "$CFG_TRACK_AGENT_DIRS" = "false" ]; then
      _say_yellow "  检测到有不追踪的目录，需要选择忽略机制。"
      local choice
      choice=$(_prompt_choice \
        "不追踪时使用哪种 git 忽略机制？" \
        "gitignore — 写入项目根 .gitignore，团队共享 (推荐)" \
        "exclude — 写入 .git/info/exclude，仅本地生效")
      case "$choice" in
        gitignore*) CFG_IGNORE_METHOD="gitignore" ;;
        exclude*) CFG_IGNORE_METHOD="exclude" ;;
        *) CFG_IGNORE_METHOD="$choice" ;;  # 自定义输入
      esac
      _say "  → ignore_method = $CFG_IGNORE_METHOD"
    fi
  fi
}

# T016: Audit constitution via TTY — 批量编号选择，不再逐条 y/n
_audit_constitution_tty() {
  if ! _is_tty || [ "$CFG_NON_INTERACTIVE" = "true" ] || [ "$CFG_YES" = "true" ] || [ -n "$CFG_CONSTITUTION_FILE" ]; then
    return 0
  fi

  _say_heading "宪法 (Constitution) 审计"

  # --- Metadata ---
  _say_green "元信息"

  local constitution_version="1.0.0"
  local today
  today=$(date +%Y-%m-%d)
  constitution_version="$(_prompt "  CONSTITUTION_VERSION" "$constitution_version")"
  local ratification_date
  ratification_date="$(_prompt "  RATIFICATION_DATE" "$today")"

  # --- Core Principles: 批量展示 + 编号多选 ---
  local accepted_titles=()
  local accepted_descs=()
  local accepted_checks=()
  local total=${#_DEFAULT_PRINCIPLE_TITLES[@]}

  _say_green "Core Principles (共 $total 项)"
  _say "  以下是默认原则，请选择要保留的项（输入编号，逗号分隔，如 1,2,4,5）："

  for ((i=0; i<total; i++)); do
    if [ "$_HAS_GUM" = "true" ]; then
      gum style --bold --foreground 6 "$((i+1))) ${_DEFAULT_PRINCIPLE_TITLES[$i]}" >&2
      gum style "     ${_DEFAULT_PRINCIPLE_DESCS[$i]}" >&2
    else
      printf "  \033[36m%d)\033[0m \033[1m%s\033[0m\n" $((i+1)) "${_DEFAULT_PRINCIPLE_TITLES[$i]}"
      printf "     %s\n" "${_DEFAULT_PRINCIPLE_DESCS[$i]}"
    fi
    echo "" >&2
  done

  local selection
  if [ "$_HAS_GUM" = "true" ]; then
    gum style --bold "保留哪些原则？(逗号分隔，留空表示全部)" >&2
    selection=$(gum input --placeholder "1-${total} 全部" --prompt "> ") || true
  else
    printf "保留哪些原则？[1-%d 全部]: " "$total" >&2
    IFS= read -r selection
  fi

  # Default: keep all
  if [ -z "$selection" ]; then
    selection=$(seq -s, 1 "$total")
  fi

  # Parse selection into indexed array (bash 3.2 compatible — no associative arrays)
  local -a keep_indices=()
  IFS=',' read -ra sel_parts <<< "$selection"
  local part
  for part in "${sel_parts[@]}"; do
    part=$(echo "$part" | tr -d ' ')
    if [[ "$part" =~ ^[0-9]+$ ]] && [ "$part" -ge 1 ] && [ "$part" -le "$total" ]; then
      keep_indices+=("$part")
    fi
  done

  # Helper: check if a number is in keep_indices
  _index_kept() {
    local needle="$1"
    local k
    for k in "${keep_indices[@]}"; do
      if [ "$k" = "$needle" ]; then
        return 0
      fi
    done
    return 1
  }

  # Process each principle
  for ((i=0; i<total; i++)); do
    local idx=$((i+1))
    if _index_kept "$idx"; then
      accepted_titles+=("${_DEFAULT_PRINCIPLE_TITLES[$i]}")
      accepted_descs+=("${_DEFAULT_PRINCIPLE_DESCS[$i]}")
      accepted_checks+=("${_DEFAULT_PRINCIPLE_CHECKS[$i]}")
    else
      _say_yellow "  原则 ${idx}「${_DEFAULT_PRINCIPLE_TITLES[$i]}」未被选中。"
      local action
      action=$(_prompt_choice \
        "如何处理？" \
        "删除此项" \
        "替换为新原则")
      case "$action" in
        替换*)
          local new_title new_desc new_checks
          new_title="$(_prompt "    新原则标题" "")"
          new_desc="$(_prompt "    新原则描述" "")"
          new_checks="$(_prompt "    检查项 (逗号分隔)" "")"
          accepted_titles+=("$new_title")
          accepted_descs+=("$new_desc")
          accepted_checks+=("$(echo "$new_checks" | tr ',' '|')")
          ;;
        *)
          # "删除此项" → skip (don't add to accepted arrays)
          # 自定义输入 → also treated as replacement title
          if [ -n "$action" ] && [ "$action" != "删除此项" ]; then
            yellow "    将「${action}」作为自定义原则标题处理"
            local new_desc new_checks
            new_desc="$(_prompt "    新原则描述" "")"
            new_checks="$(_prompt "    检查项 (逗号分隔)" "")"
            accepted_titles+=("$action")
            accepted_descs+=("$new_desc")
            accepted_checks+=("$(echo "$new_checks" | tr ',' '|')")
          fi
          ;;
      esac
    fi
  done

  # --- Add new principles ---
  echo ""
  local new_title new_desc new_checks
  while true; do
    if [ "$(_prompt_yn "添加额外原则？" "n")" != "true" ]; then
      break
    fi
    new_title="$(_prompt "  新原则标题" "")"
    if [ -z "$new_title" ]; then
      _say "  标题不能为空，跳过。"
      continue
    fi
    new_desc="$(_prompt "  新原则描述" "")"
    new_checks="$(_prompt "  检查项 (逗号分隔)" "")"
    accepted_titles+=("$new_title")
    accepted_descs+=("$new_desc")
    accepted_checks+=("$(echo "$new_checks" | tr ',' '|')")
    _say "  → 已添加「${new_title}」"
  done

  # --- Governance ---
  _say_green "Governance 规则"
  _say "  修订流程: 修改宪法需创建专门的 change proposal，标注 CONSTITUTION_CHANGE 标签"
  _say "  版本策略: 每次修改递增 CONSTITUTION_VERSION"
  _say "  合规审查: 每个 plan.md 必须通过 Constitution Check gates"

  local gov_amendment="" gov_versioning="" gov_review=""
  local -a gov_extra_labels=()
  local -a gov_extra_rules=()
  if [ "$(_prompt_yn "需要修改 Governance 规则吗？" "n")" = "true" ]; then
    echo "" >&2
    gov_amendment="$(_prompt "  修订流程" "修改宪法需要创建专门的 change proposal，标注 CONSTITUTION_CHANGE 标签")"
    gov_versioning="$(_prompt "  版本策略" "每次修改递增 CONSTITUTION_VERSION")"
    gov_review="$(_prompt "  合规审查" "每个 plan.md 必须通过 Constitution Check gates")"

    # Add custom governance rules
    local extra_label extra_rule
    while true; do
      if [ "$(_prompt_yn "添加额外的 Governance 规则？" "n")" != "true" ]; then
        break
      fi
      extra_label="$(_prompt "    规则名称" "")"
      if [ -z "$extra_label" ]; then
        _say "    名称不能为空，跳过。"
        continue
      fi
      extra_rule="$(_prompt "    规则内容" "")"
      gov_extra_labels+=("$extra_label")
      gov_extra_rules+=("$extra_rule")
      _say "    → 已添加「${extra_label}」"
    done
  fi

  # --- Generate constitution temp file ---
  local tmpfile
  tmpfile="/tmp/leaspec-constitution-$(date +%s).md"
  _write_constitution "$tmpfile" "$constitution_version" "$ratification_date" "$today" \
    accepted_titles accepted_descs accepted_checks \
    "$gov_amendment" "$gov_versioning" "$gov_review" \
    gov_extra_labels gov_extra_rules
  CFG_CONSTITUTION_FILE="$tmpfile"
  echo ""
  green "  → 宪法文件已生成: $tmpfile"
}

# Write a constitution.md from principle arrays
# Uses eval-based indirect array access for bash 3.2 compatibility
_write_constitution() {
  local outfile="$1"
  local cversion="$2"
  local rdate="$3"
  local ldate="$4"
  local titles_name="$5"
  local descs_name="$6"
  local checks_name="$7"
  local gov_amendment="${8:-}"
  local gov_versioning="${9:-}"
  local gov_review="${10:-}"
  local gov_extra_labels_name="${11:-}"
  local gov_extra_rules_name="${12:-}"

  # Copy arrays from caller's scope (bash 3.2 compatible — no namerefs)
  eval "local titles_arr=(\"\${${titles_name}[@]}\")"
  eval "local descs_arr=(\"\${${descs_name}[@]}\")"
  eval "local checks_arr=(\"\${${checks_name}[@]}\")"

  # Copy extra governance arrays (may be empty)
  local -a gov_extra_labels_arr=()
  local -a gov_extra_rules_arr=()
  if [ -n "$gov_extra_labels_name" ]; then
    eval "gov_extra_labels_arr=(\"\${${gov_extra_labels_name}[@]}\")"
  fi
  if [ -n "$gov_extra_rules_name" ]; then
    eval "gov_extra_rules_arr=(\"\${${gov_extra_rules_name}[@]}\")"
  fi

  {
    echo "# Project Constitution — ${CFG_NAME}"
    echo ""
    echo "> 项目宪法是最高级别的治理文件。所有规范、计划和实现都必须遵守宪法中的原则。"
    echo "> 如果某个技术决策需要违反宪法原则，必须在 plan.md 的 Complexity Tracking 中记录并说明理由。"
    echo ""
    echo "## Core Principles"
    echo ""

    local count=${#titles_arr[@]}
    local i
    for ((i=0; i<count; i++)); do
      local pnum=$((i + 1))
      echo "### Principle ${pnum}: ${titles_arr[$i]}"
      echo ""
      echo "**描述**: ${descs_arr[$i]}"
      echo ""
      echo "**检查项**:"
      # Split checks by |
      IFS='|' read -ra items <<< "${checks_arr[$i]}"
      local item
      for item in "${items[@]}"; do
        echo "- [ ] ${item}"
      done
      echo ""
      echo "---"
      echo ""
    done

    echo "## Governance"
    echo ""
    echo "- **修订流程**: ${gov_amendment:-修改宪法需要创建专门的 change proposal，标注 \`CONSTITUTION_CHANGE\` 标签}"
    echo "- **版本策略**: ${gov_versioning:-每次修改递增 \`CONSTITUTION_VERSION\`}"
    echo "- **合规审查**: ${gov_review:-每个 plan.md 必须通过 Constitution Check gates}"

    # Extra governance rules added by user
    if [ "${#gov_extra_labels_arr[@]}" -gt 0 ]; then
      local j
      for ((j=0; j<${#gov_extra_labels_arr[@]}; j++)); do
        echo "- **${gov_extra_labels_arr[$j]}**: ${gov_extra_rules_arr[$j]}"
      done
    fi
    echo ""
    echo "---"
    echo ""
    echo "**CONSTITUTION_VERSION**: ${cversion}"
    echo "**RATIFICATION_DATE**: ${rdate}"
    echo "**LAST_AMENDED_DATE**: ${ldate}"
  } > "$outfile"
}

# ============================================================
# File generation (refactored into functions)
# ============================================================
_yaml_string() {
  local value="$1"
  local code character escaped
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  # Bash 参数不能包含 NUL；其它控制字符使用 YAML 双引号转义。
  for code in {1..31} 127; do
    printf -v character '\\%03o' "$code"
    printf -v character '%b' "$character"
    printf -v escaped '\\x%02X' "$code"
    value="${value//"$character"/"$escaped"}"
  done
  for code in {128..159}; do
    printf -v character '\\302\\%03o' "$code"
    printf -v character '%b' "$character"
    printf -v escaped '\\u%04X' "$code"
    value="${value//"$character"/"$escaped"}"
  done
  value="${value//$'\342\200\250'/\\u2028}"
  value="${value//$'\342\200\251'/\\u2029}"
  printf '"%s"' "$value"
}

_generate_config() {
  local leaspec_root="$1"
  cat > "$leaspec_root/config.yaml" <<YAML
# leaspec configuration
version: $(_yaml_string "$CFG_VERSION")

# Git 追踪设置
git:
  track_leaspec: ${CFG_TRACK_LEASPEC}
  track_agent_dirs: ${CFG_TRACK_AGENT_DIRS}
  ignore_method: ${CFG_IGNORE_METHOD}

# 项目元信息
project:
  name: $(_yaml_string "$CFG_NAME")
  description: $(_yaml_string "$CFG_DESC")
YAML
}

_generate_constitution() {
  local leaspec_root="$1"

  if [ -n "$CFG_CONSTITUTION_FILE" ] && [ -f "$CFG_CONSTITUTION_FILE" ]; then
    cat "$CFG_CONSTITUTION_FILE" > "$leaspec_root/constitution.md"
  else
    # Generate from built-in default principles
    local today
    today=$(date +%Y-%m-%d)
    _write_constitution "$leaspec_root/constitution.md" "1.0.0" "$today" "$today" \
      _DEFAULT_PRINCIPLE_TITLES _DEFAULT_PRINCIPLE_DESCS _DEFAULT_PRINCIPLE_CHECKS
  fi
}

_handle_git_tracking() {
  local project_root="$1"

  # Check if project is a git repo
  local is_git_repo="false"
  if [ -d "$project_root/.git" ] || git -C "$project_root" rev-parse --git-dir >/dev/null 2>&1; then
    is_git_repo="true"
  fi

  # Determine ignore file path
  local ignore_file
  if [ "$CFG_IGNORE_METHOD" = "exclude" ]; then
    if [ "$is_git_repo" = "true" ]; then
      ignore_file="$project_root/.git/info/exclude"
    else
      echo "  [!] 项目不是 git 仓库，exclude 方法不可用，回退到 .gitignore"
      ignore_file="$project_root/.gitignore"
    fi
  else
    ignore_file="$project_root/.gitignore"
  fi

  # Ensure parent dir exists
  mkdir -p "$(dirname "$ignore_file")"

  # Track leaspec/
  if [ "$CFG_TRACK_LEASPEC" = "false" ]; then
    if ! grep -qE '(^|/)leaspec(/|$)' "$ignore_file" 2>/dev/null; then
      echo "leaspec/" >> "$ignore_file"
      echo "  added leaspec/ to $ignore_file"
    fi
  fi

  # Track agent dirs (.claude/ .agents/)
  if [ "$CFG_TRACK_AGENT_DIRS" = "false" ]; then
    for agent_dir in ".claude/" ".agents/"; do
      if ! grep -qE '(^|/)'"$(echo "${agent_dir%/}" | sed 's/\./\\./g')"'(/|$)' "$ignore_file" 2>/dev/null; then
        echo "${agent_dir}" >> "$ignore_file"
        echo "  added ${agent_dir} to $ignore_file"
      fi
    done
  fi
}

_print_next_steps() {
  local leaspec_root="$1"
  echo ""
  echo "============================================"
  echo " leaspec 初始化完成"
  echo "============================================"
  echo ""
  echo "--- 创建的文件 ---"
  find "$leaspec_root" -maxdepth 2 -not -path '*/templates/*' | sort | while IFS= read -r f; do
    if [ -d "$f" ]; then
      echo "  $f/"
    else
      echo "  $f"
    fi
  done
  echo ""
  echo "--- 配置摘要 ---"
  echo "  config version:  ${CFG_VERSION}"
  echo "  project.name:    ${CFG_NAME}"
  echo "  project.description: ${CFG_DESC:-"(空)"}"
  echo ""
  echo "--- Git 追踪 ---"
  echo "  track_leaspec:     ${CFG_TRACK_LEASPEC}"
  echo "  track_agent_dirs:  ${CFG_TRACK_AGENT_DIRS}"
  echo "  ignore_method:     ${CFG_IGNORE_METHOD}"
  echo ""
  echo "下一步:"
  echo "  1. 审阅 leaspec/constitution.md"
  echo "  2. 审阅 leaspec/config.yaml"
  echo "  3. 开始开发: /leaspec-new <需求描述>"
}

# ============================================================
# main
# ============================================================
main() {
  _parse_args "$@"
  _validate_args

  # Check for existing leaspec/
  local leaspec_root="$PROJECT_ROOT/leaspec"
  if [ -f "$leaspec_root/config.yaml" ]; then
    if _is_tty && [ "$CFG_NON_INTERACTIVE" != "true" ] && [ "$CFG_YES" != "true" ]; then
      local merge
      merge=$(_prompt_yn "leaspec/ 已存在，是否合并（跳过已有文件）？" "y")
      if [ "$merge" != "true" ]; then
        echo "已取消"
        exit 0
      fi
    else
      echo "==> leaspec/ 已存在，跳过已有文件继续"
    fi
  fi

  # TTY interaction (skipped in Agent mode / non-interactive)
  _collect_config_tty
  _audit_constitution_tty

  echo "==> 初始化 leaspec 到 $leaspec_root"

  # Create directory structure
  for subdir in specs changes archive templates scripts; do
    mkdir -p "$leaspec_root/$subdir"
    echo "  created: leaspec/$subdir/"
  done

  # Generate config.yaml
  if [ ! -f "$leaspec_root/config.yaml" ]; then
    _generate_config "$leaspec_root"
    echo "  created: leaspec/config.yaml"
  else
    echo "  skipped: leaspec/config.yaml (已存在)"
  fi

  # Generate constitution.md
  if [ ! -f "$leaspec_root/constitution.md" ]; then
    _generate_constitution "$leaspec_root"
    if [ -f "$leaspec_root/constitution.md" ]; then
      echo "  created: leaspec/constitution.md"
    else
      echo "  skipped: leaspec/constitution.md (模板不可用)"
    fi
  else
    echo "  skipped: leaspec/constitution.md (已存在)"
  fi

  # Handle git tracking / ignore
  _handle_git_tracking "$PROJECT_ROOT"

  # Validate
  echo ""
  echo "==> 验证结构完整性..."
  if [ -f "$leaspec_root/scripts/validate.sh" ]; then
    bash "$leaspec_root/scripts/validate.sh" "$leaspec_root" || echo "  [!] 验证发现警告，请检查上述输出"
  fi

  _print_next_steps "$leaspec_root"
}

# Only run main when executed directly, not when sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
