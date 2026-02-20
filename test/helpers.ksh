# Shared test assertions for func.ksh test suite
# Source after init.ksh:
#   . "${0%/*}/../init.ksh"
#   . "${0%/*}/helpers.ksh"

typeset -i pass=0 fail=0

function assert_eq {
    typeset label=$1 got=$2 want=$3
    if [[ $got == "$want" ]]; then
        (( pass++ ))
    else
        (( fail++ ))
        print -u2 "FAIL: $label (got='$got', want='$want')"
    fi
}

function assert_match {
    typeset label=$1 got=$2 pattern=$3
    if [[ $got == $pattern ]]; then
        (( pass++ ))
    else
        (( fail++ ))
        print -u2 "FAIL: $label (got='$got', pattern='$pattern')"
    fi
}

function assert_true {
    typeset label=$1; shift
    if "$@"; then
        (( pass++ ))
    else
        (( fail++ ))
        print -u2 "FAIL: $label"
    fi
}

# Check node A appears before node B in a space-separated ordering
function assert_before {
    typeset label=$1 ordering=$2 a=$3 b=$4
    typeset -a nodes
    set -A nodes $ordering
    typeset -i ai=-1 bi=-1 i=0
    typeset n
    for n in "${nodes[@]}"; do
        [[ $n == "$a" ]] && ai=$i
        [[ $n == "$b" ]] && bi=$i
        (( i++ ))
    done
    if (( ai >= 0 && bi >= 0 && ai < bi )); then
        (( pass++ ))
    else
        (( fail++ ))
        print -u2 "FAIL: $label ($a@$ai should be before $b@$bi in: $ordering)"
    fi
}
