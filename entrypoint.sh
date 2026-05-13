#!/bin/sh
set -e

# ~/.claude is a runtime mount, so we point it at the baked-in skills here.
# Skip if the user already has something at ~/.claude/skills.
mkdir -p "$HOME/.claude"
if [ ! -e "$HOME/.claude/skills" ] && [ ! -L "$HOME/.claude/skills" ]; then
  ln -s /opt/claude/skills "$HOME/.claude/skills"
fi

exec "$@"
