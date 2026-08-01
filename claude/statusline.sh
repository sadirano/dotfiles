#!/usr/bin/env bash
# Claude Code status line (Linux / macOS / bash)
# ----------------------------------------------
# Renders:  (<alias>) <rel-path> > <model>  <branch> <dirty/clean>  <5h%> / <7d%>
#           #<context%>  @<cached-tokens>  $<cost>  +<added>/-<removed>  <duration>  <clock>
# Quota turns red when a window is over 80%. Fully portable: no hard-coded paths.
# Git branch/status uses a single fast `git status --porcelain --branch` call
# (400ms timeout when `timeout` exists) and is silent in non-repo directories.
# Requires: jq. See README.md for one-line install instructions.

raw=$(cat)

color() { printf '\033[%sm%s\033[0m' "$1" "$2"; }

command -v jq >/dev/null 2>&1 || { echo "> ?"; exit 0; }

# one jq pass: pull every field we need, newline-separated, "null" for missing
mapfile -t f < <(jq -r '
  .cwd // .workspace.current_dir // "",
  .model.display_name // "",
  .rate_limits.five_hour.used_percentage // "null",
  .rate_limits.seven_day.used_percentage // "null",
  .rate_limits.five_hour.resets_at // "null",
  .rate_limits.seven_day.resets_at // "null",
  .context_window.used_percentage // "null",
  (.context_window.current_usage.cache_read_input_tokens // 0),
  (.context_window.current_usage.cache_creation_input_tokens // 0),
  (.cost.total_cost_usd // 0),
  (.cost.total_lines_added // 0),
  (.cost.total_lines_removed // 0),
  (.cost.total_duration_ms // 0)
' <<<"$raw" 2>/dev/null | tr -d '\r')   # tr: jq on Windows emits CRLF
[[ ${#f[@]} -lt 13 ]] && { echo "> ?"; exit 0; }

cwd=${f[0]} model=${f[1]} h5=${f[2]} d7=${f[3]} r5_at=${f[4]} r7_at=${f[5]}
ctx=${f[6]} cache_read=${f[7]} cache_create=${f[8]}
cost=${f[9]} added=${f[10]} removed=${f[11]} dur_ms=${f[12]}

parts=()

# (nix alias) path > model
# Inside an `o`/`x` session nix exports NIX_ALIAS + NIX_ALIAS_PATH, so the alias
# root collapses to its name and only the part below it is spelled out. Outside
# one (or in an unrelated directory) fall back to the full absolute path.
alias_name=${NIX_ALIAS:-${nix_alias:-}}
alias_root=${NIX_ALIAS_PATH:-}
alias_root=${alias_root%/}
rel=''
have_rel=0
if [[ -n "$alias_name" && -n "$alias_root" && -n "$cwd" ]]; then
    if [[ "${cwd%/}" == "$alias_root" ]]; then
        have_rel=1
    elif [[ "$cwd" == "$alias_root"/* ]]; then
        rel=${cwd#"$alias_root"/}
        have_rel=1
    fi
fi

if (( have_rel )); then
    path_seg="$(color 33 "(${alias_name})")"
    [[ -n "$rel" ]] && path_seg+=" $(color 36 "$rel")"
else
    path_seg="$(color 36 "$cwd")"
    [[ -n "$alias_name" ]] && path_seg="$(color 33 "(${alias_name})") $path_seg"
fi
parts+=("$path_seg$(color 90 ' > ')$(color 35 "$model")")

# git branch + dirty/clean status — single fast call, silent on non-repos
git_fast() {
    if command -v timeout >/dev/null 2>&1; then
        timeout 0.4 git -C "$cwd" --no-optional-locks status --porcelain=v1 --branch 2>/dev/null
    else
        git -C "$cwd" --no-optional-locks status --porcelain=v1 --branch 2>/dev/null
    fi
}

if [[ -n "$cwd" && -d "$cwd" ]]; then
    # first line is "## branch...upstream [ahead/behind]", rest are dirty entries
    git_out=$(git_fast)
    if [[ $? -eq 0 && "$git_out" == '## '* ]]; then
        first=${git_out%%$'\n'*}
        branch=${first#\#\# }
        branch=${branch%%...*}
        [[ "$branch" == 'HEAD (no branch)'* ]] && branch='detached'
        if [[ "$git_out" == *$'\n'* ]]; then
            indicator=$(color 33 '*dirty')
        else
            indicator=$(color 32 'clean')
        fi
        parts+=("$(color 36 "$branch") $indicator")
    fi
fi

# quota (rate limits): 5-hour / 7-day — red when over 80%, else yellow
time_left() {
    local unix=$1 diff h m
    [[ "$unix" =~ ^[0-9]+$ ]] || return
    diff=$(( unix - $(date +%s) ))
    (( diff <= 0 )) && return
    h=$(( diff / 3600 ))
    m=$(( (diff % 3600) / 60 ))
    if (( h > 0 )); then printf '@%dh%dm' "$h" "$m"; else printf '@%dm' "$m"; fi
}

if [[ "$h5" != "null" || "$d7" != "null" ]]; then
    c5='33'; c7='33'
    [[ "$h5" != "null" ]] && (( ${h5%.*} > 80 )) && c5='31'
    [[ "$d7" != "null" ]] && (( ${d7%.*} > 80 )) && c7='31'

    r5=$(time_left "$r5_at")
    r7=$(time_left "$r7_at")

    seg5="$(color "$c5" "${h5}%")"; [[ -n "$r5" ]] && seg5+="$(color 90 " $r5")"
    seg7="$(color "$c7" "${d7}%")"; [[ -n "$r7" ]] && seg7+="$(color 90 " $r7")"
    parts+=("$seg5$(color 33 ' / ')$seg7")
fi

# context window usage
[[ "$ctx" != "null" ]] && parts+=("$(color 32 "#${ctx}%")")

# cached context tokens (cache_read + cache_creation), formatted with k/M suffixes
format_tokens() {
    local n=$1
    if (( n >= 1000000 )); then awk -v n="$n" 'BEGIN{printf "%.1fM", n/1000000}'
    elif (( n >= 1000 )); then awk -v n="$n" 'BEGIN{printf "%.1fk", n/1000}'
    else printf '%s' "$n"
    fi
}

cached_total=$(( cache_read + cache_create ))
(( cached_total > 0 )) && parts+=("$(color 90 "@$(format_tokens "$cached_total")")")

# session cost so far
cost_fmt=$(awk -v c="$cost" 'BEGIN{ if (c+0 > 0) printf "%.2f", c }')
[[ -n "$cost_fmt" ]] && parts+=("$(color 92 "\$${cost_fmt}")")

# lines added / removed this session
added=${added%.*}; removed=${removed%.*}
if (( added > 0 || removed > 0 )); then
    parts+=("$(color 32 "+${added}")$(color 90 '/')$(color 31 "-${removed}")")
fi

# session wall-clock duration
dur_s=$(( ${dur_ms%.*} / 1000 ))
if (( dur_s > 0 )); then
    if (( dur_s >= 3600 )); then dur=$(printf '%dh%dm' $(( dur_s / 3600 )) $(( (dur_s % 3600) / 60 )))
    elif (( dur_s >= 60 )); then dur=$(printf '%dm' $(( dur_s / 60 )))
    else dur=$(printf '%ds' "$dur_s")
    fi
    parts+=("$(color 90 "$dur")")
fi

# wall clock
parts+=("$(color 90 "$(date +%H:%M)")")

out=''
for p in "${parts[@]}"; do
    [[ -n "$out" ]] && out+='  '
    out+=$p
done
printf '%s\n' "$out"
