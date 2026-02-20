#!/usr/bin/env ksh
. "${0%/*}/../init.ksh"
. "${0%/*}/helpers.ksh"

# --- Test helpers ---
typeset -i call_count=0

function counting_double {
    typeset -n _r=$1
    (( call_count++ ))
    typeset -i n=${_r.value}
    _r.ok "$(( n * 2 ))"
}

function counting_add {
    typeset -n _r=$1; shift
    (( call_count++ ))
    typeset -i n=${_r.value}
    typeset -i delta=$1
    _r.ok "$(( n + delta ))"
}

function counting_fail {
    typeset -n _r=$1
    (( call_count++ ))
    _r.err "intentional failure" 42
}

function crash_without_err {
    typeset -n _r=$1
    return 7
}

# ===== memo: basic caching =====

# --- first call executes, second call hits cache ---
call_count=0
Result_t m1
m1.ok "5"
chain m1 memo counting_double
assert_eq "memo first call value" "${m1.value}" "10"
assert_eq "memo first call count" "$call_count" "1"

Result_t m2
m2.ok "5"
chain m2 memo counting_double
assert_eq "memo cache hit value" "${m2.value}" "10"
assert_eq "memo cache hit count" "$call_count" "1"

# --- different input gets different result ---
Result_t m3
m3.ok "7"
chain m3 memo counting_double
assert_eq "memo different input" "${m3.value}" "14"
assert_eq "memo different input count" "$call_count" "2"

# --- extra args are part of cache key ---
call_count=0
memo_clear

Result_t m4
m4.ok "5"
chain m4 memo counting_add 10
assert_eq "memo with args value" "${m4.value}" "15"
assert_eq "memo with args count" "$call_count" "1"

Result_t m5
m5.ok "5"
chain m5 memo counting_add 10
assert_eq "memo args cache hit" "${m5.value}" "15"
assert_eq "memo args cache hit count" "$call_count" "1"

Result_t m6
m6.ok "5"
chain m6 memo counting_add 20
assert_eq "memo different args" "${m6.value}" "25"
assert_eq "memo different args count" "$call_count" "2"

# --- error results are cached too ---
call_count=0
memo_clear

Result_t m7
m7.ok "5"
chain m7 memo counting_fail
assert_eq "memo err status" "${m7.status}" "err"
assert_eq "memo err count" "$call_count" "1"

Result_t m8
m8.ok "5"
chain m8 memo counting_fail
assert_eq "memo err cache hit" "${m8.status}" "err"
assert_eq "memo err cache count" "$call_count" "1"

# --- values with spaces survive cache round-trip ---
memo_clear
call_count=0

function echo_back {
    typeset -n _r=$1
    (( call_count++ ))
    _r.ok "got: ${_r.value}"
}

Result_t m9
m9.ok "hello world"
chain m9 memo echo_back
assert_eq "memo spaces first" "${m9.value}" "got: hello world"

Result_t m10
m10.ok "hello world"
chain m10 memo echo_back
assert_eq "memo spaces cached" "${m10.value}" "got: hello world"
assert_eq "memo spaces count" "$call_count" "1"

# ===== memo_clear =====

# --- memo_clear with no args clears all ---
memo_clear
call_count=0

Result_t mc1
mc1.ok "5"
chain mc1 memo counting_double
assert_eq "memo before clear" "$call_count" "1"

memo_clear

Result_t mc2
mc2.ok "5"
chain mc2 memo counting_double
assert_eq "memo after clear" "$call_count" "2"

# --- memo_clear with fn name clears only that function ---
memo_clear
call_count=0

Result_t mc3
mc3.ok "5"
chain mc3 memo counting_double
chain mc3 memo counting_add 10

assert_eq "memo two fns count" "$call_count" "2"

memo_clear counting_double

call_count=0
Result_t mc4
mc4.ok "5"
chain mc4 memo counting_double
assert_eq "memo selective clear fires" "$call_count" "1"

Result_t mc5
mc5.ok "10"
chain mc5 memo counting_add 10
assert_eq "memo selective clear keeps" "$call_count" "1"

# ===== memo: crash detection =====

memo_clear
Result_t mc6
mc6.ok "before crash"
chain mc6 memo crash_without_err
assert_eq "memo crash detection status" "${mc6.status}" "err"
assert_eq "memo crash detection code" "${mc6.code}" "7"

# ===== memo: skip on err (via chain) =====

memo_clear
Result_t mc7
mc7.err "already broken" 1
chain mc7 memo counting_double
assert_eq "memo skip on err" "${mc7.status}" "err"
assert_eq "memo skip on err msg" "${mc7.error}" "already broken"

print "memo: ${pass} passed, ${fail} failed"
(( fail == 0 ))
