#!/usr/bin/env ksh
. "${0%/*}/../init.ksh"
. "${0%/*}/helpers.ksh"

# --- Test helpers ---
function check_nonempty {
    typeset -n _r=$1
    if [[ -z ${_r.value} ]]; then
        _r.err "value is empty" 1
    fi
}

function check_lowercase {
    typeset -n _r=$1
    if [[ ${_r.value} != ${_r.value,,} ]]; then
        _r.err "not all lowercase" 1
    fi
}

function check_min_len {
    typeset -n _r=$1; shift
    typeset -i min=$1
    if (( ${#_r.value} < min )); then
        _r.err "too short (min $min)" 1
    fi
}

function always_fail_bo {
    typeset -n _r=$1
    _r.err "always fails" 1
}

function crash_silent_bo {
    typeset -n _r=$1
    return 7
}

function transform_upper {
    typeset -n _r=$1
    _r.ok "${_r.value^^}"
}

# --- all validators pass ---
Result_t b1
b1.ok "hello"
both b1 check_nonempty check_lowercase
assert_eq "both all pass status" "${b1.status}" "ok"
assert_eq "both all pass value" "${b1.value}" "hello"

# --- one validator fails ---
Result_t b2
b2.ok "Hello"
both b2 check_nonempty check_lowercase
assert_eq "both one fail status" "${b2.status}" "err"
assert_eq "both one fail code" "${b2.code}" "1"
assert_match "both one fail error" "${b2.error}" "*not all lowercase*"

# --- multiple validators fail ---
Result_t b3
b3.ok ""
both b3 check_nonempty check_lowercase always_fail_bo
assert_eq "both multi fail status" "${b3.status}" "err"
assert_eq "both multi fail code" "${b3.code}" "2"
assert_match "both multi fail has empty" "${b3.error}" "*value is empty*"
assert_match "both multi fail has always" "${b3.error}" "*always fails*"

# --- value preserved on success ---
Result_t b4
b4.ok "original"
both b4 check_nonempty check_lowercase
assert_eq "both preserves value" "${b4.value}" "original"

# --- skip on err ---
Result_t b5
b5.err "pre-existing error" 42
both b5 always_fail_bo
assert_eq "both skip on err status" "${b5.status}" "err"
assert_eq "both skip on err msg" "${b5.error}" "pre-existing error"
assert_eq "both skip on err code" "${b5.code}" "42"

# --- silent crash detection ---
Result_t b6
b6.ok "input"
both b6 crash_silent_bo
assert_eq "both crash detect status" "${b6.status}" "err"
assert_match "both crash detect msg" "${b6.error}" "*both:*crash_silent_bo*exited*7*"

# --- delimiter mode with per-fn args ---
Result_t b7
b7.ok "hello"
both b7 check_min_len 3 -- check_nonempty -- check_lowercase
assert_eq "both delim all pass" "${b7.status}" "ok"
assert_eq "both delim value" "${b7.value}" "hello"

Result_t b7f
b7f.ok "hi"
both b7f check_min_len 5 -- check_nonempty
assert_eq "both delim fail status" "${b7f.status}" "err"
assert_match "both delim fail msg" "${b7f.error}" "*too short*"

# --- too few arguments ---
Result_t b8
both b8
assert_eq "both too few args" "${b8.status}" "err"
assert_match "both too few msg" "${b8.error}" "*both: requires*"

# --- value with spaces ---
Result_t b9
b9.ok "hello world"
both b9 check_nonempty check_lowercase
assert_eq "both spaces status" "${b9.status}" "ok"
assert_eq "both spaces value" "${b9.value}" "hello world"

# --- in pipeline: chain -> both -> chain ---
Result_t b10
b10.ok "hello"
chain b10 transform_upper
# now value is "HELLO", check_lowercase will fail
both b10 check_nonempty check_lowercase
assert_eq "both in pipeline status" "${b10.status}" "err"
assert_match "both in pipeline msg" "${b10.error}" "*not all lowercase*"

# --- single function (degenerate case) ---
Result_t b11
b11.ok "test"
both b11 check_nonempty
assert_eq "both single fn status" "${b11.status}" "ok"
assert_eq "both single fn value" "${b11.value}" "test"

# --- compose with wrap_err ---
Result_t b12
b12.ok "Hello"
both b12 check_nonempty check_lowercase
wrap_err b12 "validating input"
assert_eq "both+wrap_err" "${b12.error}" "validating input: not all lowercase"

print "both: ${pass} passed, ${fail} failed"
(( fail == 0 ))
