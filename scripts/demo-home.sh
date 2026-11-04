#!/bin/bash
# Creates a fake home directory with plausible agent config, for demos and screenshots.
# Warden Debug builds use it through WARDEN_HOME. Your real files are never involved.
set -euo pipefail
HOME_DIR="${1:?usage: demo-home.sh <directory>}"
# Only ever deletes a directory this script created.
if [ -e "$HOME_DIR" ]; then
  if [ ! -f "$HOME_DIR/.warden-demo" ]; then
    echo "Refusing to touch $HOME_DIR: it is not a Warden demo home." >&2
    exit 1
  fi
  rm -rf "$HOME_DIR"
fi
mkdir -p "$HOME_DIR/.claude/projects" "$HOME_DIR/.codex"
touch "$HOME_DIR/.warden-demo"

cat > "$HOME_DIR/.claude/settings.json" <<'JSON'
{
  "model": "opus",
  "permissions": {
    "allow": ["Read", "Edit"]
  },
  "enabledPlugins": {
    "superpowers@claude-plugins-official": true
  }
}
JSON
printf '# House rules\n\nAlways run the tests before committing.\n' > "$HOME_DIR/.claude/CLAUDE.md"
cat > "$HOME_DIR/.codex/config.toml" <<'TOML'
model = "gpt-5"
approval_policy = "on-request"

[projects."/Users/demo/code/atlas"]
trust_level = "trusted"
TOML

projects=""
for name in northwind atlas harbor; do
  path="/Users/demo/code/$name"
  folder="$(printf '%s' "$path" | tr -c 'a-zA-Z0-9' '-')"
  mkdir -p "$HOME_DIR/.claude/projects/$folder"
  touch "$HOME_DIR/.claude/projects/$folder/session.jsonl"
  projects="$projects\"$path\":{\"allowedTools\":[],\"hasTrustDialogAccepted\":true,\"lastCost\":1.5},"
done
printf '{"numStartups":42,"projects":{%s}}\n' "${projects%,}" > "$HOME_DIR/.claude.json"
