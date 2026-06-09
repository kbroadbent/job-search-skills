#!/usr/bin/env bash
#
# install-skills.sh — install the job-search skills.
#
# Two ways to install:
#   1) Full plugin   — registers this repo as a Claude Code plugin marketplace and
#                       installs the `job-search` plugin (versioned, namespaced,
#                       managed via `claude plugin` / `/plugin`). Active globally,
#                       enable/disable per project.
#   2) Skills only   — copies the skill folders into a project's .claude/skills/
#                       directory (no plugin registration). Use this when you want
#                       the skills available in one specific directory.
#
# Existing skills of the same name are overwritten in mode 2.

set -euo pipefail

# Resolve the directory this script lives in, so it works from any cwd.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/skills"
PLUGIN_MANIFEST="$SCRIPT_DIR/.claude-plugin/plugin.json"
MARKETPLACE_MANIFEST="$SCRIPT_DIR/.claude-plugin/marketplace.json"

# Names used for the plugin install. Keep in sync with .claude-plugin/*.json.
PLUGIN_NAME="job-search"
MARKETPLACE_NAME="job-search"

if [[ ! -d "$SRC_DIR" ]]; then
  echo "Error: no skills/ directory found next to this script ($SRC_DIR)." >&2
  exit 1
fi

# Collect skill folders (those containing a SKILL.md).
skills=()
for dir in "$SRC_DIR"/*/; do
  [[ -f "${dir}SKILL.md" ]] || continue
  skills+=("$(basename "$dir")")
done

if [[ ${#skills[@]} -eq 0 ]]; then
  echo "Error: no skills found in $SRC_DIR (looked for */SKILL.md)." >&2
  exit 1
fi

echo "Found ${#skills[@]} skill(s):"
for s in "${skills[@]}"; do
  echo "  - $s"
done
echo

# ---- Choose install mode -----------------------------------------------------
echo "How would you like to install?"
echo "  1) Full plugin        — register + install the '$PLUGIN_NAME' plugin (managed via /plugin)"
echo "  2) Skills only         — copy skills into a specific directory's .claude/skills/"
echo
read -r -p "Choose 1 or 2: " mode

# ---- Mode 1: install as a plugin --------------------------------------------
install_plugin() {
  if [[ ! -f "$PLUGIN_MANIFEST" ]]; then
    echo "Error: $PLUGIN_MANIFEST not found — this repo isn't a plugin." >&2
    exit 1
  fi
  if [[ ! -f "$MARKETPLACE_MANIFEST" ]]; then
    echo "Error: $MARKETPLACE_MANIFEST not found — can't register the marketplace." >&2
    exit 1
  fi

  if command -v claude >/dev/null 2>&1; then
    echo
    echo "Registering this repo as a marketplace and installing the plugin..."
    echo "  \$ claude plugin marketplace add \"$SCRIPT_DIR\""
    if claude plugin marketplace add "$SCRIPT_DIR"; then
      echo "  \$ claude plugin install ${PLUGIN_NAME}@${MARKETPLACE_NAME}"
      if claude plugin install "${PLUGIN_NAME}@${MARKETPLACE_NAME}"; then
        echo
        echo "Done. The '$PLUGIN_NAME' plugin is installed."
        echo "Manage it anytime with: claude plugin list / claude plugin disable $PLUGIN_NAME"
        return 0
      fi
    fi
    echo
    echo "The claude CLI didn't complete the install (the subcommand syntax may differ"
    echo "in your version). Run these manually instead:" >&2
  else
    echo
    echo "The 'claude' CLI isn't on your PATH, so I can't run the install for you."
    echo "Run these yourself — either the CLI form or the /plugin slash commands inside Claude Code:"
  fi

  cat <<EOF

  CLI:
    claude plugin marketplace add "$SCRIPT_DIR"
    claude plugin install ${PLUGIN_NAME}@${MARKETPLACE_NAME}

  Or inside a Claude Code session:
    /plugin marketplace add $SCRIPT_DIR
    /plugin install ${PLUGIN_NAME}@${MARKETPLACE_NAME}

  Or load it for a single session without installing:
    claude --plugin-dir "$SCRIPT_DIR"
EOF
}

# ---- Mode 2: copy skills into a chosen directory ----------------------------
install_skills_only() {
  read -r -p "Project directory: " project_dir
  # Expand a leading ~ to the home directory.
  project_dir="${project_dir/#\~/$HOME}"
  if [[ -z "$project_dir" ]]; then
    echo "Error: no directory provided." >&2
    exit 1
  fi
  # Resolve to an absolute path (create the project dir if it doesn't exist yet).
  mkdir -p "$project_dir"
  project_dir="$(cd "$project_dir" && pwd)"
  local dest="$project_dir/.claude/skills"

  mkdir -p "$dest"
  echo
  echo "Installing into: $dest"
  echo

  local installed=0
  for s in "${skills[@]}"; do
    local target="$dest/$s"
    if [[ -e "$target" ]]; then
      echo "  overwriting  $s"
      rm -rf "$target"
    else
      echo "  installing   $s"
    fi
    cp -R "$SRC_DIR/$s" "$target"
    installed=$((installed + 1))
  done

  echo
  echo "Done. Installed $installed skill(s) into $dest"
}

case "$mode" in
  1) install_plugin ;;
  2) install_skills_only ;;
  *)
    echo "Error: invalid choice '$mode'. Run again and pick 1 or 2." >&2
    exit 1
    ;;
esac
