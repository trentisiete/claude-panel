#!/usr/bin/env bash

PROJECT_DIR="${PANEL_PROJECT_DIR:-$(pwd)}"

# Encode path like Claude does: /home/user/project -> -home-user-project
ENCODED_PATH=$(echo "$PROJECT_DIR" | tr '/' '-')
ENCODED_PATH="${ENCODED_PATH#-}"

CLAUDE_PROJECT="$HOME/.claude/projects/${ENCODED_PATH}"
CLAUDE_MEMORY="${CLAUDE_PROJECT}/memory"

# Colors
K='\033[1;37m'   # White bold for keys
C='\033[0;36m'   # Cyan for labels
D='\033[2m'      # Dim
Y='\033[0;33m'   # Yellow
R='\033[0m'      # Reset
S='\033[2m|'     # Separator

printf " ${K}Ctrl+Q${R} ${D}Quit${R}  ${S}  ${K}Ctrl+O,d${R} ${D}Detach${R}  ${S}  ${K}Alt+←→${R} ${D}Switch pane${R}  ${S}  ${K}Ctrl+O,n${R} ${D}New pane${R}  ${S}  ${K}Ctrl+O,w${R} ${D}Session mgr${R}  ${S}  ${K}Ctrl+O,e${R} ${D}Scroll mode${R}${R}"
echo ""
printf " ${C}Project${R} ${D}${CLAUDE_PROJECT}${R}  ${S}  ${C}Memory${R} ${D}${CLAUDE_MEMORY}${R}  ${S}  ${Y}claude --resume${R}  ${S}  ${Y}claude-panel --kill${R}${R}"
echo ""

# Keep alive so pane doesn't close
exec cat
