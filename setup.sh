#!/bin/bash

# ============================================================
# Claude Code Config Setup
# github.com/xXMarcicraMXx/claude-config
# Run this on any machine to replicate the full environment
# ============================================================

set -e  # Stop on any error

echo ""
echo "================================================"
echo "  Claude Code Config Setup"
echo "================================================"
echo ""

# --- 1. Create ~/.claude directory if it doesn't exist ---
echo "[1/4] Ensuring ~/.claude directory exists..."
mkdir -p ~/.claude/skills

# --- 2. Install gstack ---
echo "[2/4] Installing gstack..."

if [ -d ~/.claude/skills/gstack ]; then
  echo "  gstack already exists — updating..."
  cd ~/.claude/skills/gstack
  git pull origin main
  ./setup
else
  git clone https://github.com/garrytan/gstack.git ~/.claude/skills/gstack
  cd ~/.claude/skills/gstack
  ./setup
fi

echo "  gstack installed."

# --- 3. Symlink CLAUDE.md ---
echo "[3/4] Linking CLAUDE.md to ~/.claude/CLAUDE.md..."

# Go back to the repo root regardless of where we are
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ln -sf "$SCRIPT_DIR/CLAUDE.md" ~/.claude/CLAUDE.md
echo "  Symlink created: ~/.claude/CLAUDE.md -> $SCRIPT_DIR/CLAUDE.md"

# --- 4. Done ---
echo ""
echo "[4/4] Final manual step — open Claude Code and run these two commands:"
echo ""
echo "  /plugin marketplace add obra/superpowers-marketplace"
echo "  /plugin install superpowers@superpowers-marketplace"
echo ""
echo "================================================"
echo "  Setup complete!"
echo "================================================"
echo ""
