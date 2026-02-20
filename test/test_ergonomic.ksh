#!/usr/bin/env ksh
. "${0%/*}/../init.ksh"
. "${0%/*}/helpers.ksh"

# --- Shared helpers ---
function double_value {
    typeset -n _r=$1
    typeset -i n=${_r.value}
    _r.ok "$(( n * 2 ))"
}

function always_fail {
    typeset -n _r=$1
    _r.err "intentional failure" 99
}

# ====================================================================
# tap_ok — fires observer only when status is ok
# ====================================================================

typeset _tok_log=''
function _tok_logger {
    typeset -n _r=$1
    _tok_log="saw:${_r.value}"
    _r.ok "CORRUPTED"
}

Result_t tok1
tok1.ok "hello"
tap_ok tok1 _tok_logger
assert_eq "tap_ok fires on ok" "$_tok_log" "saw:hello"
assert_eq "tap_ok preserves value" "${tok1.value}" "hello"

_tok_log=''
Result_t tok2
tok2.err "broken" 1
tap_ok tok2 _tok_logger
assert_eq "tap_ok skips on err" "$_tok_log" ""
assert_eq "tap_ok err unchanged" "${tok2.status}" "err"

# ====================================================================
# tap_err — fires observer only when status is err
# ====================================================================

typeset _ter_log=''
function _ter_logger {
    typeset -n _r=$1
    _ter_log="err:${_r.error}:${_r.code}"
    _r.ok "CORRUPTED"
}

Result_t ter1
ter1.err "disk full" 28
tap_err ter1 _ter_logger
assert_eq "tap_err fires on err" "$_ter_log" "err:disk full:28"
assert_eq "tap_err preserves status" "${ter1.status}" "err"
assert_eq "tap_err preserves error" "${ter1.error}" "disk full"

_ter_log=''
Result_t ter2
ter2.ok "fine"
tap_err ter2 _ter_logger
assert_eq "tap_err skips on ok" "$_ter_log" ""
assert_eq "tap_err ok unchanged" "${ter2.value}" "fine"

# ====================================================================
# value_into — write .value into a variable without subshell
# ====================================================================

Result_t vi1
vi1.ok "hello world"
typeset vi1_out=''
vi1.value_into vi1_out "fallback"
assert_eq "value_into on ok" "$vi1_out" "hello world"

Result_t vi2
vi2.err "broken"
typeset vi2_out=''
vi2.value_into vi2_out "default_val"
assert_eq "value_into on err" "$vi2_out" "default_val"

Result_t vi3
vi3.err "broken"
typeset vi3_out='untouched'
vi3.value_into vi3_out
assert_eq "value_into err no default" "$vi3_out" ""

# ====================================================================
# expect_into — write .value or report error and return 1
# ====================================================================

Result_t ei1
ei1.ok "payload"
typeset ei1_out=''
ei1.expect_into ei1_out "should not fail"
assert_eq "expect_into on ok" "$ei1_out" "payload"

Result_t ei2
ei2.err "something broke" 5
typeset ei2_out='untouched'
typeset ei2_stderr
ei2_stderr=$(ei2.expect_into ei2_out "loading config" 2>&1 >/dev/null)
typeset -i ei2_ret=$?
assert_eq "expect_into returns 1 on err" "$ei2_ret" "1"
assert_match "expect_into stderr" "$ei2_stderr" "*loading config*something broke*"
assert_eq "expect_into leaves var on err" "$ei2_out" "untouched"

# ====================================================================
# retry — repeat fallible operation up to N times
# ====================================================================

typeset -i _retry_count=0
function _flaky {
    typeset -n _r=$1
    (( _retry_count++ ))
    if (( _retry_count < 3 )); then
        _r.err "not yet" 1
    else
        _r.ok "finally"
    fi
    return 0
}

Result_t re1
re1.ok "input"
_retry_count=0
retry re1 5 _flaky
assert_eq "retry succeeds on 3rd" "${re1.status}" "ok"
assert_eq "retry value" "${re1.value}" "finally"
assert_eq "retry count" "$_retry_count" "3"

# retry: exhaustion preserves last error
function _always_flaky {
    typeset -n _r=$1
    _r.err "still broken" 42
    return 0
}

Result_t re2
re2.ok "input"
retry re2 3 _always_flaky
assert_eq "retry exhausted status" "${re2.status}" "err"
assert_eq "retry exhausted error" "${re2.error}" "still broken"
assert_eq "retry exhausted code" "${re2.code}" "42"

# retry: succeeds on first try
typeset -i _once_count=0
function _first_try_ok {
    typeset -n _r=$1
    (( _once_count++ ))
    _r.ok "immediate"
    return 0
}

Result_t re3
re3.ok "input"
_once_count=0
retry re3 5 _first_try_ok
assert_eq "retry first try ok" "${re3.value}" "immediate"
assert_eq "retry first try count" "$_once_count" "1"

# retry: with extra args
function _add_n {
    typeset -n _r=$1; shift
    typeset -i n=${_r.value} delta=$1
    _r.ok "$(( n + delta ))"
    return 0
}

Result_t re4
re4.ok "10"
retry re4 1 _add_n 5
assert_eq "retry with args" "${re4.value}" "15"

# retry: silent crash detection
function _crash_no_err {
    return 7
}

Result_t re5
re5.ok "input"
retry re5 2 _crash_no_err
assert_eq "retry crash detect" "${re5.status}" "err"
assert_match "retry crash msg" "${re5.error}" "*exited 7*"

# retry: resets to ok with original value before each attempt
typeset -i _reset_check=0
function _check_reset {
    typeset -n _r=$1
    (( _reset_check++ ))
    if (( _reset_check == 1 )); then
        _r.err "first fail" 1
    else
        assert_eq "retry resets value" "${_r.value}" "original"
        assert_eq "retry resets status" "${_r.status}" "ok"
        _r.ok "done"
    fi
    return 0
}

Result_t re6
re6.ok "original"
_reset_check=0
retry re6 3 _check_reset
assert_eq "retry reset result" "${re6.value}" "done"

# ====================================================================
# Version_t predicates: lt, gt, eq
# ====================================================================

Version_t va vb

va.raw="1.2.3"
vb.raw="1.2.4"
assert_true "vt lt: major.minor differ" va.lt vb
va.gt vb && typeset _vt_gt1=yes || typeset _vt_gt1=no
assert_eq "vt gt: 1.2.3 not > 1.2.4" "$_vt_gt1" "no"

va.raw="2.0.0"
vb.raw="1.9.9"
assert_true "vt gt: major greater" va.gt vb
va.lt vb && typeset _vt_lt1=yes || typeset _vt_lt1=no
assert_eq "vt lt: 2.0.0 not < 1.9.9" "$_vt_lt1" "no"

va.raw="1.2.3"
vb.raw="1.2.3"
assert_true "vt eq: same version" va.eq vb
va.lt vb && typeset _vt_lt2=yes || typeset _vt_lt2=no
assert_eq "vt lt: equal not lt" "$_vt_lt2" "no"
va.gt vb && typeset _vt_gt2=yes || typeset _vt_gt2=no
assert_eq "vt gt: equal not gt" "$_vt_gt2" "no"

# Pre-release sorts before release
va.raw="1.0.0-alpha"
vb.raw="1.0.0"
assert_true "vt lt: pre < release" va.lt vb
va.gt vb && typeset _vt_gt3=yes || typeset _vt_gt3=no
assert_eq "vt gt: pre not > release" "$_vt_gt3" "no"

# Release sorts after pre-release
va.raw="1.0.0"
vb.raw="1.0.0-beta"
assert_true "vt gt: release > pre" va.gt vb

# Pre-release equality
va.raw="1.0.0-rc.1"
vb.raw="1.0.0-rc.1"
assert_true "vt eq: same pre-release" va.eq vb

# Different pre-releases not equal
va.raw="1.0.0-alpha"
vb.raw="1.0.0-beta"
va.eq vb && typeset _vt_eq1=yes || typeset _vt_eq1=no
assert_eq "vt eq: diff pre not equal" "$_vt_eq1" "no"
assert_true "vt lt: alpha < beta" va.lt vb

# Minor version comparison
va.raw="1.3.0"
vb.raw="1.2.9"
assert_true "vt gt: minor greater" va.gt vb

# ====================================================================
# sequence optimization — verify glob path still works
# ====================================================================

# Simple mode (no --)
Result_t sq1
sq1.ok "2"
sequence sq1 double_value double_value
assert_eq "sequence simple mode" "${sq1.value}" "8"

# Delimited mode with extra args
function add_n {
    typeset -n _r=$1; shift
    typeset -i n=${_r.value} d=$1
    _r.ok "$(( n + d ))"
}

Result_t sq2
sq2.ok "1"
sequence sq2 add_n 10 -- double_value -- add_n 3
assert_eq "sequence delimited mode" "${sq2.value}" "25"

# Sequence stops on error in both modes
Result_t sq3
sq3.ok "1"
sequence sq3 double_value always_fail double_value
assert_eq "sequence stops on err" "${sq3.status}" "err"

print "ergonomic: ${pass} passed, ${fail} failed"
(( fail == 0 ))
