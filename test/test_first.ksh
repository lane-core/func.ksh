#!/usr/bin/env ksh
. "${0%/*}/../init.ksh"
. "${0%/*}/helpers.ksh"

# --- Test helpers ---
function parse_as_int {
    typeset -n _r=$1
    typeset val=${_r.value}
    if [[ $val == +([0-9]) ]]; then
        _r.ok "int:$val"
    else
        _r.err "not an integer" 1
    fi
}

function parse_as_float {
    typeset -n _r=$1
    typeset val=${_r.value}
    if [[ $val == +([0-9]).+([0-9]) ]]; then
        _r.ok "float:$val"
    else
        _r.err "not a float" 1
    fi
}

function parse_as_word {
    typeset -n _r=$1
    typeset val=${_r.value}
    if [[ $val == +([a-zA-Z]) ]]; then
        _r.ok "word:$val"
    else
        _r.err "not a word" 1
    fi
}

function always_fail_fi {
    typeset -n _r=$1
    _r.err "always fails" 1
}

function crash_silent_fi {
    typeset -n _r=$1
    return 7
}

typeset -i _fi_call_count=0
function counting_fn {
    typeset -n _r=$1
    (( _fi_call_count++ ))
    _r.ok "counted"
}

function add_prefix {
    typeset -n _r=$1; shift
    typeset pfx=$1
    _r.ok "${pfx}:${_r.value}"
}

# --- first alternative succeeds ---
Result_t f1
f1.ok "42"
first f1 parse_as_int parse_as_float parse_as_word
assert_eq "first 1st wins status" "${f1.status}" "ok"
assert_eq "first 1st wins value" "${f1.value}" "int:42"

# --- second alternative succeeds ---
Result_t f2
f2.ok "3.14"
first f2 parse_as_int parse_as_float parse_as_word
assert_eq "first 2nd wins status" "${f2.status}" "ok"
assert_eq "first 2nd wins value" "${f2.value}" "float:3.14"

# --- third alternative succeeds ---
Result_t f3
f3.ok "hello"
first f3 parse_as_int parse_as_float parse_as_word
assert_eq "first 3rd wins status" "${f3.status}" "ok"
assert_eq "first 3rd wins value" "${f3.value}" "word:hello"

# --- all alternatives fail ---
Result_t f4
f4.ok "!@#"
first f4 parse_as_int parse_as_float parse_as_word
assert_eq "first all fail status" "${f4.status}" "err"
assert_eq "first all fail code" "${f4.code}" "3"
assert_match "first all fail has int" "${f4.error}" "*not an integer*"
assert_match "first all fail has float" "${f4.error}" "*not a float*"
assert_match "first all fail has word" "${f4.error}" "*not a word*"

# --- first success wins, short-circuits ---
_fi_call_count=0
Result_t f5
f5.ok "test"
first f5 counting_fn always_fail_fi
assert_eq "first short-circuits value" "${f5.value}" "counted"
assert_eq "first short-circuits count" "$_fi_call_count" "1"

# --- output is the successful fn's transformation ---
Result_t f6
f6.ok "42"
first f6 parse_as_float parse_as_int
assert_eq "first adopts value" "${f6.value}" "int:42"

# --- skip on err ---
Result_t f7
f7.err "pre-existing error" 42
first f7 parse_as_int
assert_eq "first skip on err status" "${f7.status}" "err"
assert_eq "first skip on err msg" "${f7.error}" "pre-existing error"
assert_eq "first skip on err code" "${f7.code}" "42"

# --- silent crash detection ---
Result_t f8
f8.ok "input"
first f8 crash_silent_fi
assert_eq "first crash detect status" "${f8.status}" "err"
assert_match "first crash detect msg" "${f8.error}" "*first:*crash_silent_fi*exited*7*"

# --- delimiter mode with per-fn args ---
Result_t f9
f9.ok "data"
first f9 add_prefix "json" -- add_prefix "yaml"
assert_eq "first delim status" "${f9.status}" "ok"
assert_eq "first delim value" "${f9.value}" "json:data"

# --- too few arguments ---
Result_t f10
first f10
assert_eq "first too few args" "${f10.status}" "err"
assert_match "first too few msg" "${f10.error}" "*first: requires*"

# --- contrast with chain+or_else ---
# or_else passes the ERROR to the recovery fn; first passes the ORIGINAL VALUE
function recover_from_err {
    typeset -n _r=$1
    # or_else: _r.value is empty (err state), _r.error has the message
    _r.ok "recovered:${_r.error}"
}
Result_t fc1
fc1.ok "original"
chain fc1 always_fail_fi
or_else fc1 recover_from_err
assert_eq "or_else gets error" "${fc1.value}" "recovered:always fails"

Result_t fc2
fc2.ok "original"
first fc2 always_fail_fi parse_as_word
assert_eq "first gets original" "${fc2.value}" "word:original"

# --- compose: first -> chain ---
Result_t f11
f11.ok "42"
first f11 parse_as_float parse_as_int
function double_num {
    typeset -n _r=$1
    _r.ok "${_r.value}+${_r.value}"
}
chain f11 double_num
assert_eq "first then chain" "${f11.value}" "int:42+int:42"

# --- value with spaces ---
Result_t f12
f12.ok "hello world"
first f12 parse_as_int parse_as_word always_fail_fi
assert_eq "first spaces all fail" "${f12.status}" "err"

function accept_anything {
    typeset -n _r=$1
    _r.ok "accepted: ${_r.value}"
}
Result_t f13
f13.ok "hello world"
first f13 parse_as_int accept_anything
assert_eq "first spaces wins" "${f13.status}" "ok"
assert_eq "first spaces value" "${f13.value}" "accepted: hello world"

print "first: ${pass} passed, ${fail} failed"
(( fail == 0 ))
