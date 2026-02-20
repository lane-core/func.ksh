#!/usr/bin/env ksh
. "${0%/*}/../init.ksh"
. "${0%/*}/helpers.ksh"

# --- Construction ---
Result_t r1
assert_eq "default status is ok" "${r1.status}" "ok"

# --- .ok method ---
r1.ok "hello"
assert_eq "ok sets value" "${r1.value}" "hello"
assert_eq "ok sets status" "${r1.status}" "ok"
assert_eq "ok clears error" "${r1.error}" ""
assert_true "is_ok returns true" r1.is_ok

# --- .err method ---
r1.err "broke" 42
assert_eq "err sets status" "${r1.status}" "err"
assert_eq "err sets message" "${r1.error}" "broke"
assert_eq "err sets code" "${r1.code}" "42"
assert_eq "err origin empty without arg" "${r1.origin}" ""
assert_eq "err clears value" "${r1.value}" ""
assert_true "is_err returns true" r1.is_err

# --- .err with explicit origin ---
r1.err "located" 1 "myfile.ksh:42"
assert_eq "err origin from caller" "${r1.origin}" "myfile.ksh:42"

# --- Discipline rejects bad status ---
r1.status=ok
r1.status=bogus 2>/dev/null
assert_eq "rejects bogus status" "${r1.status}" "ok"

# --- Through nameref ---
function use_ref {
    typeset -n _r=$1
    _r.ok "from ref"
}
Result_t r2
use_ref r2
assert_eq "nameref ok works" "${r2.value}" "from ref"
assert_eq "nameref status ok" "${r2.status}" "ok"

function err_ref {
    typeset -n _r=$1
    _r.err "ref error" 7
}
err_ref r2
assert_eq "nameref err works" "${r2.error}" "ref error"
assert_eq "nameref err code" "${r2.code}" "7"

# --- .value_or ---
Result_t r3
r3.ok "real value"
assert_eq "value_or on ok" "$(r3.value_or fallback)" "real value"
r3.err "broken"
assert_eq "value_or on err" "$(r3.value_or fallback)" "fallback"

# --- .expect ---
Result_t r4
r4.ok "expected value"
assert_eq "expect on ok" "$(r4.expect 'should work')" "expected value"
r4.err "broken"
typeset expect_out
expect_out=$(r4.expect "critical op" 2>/dev/null) && true
assert_eq "expect on err fails" "$?" "1"

# --- .reset ---
Result_t r5
r5.err "some error" 42 "origin.ksh:1"
r5.reset
assert_eq "reset status" "${r5.status}" "ok"
assert_eq "reset value" "${r5.value}" ""
assert_eq "reset error" "${r5.error}" ""
assert_eq "reset code" "${r5.code}" "0"
assert_eq "reset origin" "${r5.origin}" ""

print "Result_t: ${pass} passed, ${fail} failed"
(( fail == 0 ))
