#!/usr/bin/env bash

tput smcup 2>/dev/null
trap 'tput rmcup 2>/dev/null' EXIT INT TERM

BOLD='\033[1m'; DIM='\033[2m'
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'
RESET='\033[0m'

draw() {
    tput cup 0 0
    tput ed

    local now_fmt
    now_fmt=$(date '+%H:%M:%S')

    echo -e " ${BOLD}${CYAN}Usage${RESET}  ${DIM}${now_fmt}${RESET}"
    echo ""

    local data
    data=$(python3 << 'PYEOF'
import json, os, glob, time
from datetime import datetime, timedelta

projects_dir = os.path.expanduser("~/.claude/projects")
now = time.time()
now_dt = datetime.now()

# Time windows
hour_ago = now - 3600
day_start = now - (now_dt.hour * 3600 + now_dt.minute * 60 + now_dt.second)
week_start = day_start - (now_dt.weekday() * 86400)

periods = {
    "1h": {"since": hour_ago, "in": 0, "out": 0, "reqs": 0},
    "today": {"since": day_start, "in": 0, "out": 0, "reqs": 0},
    "week": {"since": week_start, "in": 0, "out": 0, "reqs": 0},
    "all": {"since": 0, "in": 0, "out": 0, "reqs": 0, "cache_r": 0, "cache_c": 0},
}
models = {}
daily_out = {}  # day_str -> output_tokens

for jf in glob.glob(os.path.join(projects_dir, "*", "*.jsonl")):
    try:
        with open(jf) as fh:
            for line in fh:
                try:
                    d = json.loads(line)
                    if d.get("type") != "assistant":
                        continue
                    msg = d.get("message", {})
                    usage = msg.get("usage", {})
                    model = msg.get("model", "")
                    if not usage:
                        continue

                    inp = usage.get("input_tokens", 0)
                    out = usage.get("output_tokens", 0)
                    cache_r = usage.get("cache_read_input_tokens", 0)
                    cache_c = usage.get("cache_creation_input_tokens", 0)

                    ts = 0
                    ts_str = d.get("timestamp", "")
                    if ts_str:
                        try:
                            dt = datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
                            ts = dt.timestamp()
                        except:
                            pass

                    for name, p in periods.items():
                        if ts >= p["since"]:
                            p["in"] += inp
                            p["out"] += out
                            p["reqs"] += 1
                            if name == "all":
                                p["cache_r"] = p.get("cache_r", 0) + cache_r
                                p["cache_c"] = p.get("cache_c", 0) + cache_c

                    if model and not model.startswith("<"):
                        short = model.replace("claude-", "").replace("-4-6", " 4.6").replace("-4-5", " 4.5")
                        if ts >= periods["week"]["since"]:
                            models[short] = models.get(short, 0) + out

                    # Daily tracking for trend
                    if ts > 0:
                        day_key = datetime.fromtimestamp(ts).strftime("%a")
                        daily_out[day_key] = daily_out.get(day_key, 0) + out
                except:
                    continue
    except:
        pass

# Hours left today / in week
hours_left_today = max(0, 24 - now_dt.hour - 1)
days_left_week = max(0, 6 - now_dt.weekday())
hours_left_week = days_left_week * 24 + hours_left_today

def fmt(n):
    if n >= 1_000_000:
        return f"{n/1_000_000:.1f}M"
    elif n >= 1_000:
        return f"{n/1_000:.1f}K"
    return str(n)

# Output
for name in ["1h", "today", "week", "all"]:
    p = periods[name]
    extra = ""
    if name == "all":
        extra = f"\t{p.get('cache_r', 0)}\t{p.get('cache_c', 0)}"
    print(f"PERIOD\t{name}\t{p['in']}\t{p['out']}\t{p['reqs']}{extra}")

print(f"TIME\t{hours_left_today}\t{hours_left_week}")

for m, out in sorted(models.items(), key=lambda x: -x[1]):
    print(f"MODEL\t{m}\t{out}")

# Daily trend (last 7 days)
days_order = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
for day in days_order:
    print(f"DAY\t{day}\t{daily_out.get(day, 0)}")
PYEOF
    )

    # Parse periods
    local h_in h_out h_req d_in d_out d_req w_in w_out w_req a_in a_out a_req
    while IFS=$'\t' read -r _ name inp out req extra1 extra2; do
        case "$name" in
            1h)    h_in=$inp; h_out=$out; h_req=$req ;;
            today) d_in=$inp; d_out=$out; d_req=$req ;;
            week)  w_in=$inp; w_out=$out; w_req=$req ;;
            all)   a_in=$inp; a_out=$out; a_req=$req ;;
        esac
    done <<< "$(echo "$data" | grep "^PERIOD")"

    # Time remaining
    local hours_today hours_week
    IFS=$'\t' read -r _ hours_today hours_week <<< "$(echo "$data" | grep "^TIME")"

    # Format tokens
    fmt_tok() {
        local n=$1
        if [ "$n" -ge 1000000 ]; then
            echo "$((n/1000000)).$((n%1000000/100000))M"
        elif [ "$n" -ge 1000 ]; then
            echo "$((n/1000)).$((n%1000/100))K"
        else
            echo "$n"
        fi
    }

    # ── Token usage table ──
    printf " ${DIM}%-8s %10s %10s %6s${RESET}\n" "" "input" "output" "reqs"
    printf " ${DIM}%-8s %10s %10s %6s${RESET}\n" "--------" "----------" "----------" "------"
    printf " ${BOLD}%-8s${RESET} %10s %10s %6s\n" "1 hour" "$(fmt_tok ${h_in:-0})" "$(fmt_tok ${h_out:-0})" "${h_req:-0}"
    printf " ${BOLD}%-8s${RESET} %10s %10s %6s\n" "Today" "$(fmt_tok ${d_in:-0})" "$(fmt_tok ${d_out:-0})" "${d_req:-0}"
    printf " ${YELLOW}%-8s${RESET} %10s %10s %6s\n" "Week" "$(fmt_tok ${w_in:-0})" "$(fmt_tok ${w_out:-0})" "${w_req:-0}"
    printf " ${DIM}%-8s %10s %10s %6s${RESET}\n" "All time" "$(fmt_tok ${a_in:-0})" "$(fmt_tok ${a_out:-0})" "${a_req:-0}"
    echo ""

    # ── Time remaining ──
    echo -e " ${BOLD}Remaining:${RESET} ${GREEN}${hours_today:-?}h${RESET} today  ${GREEN}${hours_week:-?}h${RESET} this week"
    echo ""

    # ── Rate (output tokens per hour) ──
    if [ "${d_req:-0}" -gt 0 ] && [ "${hours_today:-24}" -lt 24 ]; then
        local hours_used=$(( 24 - ${hours_today:-0} ))
        [ "$hours_used" -eq 0 ] && hours_used=1
        local rate=$(( ${d_out:-0} / hours_used ))
        echo -e " ${DIM}Rate: ~$(fmt_tok $rate) out/hour today${RESET}"
    fi

    # ── Models this week ──
    local model_lines
    model_lines=$(echo "$data" | grep "^MODEL")
    if [ -n "$model_lines" ]; then
        echo ""
        echo -e " ${BOLD}Models (week):${RESET}"
        echo "$model_lines" | while IFS=$'\t' read -r _ model out; do
            [ -z "$model" ] && continue
            echo -e "   ${MAGENTA}${model}${RESET}  ${DIM}$(fmt_tok $out) output${RESET}"
        done
    fi

    # ── Daily bar chart ──
    echo ""
    echo -e " ${BOLD}Daily output:${RESET}"
    local max_day_val=1
    local -a day_names=() day_vals=()
    while IFS=$'\t' read -r _ day val; do
        day_names+=("$day")
        day_vals+=("$val")
        [ "$val" -gt "$max_day_val" ] && max_day_val=$val
    done <<< "$(echo "$data" | grep "^DAY")"

    local today_name
    today_name=$(date +%a)
    local bar_width=20

    for ((i=0; i<${#day_names[@]}; i++)); do
        local d="${day_names[$i]}"
        local v="${day_vals[$i]}"
        local bar_len=$(( v * bar_width / max_day_val ))
        [ "$v" -gt 0 ] && [ "$bar_len" -eq 0 ] && bar_len=1

        local bar=""
        for ((j=0; j<bar_len; j++)); do bar+="="; done

        local color="$DIM"
        [ "$d" = "$today_name" ] && color="$GREEN"

        printf " ${color} %-3s %s ${DIM}%s${RESET}\n" "$d" "$bar" "$(fmt_tok $v)"
    done
}

while true; do
    draw
    sleep 30
done
