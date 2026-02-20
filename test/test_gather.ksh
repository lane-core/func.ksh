#!/usr/bin/env ksh
. "${0%/*}/../init.ksh"
. "${0%/*}/helpers.ksh"

# --- Test helpers ---
function succeed_with_upper {
    typeset -n _r=$1
    typeset val=${_r.value}
    _r.ok "${val^^}"
}

function always_fail_ga {
    typeset -n _r=$1
    _r.err "fail: ${_r.value}" 1
}

function fail_if_odd {
    typeset -n _r=$1
    typeset -i n=${_r.value}
    if (( n % 2 == 1 )); then
        _r.err "odd: $n" 1
    else
        _r.ok "$n"
    fi
}

function crash_silent {
    typeset -n _r=$1
    return 7
}

# Uses chain internally — chain should short-circuit within item,
# but gather should still continue to the next item.
function chain_inside {
    typeset -n _r=$1
    typeset val=${_r.value}
    if [[ $val == "bad" ]]; then
        _r.err "chain_inside: bad input" 1
        return 0
    fi
    _r.ok "chained:$val"
}

# --- gather: all succeed ---
Result_t g1
gather g1 succeed_with_upper "hello"
gather g1 succeed_with_upper "world"
assert_eq "gather all ok status" "${g1.status}" "ok"
assert_eq "gather all ok code" "${g1.code}" "0"

# --- gather: single failure ---
Result_t g2
gather g2 always_fail_ga "oops"
assert_eq "gather single fail status" "${g2.status}" "err"
assert_eq "gather single fail error" "${g2.error}" "fail: oops"
assert_eq "gather single fail code" "${g2.code}" "1"

# --- gather: multiple failures ---
Result_t g3
gather g3 always_fail_ga "a"
gather g3 always_fail_ga "b"
gather g3 always_fail_ga "c"
assert_eq "gather multi fail status" "${g3.status}" "err"
assert_eq "gather multi fail code" "${g3.code}" "3"
# errors should be newline-separated
assert_match "gather multi error has a" "${g3.error}" "*fail: a*"
assert_match "gather multi error has b" "${g3.error}" "*fail: b*"
assert_match "gather multi error has c" "${g3.error}" "*fail: c*"

# --- gather: mixed success/failure ---
Result_t g4
gather g4 fail_if_odd "2"
gather g4 fail_if_odd "3"
gather g4 fail_if_odd "4"
gather g4 fail_if_odd "5"
assert_eq "gather mixed status" "${g4.status}" "err"
assert_eq "gather mixed code" "${g4.code}" "2"
assert_match "gather mixed has odd 3" "${g4.error}" "*odd: 3*"
assert_match "gather mixed has odd 5" "${g4.error}" "*odd: 5*"

# --- gather: function uses chain internally ---
Result_t g5
gather g5 chain_inside "good"
gather g5 chain_inside "bad"
gather g5 chain_inside "also_good"
assert_eq "gather chain-inside status" "${g5.status}" "err"
assert_eq "gather chain-inside code" "${g5.code}" "1"
assert_match "gather chain-inside error" "${g5.error}" "*chain_inside: bad input*"

# --- gather: defensive catch (fn exits non-zero without .err) ---
Result_t g6
gather g6 crash_silent "input"
assert_eq "gather defensive catch status" "${g6.status}" "err"
assert_match "gather defensive catch msg" "${g6.error}" "*gather:*crash_silent*exited*7*"

# --- collect: batch success ---
Result_t c1
collect c1 succeed_with_upper a b c
assert_eq "collect all ok status" "${c1.status}" "ok"

# --- collect: batch with failures ---
Result_t c2
collect c2 fail_if_odd 1 2 3 4
assert_eq "collect batch fail status" "${c2.status}" "err"
assert_eq "collect batch fail code" "${c2.code}" "2"
assert_match "collect has odd 1" "${c2.error}" "*odd: 1*"
assert_match "collect has odd 3" "${c2.error}" "*odd: 3*"

# --- collect: composable (two collect calls on same accumulator) ---
Result_t c3
collect c3 fail_if_odd 2 4
assert_eq "collect first batch ok" "${c3.status}" "ok"
collect c3 fail_if_odd 1 6
assert_eq "collect composable status" "${c3.status}" "err"
assert_eq "collect composable code" "${c3.code}" "1"
assert_match "collect composable error" "${c3.error}" "*odd: 1*"

# --- collect: empty argument list ---
Result_t c4
collect c4 always_fail_ga
assert_eq "collect empty args status" "${c4.status}" "ok"
assert_eq "collect empty args code" "${c4.code}" "0"

# --- gather with extra args passed through ---
function check_extra_arg {
    typeset -n _r=$1; shift
    typeset extra=$1
    if [[ $extra == "reject" ]]; then
        _r.err "rejected by extra arg" 1
    else
        _r.ok "${_r.value}+$extra"
    fi
}

Result_t g7
gather g7 check_extra_arg "base" "accept"
assert_eq "gather extra arg ok" "${g7.status}" "ok"

Result_t g8
gather g8 check_extra_arg "base" "reject"
assert_eq "gather extra arg fail" "${g8.status}" "err"
assert_eq "gather extra arg msg" "${g8.error}" "rejected by extra arg"

# --- map_collect: all succeed ---
function double_val {
    typeset -n _r=$1
    typeset -i n=${_r.value}
    _r.ok "$(( n * 2 ))"
}

Result_t mc1
map_collect mc1 double_val 3 5 7
assert_eq "map_collect all ok status" "${mc1.status}" "ok"
assert_eq "map_collect all ok values" "${mc1.value}" $'6\n10\n14'

# --- map_collect: mixed success/failure ---
Result_t mc2
map_collect mc2 fail_if_odd 2 3 4 5 6
assert_eq "map_collect mixed status" "${mc2.status}" "err"
assert_eq "map_collect mixed code" "${mc2.code}" "2"
assert_eq "map_collect mixed values" "${mc2.value}" $'2\n4\n6'
assert_match "map_collect mixed errors" "${mc2.error}" "*odd: 3*"
assert_match "map_collect mixed errors 5" "${mc2.error}" "*odd: 5*"

# --- map_collect: all fail ---
Result_t mc3
map_collect mc3 always_fail_ga x y
assert_eq "map_collect all fail status" "${mc3.status}" "err"
assert_eq "map_collect all fail code" "${mc3.code}" "2"
assert_eq "map_collect all fail value" "${mc3.value}" ""

# --- map_collect: empty args ---
Result_t mc4
map_collect mc4 double_val
assert_eq "map_collect empty status" "${mc4.status}" "ok"

print "gather+collect: ${pass} passed, ${fail} failed"
(( fail == 0 ))
