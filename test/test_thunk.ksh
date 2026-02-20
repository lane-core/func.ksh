#!/usr/bin/env ksh
. "${0%/*}/../init.ksh"
. "${0%/*}/helpers.ksh"

# --- Test helpers ---
function double_value {
    typeset -n _r=$1
    typeset -i n=${_r.value}
    _r.ok "$(( n * 2 ))"
}

function add_n {
    typeset -n _r=$1; shift
    typeset -i n=${_r.value}
    typeset -i delta=$1
    _r.ok "$(( n + delta ))"
}

function recover {
    typeset -n _r=$1
    _r.ok "recovered"
}

function crash_without_err {
    typeset -n _r=$1
    return 42
}

function greet {
    typeset -n _r=$1; shift
    _r.ok "hello $1"
}

# ===== Thunk_t tests =====

# --- create with fn name only (empty argv) ---
Thunk_t t1
t1.new double_value
assert_eq "thunk fn only .fn" "${t1.fn}" "double_value"
assert_eq "thunk fn only .argv" "${t1.argv}" ""

# --- create with fn + args ---
Thunk_t t2
t2.new add_n 10
assert_eq "thunk with args .fn" "${t2.fn}" "add_n"
assert_eq "thunk with args .argv nonempty" "$(( ${#t2.argv} > 0 ))" "1"

# --- create with spaced args (printf %q round-trip) ---
Thunk_t t3
t3.new greet "hello world"
assert_eq "thunk spaced .fn" "${t3.fn}" "greet"

# --- create with quoted args (quotes survive) ---
Thunk_t t4
t4.new greet "it's a test"
assert_eq "thunk quoted .fn" "${t4.fn}" "greet"

# --- display human-readable form ---
Thunk_t t5
t5.new double_value
assert_eq "thunk display no args" "${t5}" "double_value"

Thunk_t t6
t6.new add_n 10
assert_match "thunk display with args" "${t6}" "add_n *"

# ===== force tests =====

# --- simple thunk: double_value ---
Thunk_t ft1
ft1.new double_value
Result_t fr1
fr1.ok "7"
force fr1 ft1
assert_eq "force simple" "${fr1.value}" "14"

# --- thunk with args: add_n 10 ---
Thunk_t ft2
ft2.new add_n 10
Result_t fr2
fr2.ok "5"
force fr2 ft2
assert_eq "force with args" "${fr2.value}" "15"

# --- thunk with spaced args: round-trip through printf %q + eval ---
Thunk_t ft3
ft3.new greet "big world"
Result_t fr3
fr3.ok "ignored"
force fr3 ft3
assert_eq "force spaced args" "${fr3.value}" "hello big world"

# --- empty thunk sets err ---
Thunk_t ft4
Result_t fr4
fr4.ok "was ok"
force fr4 ft4
assert_eq "force empty thunk status" "${fr4.status}" "err"
assert_match "force empty thunk msg" "${fr4.error}" "*empty thunk*"

# --- force always executes (even on err status result) ---
Thunk_t ft5
ft5.new recover
Result_t fr5
fr5.err "was broken" 1
force fr5 ft5
assert_eq "force on err status" "${fr5.status}" "ok"
assert_eq "force on err value" "${fr5.value}" "recovered"

# --- silent crash detection on thunked function ---
Thunk_t ft6
ft6.new crash_without_err
Result_t fr6
fr6.ok "before crash"
force fr6 ft6
assert_eq "force crash detection status" "${fr6.status}" "err"
assert_eq "force crash detection code" "${fr6.code}" "42"
assert_match "force crash detection msg" "${fr6.error}" "*crash_without_err*"

# --- chain r force t pattern (ok-gated thunk execution) ---
Thunk_t ft7
ft7.new double_value
Result_t fr7
fr7.ok "6"
chain fr7 force ft7
assert_eq "chain+force ok" "${fr7.value}" "12"

# --- chain r force t skips on err ---
Thunk_t ft8
ft8.new double_value
Result_t fr8
fr8.err "already broken" 1
chain fr8 force ft8
assert_eq "chain+force err skip" "${fr8.status}" "err"
assert_eq "chain+force err msg" "${fr8.error}" "already broken"

# --- pipeline of chain r force calls ---
Thunk_t tp1
tp1.new double_value
Thunk_t tp2
tp2.new add_n 3
Result_t fp1
fp1.ok "4"
chain fp1 force tp1
chain fp1 force tp2
assert_eq "force pipeline" "${fp1.value}" "11"   # 4*2+3

# --- match r force_ok force_err pattern ---
function force_thunk_a {
    typeset -n _r=$1
    # thunk ta is in outer scope
    force "$1" ta
}
function force_thunk_b {
    typeset -n _r=$1
    force "$1" tb
}

Thunk_t ta
ta.new double_value
Thunk_t tb
tb.new recover

Result_t fm1
fm1.ok "5"
match fm1 force_thunk_a force_thunk_b
assert_eq "match+force ok arm" "${fm1.value}" "10"

Result_t fm2
fm2.err "broken" 1
match fm2 force_thunk_a force_thunk_b
assert_eq "match+force err arm" "${fm2.value}" "recovered"

print "thunk+force: ${pass} passed, ${fail} failed"
(( fail == 0 ))
