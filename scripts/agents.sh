#!/usr/bin/env bash

# Use alternate screen buffer — prevents scroll accumulation
tput smcup 2>/dev/null
trap 'tput rmcup 2>/dev/null' EXIT INT TERM

BOLD='\033[1m'; DIM='\033[2m'
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'
RESET='\033[0m'

PROJECT_DIR="${PANEL_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
PROJECT_NAME="${PANEL_PROJECT_NAME:-$(basename "$PROJECT_DIR")}"

draw() {
    tput cup 0 0
    tput ed

    local now now_fmt
    now=$(date +%s)
    now_fmt=$(date '+%H:%M:%S')

    echo -e " ${BOLD}${CYAN}Agents${RESET}  ${DIM}${now_fmt}${RESET}"
    echo ""

    # ── All data from one Python call: worktrees + agents ──
    local data=""
    data=$(python3 << PYEOF
import json, os, glob, time, subprocess

now = int(time.time())
sessions_dir = os.path.expanduser("~/.claude/sessions")
projects_dir = os.path.expanduser("~/.claude/projects")
project_dir = "${PROJECT_DIR}"

# ── Count total sessions per worktree path ──
# Claude encodes paths: /a/b/.c/d -> -a-b-c-d (/ -> -, dots stripped)
def encode_path(p):
    return p.replace("/", "-").replace(".", "-")

# Get worktree paths from git
wt_paths = []
try:
    out = subprocess.check_output(
        ["git", "-C", project_dir, "worktree", "list", "--porcelain"],
        stderr=subprocess.DEVNULL, text=True
    )
    for line in out.splitlines():
        if line.startswith("worktree "):
            wt_paths.append(line.split(" ", 1)[1])
except:
    wt_paths = [project_dir]

# Count JSONL files per worktree (total historical sessions)
# Also count active sessions per worktree from sessions/*.json
active_by_cwd = {}
for f in glob.glob(os.path.join(sessions_dir, "*.json")):
    try:
        d = json.load(open(f))
        pid = d.get("pid", 0)
        cwd = d.get("cwd", "")
        try:
            os.kill(pid, 0)
            active_by_cwd[cwd] = active_by_cwd.get(cwd, 0) + 1
        except:
            pass
    except:
        pass

for wt in wt_paths:
    encoded = encode_path(wt)
    # Count JSONL files in matching project dir
    total_sessions = 0
    pdir = os.path.join(projects_dir, encoded)
    if os.path.isdir(pdir):
        total_sessions = len(glob.glob(os.path.join(pdir, "*.jsonl")))
    active = active_by_cwd.get(wt, 0)
    print(f"WT\t{wt}\t{active}\t{total_sessions}")

# ── Agent sessions ──
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

        conv_size = 0
        branch = ""
        first_task = ""
        last_task = ""
        model = ""

        for jf in glob.glob(os.path.join(projects_dir, "*", f"{sid}.jsonl")):
            try:
                conv_size = os.path.getsize(jf)
            except:
                pass
            try:
                with open(jf) as fh:
                    for line in fh:
                        try:
                            e = json.loads(line)
                            # Extract model from assistant messages
                            if e.get("type") == "assistant":
                                m = e.get("message", {}).get("model", "")
                                if m and not m.startswith("<"):
                                    model = m
                            if e.get("type") != "user":
                                continue
                            if e.get("isMeta") or e.get("toolUseResult"):
                                continue
                            branch = e.get("gitBranch", branch)
                            msg = e.get("message", {})
                            content = msg.get("content", "") if isinstance(msg, dict) else ""
                            text = ""
                            if isinstance(content, list):
                                for c in content:
                                    if isinstance(c, dict) and c.get("type") == "text":
                                        text = c.get("text", "").strip()
                                        break
                            elif isinstance(content, str):
                                text = content.strip()
                            if text and not text.startswith("<") and len(text) > 3:
                                if not first_task:
                                    first_task = text[:70]
                                last_task = text[:70]
                        except:
                            continue
            except:
                pass

        # Match cwd to worktree
        wt_match = os.path.basename(cwd)
        for wt in wt_paths:
            if cwd.startswith(wt):
                wt_match = os.path.basename(wt)
                break

        # Shorten model name
        short_model = model.replace("claude-", "").replace("-4-6", " 4.6").replace("-4-5", " 4.5") if model else "?"

        mem_mb = 0
        if alive:
            try:
                out = subprocess.check_output(
                    ["ps", "-o", "rss=", "-p", str(pid)],
                    stderr=subprocess.DEVNULL, text=True
                ).strip()
                if out:
                    mem_mb = int(out) // 1024
            except:
                pass

        status = "ACTIVE" if alive else "ENDED"
        print(f"{status}\t{pid}\t{proj}\t{cwd}\t{elapsed}\t{kind}\t{entry}\t{conv_size}\t{mem_mb}\t{branch}\t{first_task}\t{last_task}\t{short_model}\t{wt_match}")
    except:
        pass
PYEOF
    )

    # ── Worktrees display ──
    echo -e " ${BOLD}Worktrees:${RESET}"

    echo "$data" | grep "^WT" | while IFS=$'\t' read -r _ wt_path active total; do
        [ -z "$wt_path" ] && continue

        local wt_name wt_branch
        wt_name=$(basename "$wt_path")

        local marker="${DIM}o${RESET}"
        [ "$wt_path" = "$PROJECT_DIR" ] && marker="${GREEN}*${RESET}"

        local counts=""
        if [ "${active:-0}" -gt 0 ]; then
            counts="${GREEN}${active} running${RESET} ${DIM}/${RESET} ${total} total"
        else
            counts="${DIM}${total} sessions${RESET}"
        fi

        printf "   %b %-22s  %b\n" "$marker" "$wt_name" "$counts"
    done

    echo ""

    # Count active
    local active_n
    active_n=$(echo "$data" | grep -c "^ACTIVE" || echo 0)
    local total_n
    total_n=$(echo "$data" | grep -c "." || echo 0)

    echo -e " ${BOLD}Active agents: ${GREEN}${active_n}${RESET}"
    echo ""

    # Show active agents
    echo "$data" | grep "^ACTIVE" | while IFS=$'\t' read -r _ pid proj cwd elapsed kind entry conv_size mem_mb branch first_task last_task model wt_name; do
        [ -z "$pid" ] && continue

        # Time
        local time_str=""
        if [ "$elapsed" -lt 60 ]; then time_str="${elapsed}s"
        elif [ "$elapsed" -lt 3600 ]; then time_str="$((elapsed/60))m"
        elif [ "$elapsed" -lt 86400 ]; then time_str="$((elapsed/3600))h$((elapsed%3600/60))m"
        else time_str="$((elapsed/86400))d"
        fi

        # Context size
        local ctx=""
        if [ "$conv_size" -ge 1048576 ]; then ctx="$((conv_size/1048576))MB"
        elif [ "$conv_size" -ge 1024 ]; then ctx="$((conv_size/1024))KB"
        else ctx="${conv_size}B"
        fi

        # Memory
        local mem_str="-"
        [ "$mem_mb" -gt 0 ] && mem_str="${mem_mb}MB"

        # Entry label
        local label="${entry#claude-}"
        [ -z "$label" ] && label="$kind"

        echo -e "   ${GREEN}*${RESET} ${BOLD}${wt_name:-$proj}${RESET} ${DIM}[${label}]${RESET}  ${MAGENTA}${model:-?}${RESET}"
        echo -e "     ${DIM}on${RESET} ${YELLOW}${branch:-?}${RESET}  ${DIM}| PID ${pid} | ${time_str}${RESET}"
        echo -e "     ${DIM}mem ${mem_str} | ctx ${ctx}${RESET}"

        # Show task
        local task="${last_task:-$first_task}"
        if [ -n "$task" ]; then
            [ ${#task} -gt 50 ] && task="${task:0:47}..."
            echo -e "     ${CYAN}> ${task}${RESET}"
        fi
        echo ""
    done

    if [ "$active_n" = "0" ]; then
        echo -e "   ${DIM}No active agents${RESET}"
        echo ""
    fi

    # Recent ended
    local ended
    ended=$(echo "$data" | grep "^ENDED")
    if [ -n "$ended" ]; then
        echo -e " ${BOLD}Recent:${RESET}"
        echo "$ended" | head -5 | while IFS=$'\t' read -r _ pid proj cwd elapsed kind entry conv_size mem_mb branch first_task last_task model wt_name; do
            [ -z "$pid" ] && continue

            local time_str=""
            if [ "$elapsed" -lt 3600 ]; then time_str="$((elapsed/60))m ago"
            elif [ "$elapsed" -lt 86400 ]; then time_str="$((elapsed/3600))h ago"
            else time_str="$((elapsed/86400))d ago"
            fi

            local ctx=""
            if [ "$conv_size" -ge 1048576 ]; then ctx="$((conv_size/1048576))MB"
            elif [ "$conv_size" -ge 1024 ]; then ctx="$((conv_size/1024))KB"
            fi

            local task="${last_task:-$first_task}"
            [ ${#task} -gt 35 ] && task="${task:0:32}..."

            echo -e "   ${DIM}o ${wt_name:-$proj} ${model:-?} [${branch:-?}] ${time_str} ${ctx}${RESET}"
            [ -n "$task" ] && echo -e "     ${DIM}> ${task}${RESET}"
        done
    fi
}

while true; do
    draw
    sleep 10
done
