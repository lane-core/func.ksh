# Progress_t — nix-build-style progress reporting
#
# Completed items scroll above a single in-place status line showing
# counters and current activity. Falls back to plain per-item output
# when stderr isn't a TTY.
#
# Usage:
#   Progress_t p
#   p.begin 5 "installed" "cloning"
#   p.pool_start "my-pkg"
#   p.pool_finish
#   p.ok "my-pkg" "abc1234"
#   p.err "broken" "clone failed"
#   p.end

# ANSI: CR + clear-to-end-of-line — shared by all Progress_t methods.
typeset _PROGRESS_CLR=$'\r\033[K'

typeset -T Progress_t=(
    typeset -i total=0 done=0 fail=0 active=0
    typeset verb=''           # past tense for completed: "installed", "updated", "frozen"
    typeset active_verb=''    # present participle for in-flight: "cloning", "fetching"
    typeset current=''        # name of item currently being processed
    typeset tty=false

    function begin {
        # $1=total  $2=verb  $3=active_verb (optional)
        _.total=$1
        _.verb="${2:-done}"
        _.active_verb="${3:-active}"
        _.done=0; _.fail=0; _.active=0; _.current=''
        [[ -t 2 ]] && _.tty=true || _.tty=false
        _.render
    }

    function item {
        _.current="$1"
        _.render
    }

    function pool_start {
        (( _.active++ ))
        _.current="$1"
        _.render
    }

    function pool_finish {
        (( _.active > 0 )) && (( _.active-- ))
        _.render
    }

    function ok {
        # $1=name  $2=detail (optional, e.g. short sha)
        (( _.done++ ))
        typeset name="$1" detail="${2:-}"
        [[ ${_.tty} == true ]] && printf '%s' "$_PROGRESS_CLR" >&2
        print -u2 -r -- "  ✓ ${name}${detail:+ (${detail})}"
        _.render
    }

    function err {
        # $1=name  $2=detail (optional)
        (( _.fail++ ))
        typeset name="$1" detail="${2:-}"
        [[ ${_.tty} == true ]] && printf '%s' "$_PROGRESS_CLR" >&2
        print -u2 -r -- "  ✗ ${name}${detail:+ (${detail})}"
        _.render
    }

    function skip {
        # $1=name  $2=reason (optional) — informational, not counted
        [[ ${_.tty} == true ]] && printf '%s' "$_PROGRESS_CLR" >&2
        print -u2 -r -- "  - ${1}${2:+ (${2})}"
        _.render
    }

    function render {
        [[ ${_.tty} != true ]] && return
        typeset -i c=$(( _.done + _.fail ))
        typeset body="${c}/${_.total} ${_.verb}"
        (( _.active > 0 )) && body+=", ${_.active} ${_.active_verb}"
        typeset line="[${body}]"
        [[ -n "${_.current}" ]] && line+=" ${_.current} ..."
        printf '%s%s' "$_PROGRESS_CLR" "$line" >&2
    }

    function end {
        [[ ${_.tty} == true ]] && printf '%s' "$_PROGRESS_CLR" >&2
    }
)
