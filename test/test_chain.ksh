#!/usr/bin/env ksh
. "${0%/*}/../init.ksh"
. "${0%/*}/helpers.ksh"

# --- Test helpers ---
function double_value {
    typeset -n _r=$1
    typeset -i n=${_r.value}
    _r.ok "$(( n * 2 ))"
}

function add_ten {
    typeset -n _r=$1
    typeset -i n=${_r.value}
    _r.ok "$(( n + 10 ))"
}

function always_fail {
    typeset -n _r=$1
    _r.err "intentional failure" 99
}

function recover {
    typeset -n _r=$1
    _r.ok "recovered"
}

# --- chain: success path ---
Result_t r1
r1.ok "5"
chain r1 double_value
assert_eq "chain success" "${r1.value}" "10"

# --- chain: short-circuit on error ---
Result_t r2
r2.ok "5"
chain r2 always_fail
chain r2 double_value    # should be skipped
assert_eq "chain short-circuits" "${r2.status}" "err"
assert_eq "chain preserved error" "${r2.error}" "intentional failure"
assert_eq "chain error code" "${r2.code}" "99"

# --- sequence ---
Result_t r3
r3.ok "3"
sequence r3 double_value add_ten double_value
assert_eq "sequence all ok" "${r3.value}" "32"  # (3*2+10)*2

# --- sequence stops on error ---
Result_t r4
r4.ok "3"
sequence r4 double_value always_fail add_ten
assert_eq "sequence stops on error" "${r4.status}" "err"

# --- or_else: recovers from error ---
Result_t r5
r5.err "original failure"
or_else r5 recover
assert_eq "or_else recovers" "${r5.status}" "ok"
assert_eq "or_else value" "${r5.value}" "recovered"

# --- or_else: does nothing on ok ---
Result_t r6
r6.ok "fine"
or_else r6 always_fail
assert_eq "or_else skips on ok" "${r6.status}" "ok"
assert_eq "or_else keeps value" "${r6.value}" "fine"

# --- map_result ---
Result_t r7
r7.ok "hello world"
map_result r7 tr ' ' '_'
assert_eq "map_result transforms" "${r7.value}" "hello_world"

# --- map_result skips on error ---
Result_t r8
r8.err "already broken"
map_result r8 tr ' ' '_'
assert_eq "map_result skips err" "${r8.status}" "err"

# --- try_cmd: success ---
Result_t r9
try_cmd r9 print -n "output"
assert_eq "try_cmd success" "${r9.value}" "output"

# --- try_cmd: failure ---
Result_t r10
try_cmd r10 false
assert_eq "try_cmd failure" "${r10.status}" "err"

# --- guard: passes ---
Result_t r11
r11.ok "nonempty"
guard r11 "must not be empty" test -n
assert_eq "guard passes" "${r11.status}" "ok"

# --- guard: fails ---
Result_t r12
r12.ok ""
guard r12 "must not be empty" test -n
assert_eq "guard fails" "${r12.status}" "err"
assert_eq "guard message" "${r12.error}" "must not be empty"

# --- Full pipeline: chain + or_else + map_result ---
Result_t r13
r13.ok "5"
chain r13 double_value
chain r13 always_fail
or_else r13 recover
map_result r13 tr 'r' 'R'
assert_eq "full pipeline" "${r13.value}" "RecoveRed"

# --- chain defensive catch: function exits non-zero without .err ---
function crash_without_err {
    typeset -n _r=$1
    return 42  # exits non-zero but never calls _r.err
}

Result_t r14
r14.ok "before crash"
chain r14 crash_without_err
assert_eq "chain catches silent crash" "${r14.status}" "err"
assert_eq "chain captures exit code" "${r14.code}" "42"

# --- sequence defensive catch ---
Result_t r15
r15.ok "3"
sequence r15 double_value crash_without_err add_ten
assert_eq "sequence catches silent crash" "${r15.status}" "err"
assert_eq "sequence captures exit code" "${r15.code}" "42"

# --- guard with value containing spaces ---
Result_t r16
r16.ok "/path/with spaces/file"
guard r16 "path must exist" test -n
assert_eq "guard with spaces" "${r16.status}" "ok"

# --- map_result with multiline value ---
Result_t r17
r17.ok $'line1\nline2\nline3'
map_result r17 wc -l
# 2 embedded newlines + 1 from print = 3 newlines → wc -l reports 3
typeset wc_val=${r17.value}
wc_val=${wc_val##*([[:space:]])}
assert_eq "map multiline wc" "$wc_val" "3"

# --- safe_fetch: URL scheme validation ---
Result_t r18
safe_fetch r18 "ftp://bad.scheme/file"
assert_eq "fetch rejects ftp" "${r18.status}" "err"

Result_t r19
safe_fetch r19 "javascript:alert(1)"
assert_eq "fetch rejects js" "${r19.status}" "err"

# --- sequence with --: per-function extra args ---
function add_n {
    typeset -n _r=$1; shift
    typeset -i n=${_r.value}
    typeset -i delta=$1
    _r.ok "$(( n + delta ))"
}

Result_t rs1
rs1.ok "1"
sequence rs1 add_n 10 -- double_value -- add_n 3
assert_eq "sequence -- args" "${rs1.value}" "25"  # (1+10)*2+3

# --- sequence with --: stops on error ---
Result_t rs2
rs2.ok "1"
sequence rs2 add_n 10 -- always_fail -- double_value
assert_eq "sequence -- stops on err" "${rs2.status}" "err"

# --- lift: bridges stdin/stdout filter to chain convention ---
Result_t rl1
rl1.ok "hello world"
chain rl1 lift tr ' ' '_'
assert_eq "lift transforms" "${rl1.value}" "hello_world"

# --- lift: skips on error ---
Result_t rl2
rl2.err "already broken"
chain rl2 lift tr ' ' '_'
assert_eq "lift skips err" "${rl2.status}" "err"

# --- lift: in sequence with native functions ---
function prepend_hi {
    typeset -n _r=$1
    _r.ok "hi ${_r.value}"
}
function to_upper { lift "$1" tr '[:lower:]' '[:upper:]'; }
Result_t rl3
rl3.ok "world"
sequence rl3 prepend_hi to_upper
assert_eq "lift in sequence" "${rl3.value}" "HI WORLD"

# --- tap: observe without modifying ---
typeset _tap_log=''
function _tap_logger {
    typeset -n _r=$1
    _tap_log="saw:${_r.value}"
    _r.ok "CORRUPTED"   # tap should discard this
}

Result_t rt1
rt1.ok "original"
tap rt1 _tap_logger
assert_eq "tap preserves value" "${rt1.value}" "original"
assert_eq "tap called observer" "$_tap_log" "saw:original"

# --- tap: works on err too ---
Result_t rt2
rt2.err "broken" 42
typeset _tap_err_log=''
function _tap_err_logger {
    typeset -n _r=$1
    _tap_err_log="err:${_r.error}"
}
tap rt2 _tap_err_logger
assert_eq "tap on err preserves" "${rt2.status}" "err"
assert_eq "tap on err called" "$_tap_err_log" "err:broken"

# --- wrap_err: adds context to error ---
Result_t r20
r20.err "permission denied: /usr/local/bin" 1
wrap_err r20 "deploying myapp"
assert_eq "wrap_err message" "${r20.error}" "deploying myapp: permission denied: /usr/local/bin"
assert_eq "wrap_err keeps code" "${r20.code}" "1"

# --- wrap_err: no-op on ok ---
Result_t r21
r21.ok "fine"
wrap_err r21 "should not appear"
assert_eq "wrap_err skips ok" "${r21.status}" "ok"
assert_eq "wrap_err ok value" "${r21.value}" "fine"

# --- wrap_err: in a chain pipeline ---
Result_t r22
r22.ok "5"
chain r22 always_fail
wrap_err r22 "while computing"
assert_eq "wrap_err in pipeline" "${r22.error}" "while computing: intentional failure"

print "chain+combinators: ${pass} passed, ${fail} failed"
(( fail == 0 ))
