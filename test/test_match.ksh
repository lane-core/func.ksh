#!/usr/bin/env ksh
. "${0%/*}/../init.ksh"
. "${0%/*}/helpers.ksh"

# --- Test helpers ---
function double_value {
    typeset -n _r=$1
    typeset -i n=${_r.value}
    _r.ok "$(( n * 2 ))"
}

function recover {
    typeset -n _r=$1
    _r.ok "recovered"
}

function always_fail {
    typeset -n _r=$1
    _r.err "intentional failure" 99
}

function add_extra {
    typeset -n _r=$1; shift
    _r.ok "${_r.value}+$1"
}

function recover_extra {
    typeset -n _r=$1; shift
    _r.ok "fixed+$1"
}

function crash_without_err {
    typeset -n _r=$1
    return 42
}

function recode_err {
    typeset -n _r=$1
    _r.err "recoded: ${_r.error}" 50
}

function handle_code6 {
    typeset -n _r=$1
    _r.ok "dns resolved via fallback"
}

function handle_code22 {
    typeset -n _r=$1
    _r.ok "http error handled"
}

function handle_default {
    typeset -n _r=$1
    _r.ok "default handler fired"
}

function recode_handler {
    typeset -n _r=$1
    _r.err "re-errored from handler" 77
}

# ===== match tests =====

# --- ok dispatches to ok_fn ---
Result_t m1
m1.ok "5"
match m1 double_value recover
assert_eq "match ok dispatches" "${m1.value}" "10"

# --- err dispatches to err_fn ---
Result_t m2
m2.err "broken" 1
match m2 double_value recover
assert_eq "match err dispatches" "${m2.status}" "ok"
assert_eq "match err recovers" "${m2.value}" "recovered"

# --- ok with '-' err_fn (equivalent to chain) ---
Result_t m3
m3.ok "5"
match m3 double_value -
assert_eq "match ok skip err" "${m3.value}" "10"

# --- err with ok_fn '-' (equivalent to or_else) ---
Result_t m4
m4.err "broken" 1
match m4 - recover
assert_eq "match err skip ok" "${m4.value}" "recovered"

# --- both arms '-' on ok (no-op) ---
Result_t m5
m5.ok "untouched"
match m5 - -
assert_eq "match both dash ok" "${m5.value}" "untouched"

# --- both arms '-' on err (no-op) ---
Result_t m6
m6.err "still broken" 3
match m6 - -
assert_eq "match both dash err status" "${m6.status}" "err"
assert_eq "match both dash err msg" "${m6.error}" "still broken"

# --- atomicity: ok_fn sets err, err_fn must NOT fire ---
function ok_then_fail {
    typeset -n _r=$1
    _r.err "ok arm failed" 88
}
function err_should_not_fire {
    typeset -n _r=$1
    _r.ok "err arm incorrectly fired"
}

Result_t m7
m7.ok "starting"
match m7 ok_then_fail err_should_not_fire
assert_eq "match atomicity status" "${m7.status}" "err"
assert_eq "match atomicity error" "${m7.error}" "ok arm failed"
assert_eq "match atomicity code" "${m7.code}" "88"

# --- extra args forwarded to ok_fn ---
Result_t m8
m8.ok "base"
match m8 add_extra recover_extra "X"
assert_eq "match extra args ok" "${m8.value}" "base+X"

# --- extra args forwarded to err_fn ---
Result_t m9
m9.err "broken" 1
match m9 add_extra recover_extra "Y"
assert_eq "match extra args err" "${m9.value}" "fixed+Y"

# --- silent crash detection on ok arm ---
Result_t m10
m10.ok "before crash"
match m10 crash_without_err recover
assert_eq "match crash detection status" "${m10.status}" "err"
assert_eq "match crash detection code" "${m10.code}" "42"
assert_match "match crash detection msg" "${m10.error}" "*crash_without_err*"

# --- err arm preserves root cause on handler crash ---
function crash_recovery {
    typeset -n _r=$1
    return 7
}
Result_t m11
m11.err "original root cause" 5
match m11 double_value crash_recovery
assert_eq "match err root cause" "${m11.status}" "err"
assert_eq "match err root cause msg" "${m11.error}" "original root cause"
assert_eq "match err root cause code" "${m11.code}" "5"

# --- fewer than 3 args sets err diagnostic ---
Result_t m12
m12.ok "was ok"
match m12 double_value
assert_eq "match too few args status" "${m12.status}" "err"
assert_match "match too few args msg" "${m12.error}" "*match*requires*"

# --- value with spaces survives dispatch ---
Result_t m13
m13.ok "hello world"
function echo_back {
    typeset -n _r=$1
    _r.ok "got: ${_r.value}"
}
match m13 echo_back -
assert_eq "match spaces" "${m13.value}" "got: hello world"

# ===== case_code tests =====

# --- pass through on ok status ---
Result_t c1
c1.ok "fine"
case_code c1 6:handle_code6 22:handle_code22
assert_eq "case_code ok passthrough" "${c1.status}" "ok"
assert_eq "case_code ok value" "${c1.value}" "fine"

# --- exact code match fires handler ---
Result_t c2
c2.err "dns failure" 6
case_code c2 6:handle_code6 22:handle_code22
assert_eq "case_code match 6" "${c2.status}" "ok"
assert_eq "case_code match 6 val" "${c2.value}" "dns resolved via fallback"

Result_t c3
c3.err "http error" 22
case_code c3 6:handle_code6 22:handle_code22
assert_eq "case_code match 22" "${c3.status}" "ok"
assert_eq "case_code match 22 val" "${c3.value}" "http error handled"

# --- first match wins (duplicate codes) ---
Result_t c4
c4.err "ambiguous" 6
case_code c4 6:handle_code6 6:handle_code22
assert_eq "case_code first wins" "${c4.value}" "dns resolved via fallback"

# --- default fires when no code matches ---
Result_t c5
c5.err "unknown problem" 99
case_code c5 6:handle_code6 22:handle_code22 default:handle_default
assert_eq "case_code default" "${c5.value}" "default handler fired"

# --- no match + no default preserves original error ---
Result_t c6
c6.err "mystery" 42
case_code c6 6:handle_code6 22:handle_code22
assert_eq "case_code no match status" "${c6.status}" "err"
assert_eq "case_code no match msg" "${c6.error}" "mystery"
assert_eq "case_code no match code" "${c6.code}" "42"

# --- handler recovers (calls .ok) ---
Result_t c7
c7.err "recoverable" 6
case_code c7 6:handle_code6
assert_eq "case_code handler recovers" "${c7.status}" "ok"

# --- handler re-errors (calls .err with new message) ---
Result_t c8
c8.err "original" 6
case_code c8 6:recode_handler
assert_eq "case_code re-error status" "${c8.status}" "err"
assert_eq "case_code re-error msg" "${c8.error}" "re-errored from handler"
assert_eq "case_code re-error code" "${c8.code}" "77"

# --- '-' handler passes through for that code ---
Result_t c9
c9.err "acknowledged" 6
case_code c9 6:- 22:handle_code22
assert_eq "case_code dash handler status" "${c9.status}" "err"
assert_eq "case_code dash handler msg" "${c9.error}" "acknowledged"

# --- malformed spec (no colon) sets diagnostic err ---
Result_t c10
c10.err "some error" 1
case_code c10 bad_spec
assert_eq "case_code malformed status" "${c10.status}" "err"
assert_match "case_code malformed msg" "${c10.error}" "*malformed*bad_spec*"

# --- compose case_code with wrap_err ---
Result_t c11
c11.err "timeout" 28
case_code c11 6:handle_code6 22:handle_code22
wrap_err c11 "fetching config"
assert_eq "case_code+wrap_err" "${c11.error}" "fetching config: timeout"

print "match+case_code: ${pass} passed, ${fail} failed"
(( fail == 0 ))
