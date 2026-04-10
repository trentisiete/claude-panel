#!/usr/bin/env bash

# Use alternate screen buffer — prevents scroll accumulation
tput smcup 2>/dev/null
trap 'tput rmcup 2>/dev/null' EXIT INT TERM

BOLD='\033[1m'; DIM='\033[2m'
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; RESET='\033[0m'

SESSIONS_DIR="$HOME/.claude/sessions"

time_ago() {
    local s=$1
    if [ "$s" -lt 60 ]; then echo "${s}s"
    elif [ "$s" -lt 3600 ]; then echo "$((s / 60))m"
    elif [ "$s" -lt 86400 ]; then echo "$((s / 3600))h $((s % 3600 / 60))m"
    else echo "$((s / 86400))d $((s % 86400 / 3600))h"
    fi
}

fmt_size() {
    local bytes=$1
    if [ "$bytes" -ge 1048576 ]; then echo "$((bytes / 1048576))MB"
    elif [ "$bytes" -ge 1024 ]; then echo "$((bytes / 1024))KB"
    else echo "${bytes}B"
    fi
}

draw() {
    tput cup 0 0
    tput ed

    local now now_fmt
    now=$(date +%s)
    now_fmt=$(date '+%H:%M:%S')

    echo -e " ${BOLD}${CYAN}Claude Agents${RESET}  ${DIM}${now_fmt}${RESET}"
    echo ""

    # Parse all sessions in one python3 call
    local data=""
    if [ -d "$SESSIONS_DIR" ]; then
        data=$(python3 << 'PYEOF'
import json, os, glob, time

now = int(time.time())
sessions_dir = os.path.expanduser("~/.claude/sessions")
projects_dir = os.path.expanduser("~/.claude/projects")

sessions = []
for f in sorted(glob.glob(os.path.join(sessions_dir, "*.json")),
                key=os.path.getmtime, reverse=True):
    try:
        d = json.load(open(f))
        pid = d.get("pid", 0)
        alive = False
        try:
            os.kill(pid, 0)
            alive = True
        except:
            pass

        started = d.get("startedAt", 0) // 1000
        elapsed = max(0, now - started)
        cwd = d.get("cwd", "")
        proj = os.path.basename(cwd)
        kind = d.get("kind", "interactive")
        entry = d.get("entrypoint", "cli")
        sid = d.get("sessionId", "")

        # Find conversation file size (proxy for context volume)
        conv_size = 0
        for pdir in glob.glob(os.path.join(projects_dir, "*", f"{sid}.jsonl")):
            try:
                conv_size = os.path.getsize(pdir)
            except:
                pass

        # Get memory usage if alive
        mem_mb = 0
        if alive:
            try:
                import subprocess
                out = subprocess.check_output(
                    ["ps", "-o", "rss=", "-p", str(pid)],
                    stderr=subprocess.DEVNULL, text=True
                ).strip()
                if out:
                    mem_mb = int(out) // 1024
            except:
                pass

        sessions.append((alive, pid, proj, cwd, elapsed, kind, entry, conv_size, mem_mb))
    except:
        pass

active = [s for s in sessions if s[0]]
ended = [s for s in sessions if not s[0]]

print(f"TOTAL\t{len(active)}\t{len(sessions)}")
for s in active:
    alive, pid, proj, cwd, elapsed, kind, entry, conv_size, mem_mb = s
    print(f"ACTIVE\t{pid}\t{proj}\t{cwd}\t{elapsed}\t{kind}\t{entry}\t{conv_size}\t{mem_mb}")
for s in ended[:8]:
    alive, pid, proj, cwd, elapsed, kind, entry, conv_size, mem_mb = s
    print(f"ENDED\t{pid}\t{proj}\t{cwd}\t{elapsed}\t{kind}\t{entry}\t{conv_size}\t{mem_mb}")
PYEOF
        )
    fi

    # Parse totals
    local counts_line
    counts_line=$(echo "$data" | grep "^TOTAL" | head -1)
    local active_n total_n
    active_n=$(echo "$counts_line" | cut -f2)
    total_n=$(echo "$counts_line" | cut -f3)

    echo -e " ${BOLD}Agents: ${GREEN}${active_n:-0}${RESET} active  ${DIM}/ ${total_n:-0} total${RESET}"
    echo ""

    # Active agents
    echo -e " ${BOLD}Active:${RESET}"

    local found=false
    echo "$data" | grep "^ACTIVE" | while IFS=$'\t' read -r _ pid proj cwd elapsed kind entry conv_size mem_mb; do
        [ -z "$pid" ] && continue
        found=true

        local time_str ctx_str mem_str kind_label
        time_str=$(time_ago "$elapsed")
        ctx_str=$(fmt_size "$conv_size")
        [ "$mem_mb" -gt 0 ] && mem_str="${mem_mb}MB" || mem_str="-"

        # Clean entry label
        kind_label="$entry"
        kind_label="${kind_label#claude-}"
        [ -z "$kind_label" ] && kind_label="$kind"

        echo -e ""
        echo -e "   ${GREEN}*${RESET} ${BOLD}${proj}${RESET}  ${DIM}[${kind_label}]${RESET}"
        echo -e "     ${DIM}PID ${pid} | uptime ${time_str} | mem ${mem_str}${RESET}"
        echo -e "     ${DIM}context ${ctx_str} | ${cwd}${RESET}"
    done

    if [ "${active_n:-0}" = "0" ]; then
        echo -e "   ${DIM}No active agents${RESET}"
    fi

    echo ""

    # Recent ended sessions
    local ended_lines
    ended_lines=$(echo "$data" | grep "^ENDED")
    if [ -n "$ended_lines" ]; then
        echo -e " ${BOLD}Recent:${RESET}"
        echo "$ended_lines" | head -6 | while IFS=$'\t' read -r _ pid proj cwd elapsed kind entry conv_size mem_mb; do
            [ -z "$pid" ] && continue
            local time_str ctx_str kind_label
            time_str=$(time_ago "$elapsed")
            ctx_str=$(fmt_size "$conv_size")
            kind_label="${entry#claude-}"
            [ -z "$kind_label" ] && kind_label="$kind"

            echo -e "   ${DIM}o ${proj}  [${kind_label}]  ${time_str} ago  ctx:${ctx_str}${RESET}"
        done
    fi
}

while true; do
    draw
    sleep 10
done
