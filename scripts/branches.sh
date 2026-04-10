#!/usr/bin/env bash

# Use alternate screen buffer — prevents scroll accumulation
tput smcup 2>/dev/null
trap 'tput rmcup 2>/dev/null' EXIT INT TERM

BOLD='\033[1m'; DIM='\033[2m'; UNDERLINE='\033[4m'
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'
RESET='\033[0m'

# Branch colors cycle
BCOLORS=("$GREEN" "$YELLOW" "$MAGENTA" "$BLUE" "$CYAN" "$RED")

PROJECT_DIR="${PANEL_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
PROJECT_NAME="${PANEL_PROJECT_NAME:-$(basename "$PROJECT_DIR")}"

draw() {
    tput cup 0 0
    tput ed

    cd "$PROJECT_DIR" 2>/dev/null || return

    local now current main_branch
    now=$(date '+%H:%M:%S')
    current=$(git branch --show-current 2>/dev/null || echo "detached")
    main_branch="main"
    git rev-parse --verify main &>/dev/null || main_branch="master"

    local lines_avail
    lines_avail=$(tput lines 2>/dev/null || echo 40)

    echo -e " ${BOLD}${CYAN}Git${RESET}  ${DIM}${PROJECT_NAME}  ${now}${RESET}"

    # Working tree status
    local modified staged untracked
    modified=$(git diff --name-only 2>/dev/null | wc -l | tr -d ' ')
    staged=$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
    untracked=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')

    local wt_parts=()
    [ "$modified" -gt 0 ] && wt_parts+=("${YELLOW}${modified} modified${RESET}")
    [ "$staged" -gt 0 ] && wt_parts+=("${GREEN}${staged} staged${RESET}")
    [ "$untracked" -gt 0 ] && wt_parts+=("${RED}${untracked} untracked${RESET}")
    if [ ${#wt_parts[@]} -gt 0 ]; then
        echo -e " $(IFS=', '; echo "${wt_parts[*]}")"
    else
        echo -e " ${GREEN}clean${RESET}"
    fi
    echo ""

    # ── Local branches ──
    echo -e " ${BOLD}Local branches:${RESET}"

    local -a branch_names=()
    local -a branch_dates=()
    local -a branch_aheads=()
    local -a branch_behinds=()
    local -a branch_authors=()

    while IFS=$'\t' read -r branch date author; do
        [ -z "$branch" ] && continue
        branch_names+=("$branch")
        branch_dates+=("$date")
        branch_authors+=("$author")

        local ahead=0 behind=0
        if [ "$branch" != "$main_branch" ] && git rev-parse --verify "$main_branch" &>/dev/null; then
            ahead=$(git rev-list --count "${main_branch}..${branch}" 2>/dev/null || echo 0)
            behind=$(git rev-list --count "${branch}..${main_branch}" 2>/dev/null || echo 0)
        fi
        branch_aheads+=("$ahead")
        branch_behinds+=("$behind")
    done < <(git for-each-ref --sort=-committerdate \
        --format='%(refname:short)	%(committerdate:relative)	%(authorname)' \
        refs/heads/ 2>/dev/null)

    local num_branches=${#branch_names[@]}
    local max_show=$((num_branches > 12 ? 12 : num_branches))

    for ((i=0; i<max_show; i++)); do
        local branch="${branch_names[$i]}"
        local date="${branch_dates[$i]}"
        local ahead="${branch_aheads[$i]}"
        local behind="${branch_behinds[$i]}"
        local author="${branch_authors[$i]}"
        local bcolor="${BCOLORS[$((i % ${#BCOLORS[@]}))]}"

        # Marker
        local marker="  "
        [ "$branch" = "$current" ] && marker="${GREEN}*${RESET} "

        # Track indicator
        local track=""
        if [ "$branch" = "$main_branch" ]; then
            track="${DIM}(base)${RESET}"
        elif [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
            track="${GREEN}+${ahead}${RESET}${RED}-${behind}${RESET}"
        elif [ "$ahead" -gt 0 ]; then
            track="${GREEN}+${ahead}${RESET}"
        elif [ "$behind" -gt 0 ]; then
            track="${RED}-${behind}${RESET}"
        else
            track="${DIM}=${RESET}"
        fi

        # Truncate
        local bname="$branch"
        [ ${#bname} -gt 28 ] && bname="${bname:0:25}..."

        # First word of author
        local short_author="${author%% *}"

        printf " %b${bcolor}%-28s${RESET} %-8b ${DIM}%-12s %s${RESET}\n" \
            "$marker" "$bname" "$track" "$date" "$short_author"
    done

    [ "$num_branches" -gt "$max_show" ] && echo -e " ${DIM}  ... +$((num_branches - max_show)) more${RESET}"
    echo ""

    # ── Commits per branch ──
    echo -e " ${BOLD}Commits by branch:${RESET}"
    echo ""

    # How many branches to show commits for
    local max_branch_commits=5
    [ "$lines_avail" -lt 50 ] && max_branch_commits=3

    local shown=0
    for ((i=0; i<num_branches && shown<max_branch_commits; i++)); do
        local branch="${branch_names[$i]}"
        local bcolor="${BCOLORS[$((i % ${#BCOLORS[@]}))]}"
        local ahead="${branch_aheads[$i]}"

        # For main: show recent commits
        # For others: show commits unique to this branch (not on main)
        local log_range=""
        local branch_label=""
        if [ "$branch" = "$main_branch" ]; then
            log_range="$branch"
            branch_label="${branch}"
        else
            log_range="${main_branch}..${branch}"
            branch_label="${branch} ${DIM}(+${ahead} vs ${main_branch})${RESET}"
            # Skip if no unique commits
            [ "$ahead" -eq 0 ] && continue
        fi

        # Truncate label
        local display_label="$branch"
        [ ${#display_label} -gt 35 ] && display_label="${display_label:0:32}..."

        echo -e " ${bcolor}-- ${display_label}${RESET}"

        git log --format="%h|%cr|%an|%s" -n 3 "$log_range" 2>/dev/null | while IFS='|' read -r hash date author msg; do
            [ -z "$hash" ] && continue
            # Short author (first name or initials)
            local short_author="${author%% *}"
            [ ${#short_author} -gt 10 ] && short_author="${short_author:0:8}.."
            # Truncate message
            [ ${#msg} -gt 38 ] && msg="${msg:0:35}..."
            # Shorten date
            local short_date="${date/hace /}"
            short_date="${short_date/ ago/}"
            [ ${#short_date} -gt 8 ] && short_date="${short_date:0:8}"

            printf "    ${YELLOW}%s${RESET} ${DIM}%-8s${RESET} ${CYAN}%-10s${RESET} %s\n" \
                "$hash" "$short_date" "$short_author" "$msg"
        done
        echo ""
        shown=$((shown + 1))
    done

    # ── Stashes ──
    local stash_count
    stash_count=$(git stash list 2>/dev/null | wc -l | tr -d ' ')
    [ "$stash_count" -gt 0 ] && echo -e " ${DIM}Stashes: ${stash_count}${RESET}"

    # ── Tags ──
    local latest_tag
    latest_tag=$(git describe --tags --abbrev=0 2>/dev/null)
    [ -n "$latest_tag" ] && echo -e " ${DIM}Latest tag: ${latest_tag}${RESET}"
}

while true; do
    draw
    sleep 10
done
