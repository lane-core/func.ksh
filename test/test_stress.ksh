#!/usr/bin/env ksh
# Stress and performance tests for func.ksh
# Tests scaling behavior and correctness under load.
# All Result_t variables live at file scope to stay within ksh93u+m's
# nameref depth limit (1-level for function-scope compound types).

. "${0%/*}/../init.ksh"
. "${0%/*}/helpers.ksh"

typeset -i _bench_ms=0

# Timing helper: wraps a code block via eval. Sets _bench_ms.
function _bench_start { typeset -g _bench_t0; _bench_t0=$SECONDS; }
function _bench_end {
	typeset _t1=$SECONDS
	if command -v bc >/dev/null 2>&1; then
		_bench_ms=$(print "scale=0; ($_t1 - $_bench_t0) * 1000 / 1" | bc)
	else
		_bench_ms=$(( ${_t1%%.*} - ${_bench_t0%%.*} ))
		(( _bench_ms *= 1000 ))
	fi
}

function _bench_report {
	typeset label="$1"
	typeset -i count=$2
	if (( _bench_ms > 0 )); then
		typeset -i ops_sec=$(( count * 1000 / _bench_ms ))
		print -r -- "  ${label}: ${count} ops in ${_bench_ms}ms (~${ops_sec} ops/sec)"
	else
		print -r -- "  ${label}: ${count} ops in <1ms"
	fi
}

# ── Helpers ───────────────────────────────────────────────────────────────
function _increment {
	typeset -n _r=$1
	typeset -i n=${_r.value}
	_r.ok "$(( n + 1 ))"
}

function _always_err {
	typeset -n _r=$1
	_r.err "stop" 1
}

function _sometimes_fail {
	typeset -n _r=$1
	typeset -i n=${_r.value}
	if (( n % 3 == 0 )); then
		_r.err "fail-${n}" 1
	else
		_r.ok "pass-${n}"
	fi
}

function _validate_item {
	typeset -n _r=$1
	typeset val="${_r.value}"
	if [[ "$val" == bad_* ]]; then
		_r.err "invalid: $val" 1
	fi
}

function _always_fail_numbered {
	typeset -n _r=$1
	_r.err "error-${_r.value}" 1
}

function _validate_and_transform {
	typeset -n _r=$1
	typeset -i val=${_r.value}
	if (( val < 0 )); then
		_r.err "negative: $val" 1
		return 0
	fi
	_r.ok "$(( val * 2 ))"
}

function _check_positive {
	typeset -n _r=$1
	typeset -i n=${_r.value}
	(( n > 0 )) || _r.err "$n is not positive" 1
}

# ══════════════════════════════════════════════════════════════════════════
# 1. Result_t creation throughput
# ══════════════════════════════════════════════════════════════════════════
print -r -- "-- Result_t creation --"
_bench_start
typeset -i _ri
for (( _ri=0; _ri < 1000; _ri++ )); do
	Result_t "_sr_${_ri}"
done
_bench_end
_bench_report "create 1000 Result_t" 1000

Result_t _src_a; _src_a.ok "hello"
assert_eq "result create ok" "${_src_a.value}" "hello"
Result_t _src_b; _src_b.err "boom" 42
assert_eq "result create err" "${_src_b.error}" "boom"
assert_eq "result create code" "${_src_b.code}" "42"

# ══════════════════════════════════════════════════════════════════════════
# 2. Chain — deep pipeline (500 steps)
# ══════════════════════════════════════════════════════════════════════════
print -r -- "-- chain deep pipeline --"
Result_t _scd
_scd.ok "0"
_bench_start
for (( _ri=0; _ri < 500; _ri++ )); do
	chain _scd _increment
done
_bench_end
_bench_report "chain 500 steps" 500
assert_eq "chain 500 steps result" "${_scd.value}" "500"

# ══════════════════════════════════════════════════════════════════════════
# 3. Chain — short-circuit efficiency
# ══════════════════════════════════════════════════════════════════════════
print -r -- "-- chain short-circuit --"
Result_t _scs
_scs.ok "start"
chain _scs _always_err
_bench_start
for (( _ri=0; _ri < 1000; _ri++ )); do
	chain _scs _increment
done
_bench_end
_bench_report "chain 1000 skipped" 1000
assert_eq "chain shortcircuit stays err" "${_scs.status}" "err"

# ══════════════════════════════════════════════════════════════════════════
# 4. Gather — large batch (300 items, 100 failures)
# ══════════════════════════════════════════════════════════════════════════
print -r -- "-- gather batch --"
Result_t _sgb
_bench_start
for (( _ri=0; _ri < 300; _ri++ )); do
	gather _sgb _sometimes_fail "$_ri"
done
_bench_end
_bench_report "gather 300 items" 300
assert_eq "gather 300 error count" "${_sgb.code}" "100"

# ══════════════════════════════════════════════════════════════════════════
# 5. Collect — batch wrapper (200 items, 40 failures)
# ══════════════════════════════════════════════════════════════════════════
print -r -- "-- collect batch --"
Result_t _scb
typeset -a _cb_items=()
for (( _ri=0; _ri < 200; _ri++ )); do
	if (( _ri % 5 == 0 )); then
		_cb_items+=("bad_${_ri}")
	else
		_cb_items+=("ok_${_ri}")
	fi
done
_bench_start
collect _scb _validate_item "${_cb_items[@]}"
_bench_end
_bench_report "collect 200 items" 200
assert_eq "collect 200 error count" "${_scb.code}" "40"

# ══════════════════════════════════════════════════════════════════════════
# 6. try_cmd — throughput
# ══════════════════════════════════════════════════════════════════════════
print -r -- "-- try_cmd throughput --"
Result_t _stcmd
_bench_start
for (( _ri=0; _ri < 200; _ri++ )); do
	try_cmd _stcmd print "iteration $_ri"
done
_bench_end
_bench_report "try_cmd 200" 200
assert_eq "try_cmd all ok" "${_stcmd.status}" "ok"

# try_cmd with failure
Result_t _stcf
try_cmd _stcf false
assert_eq "try_cmd captures failure" "${_stcf.status}" "err"
assert_eq "try_cmd failure code" "${_stcf.code}" "1"

# ══════════════════════════════════════════════════════════════════════════
# 11. Sequence — 100 functions
# ══════════════════════════════════════════════════════════════════════════
print -r -- "-- sequence 100 --"
Result_t _ss
_ss.ok "0"
typeset -a _ss_fns=()
for (( _ri=0; _ri < 100; _ri++ )); do
	_ss_fns+=(_increment)
done
_bench_start
sequence _ss "${_ss_fns[@]}"
_bench_end
_bench_report "sequence 100 fns" 100
assert_eq "sequence 100 result" "${_ss.value}" "100"

# ══════════════════════════════════════════════════════════════════════════
# 12. Gather — error message scaling (100 accumulated errors)
# ══════════════════════════════════════════════════════════════════════════
print -r -- "-- gather error accumulation --"
Result_t _sge
_bench_start
for (( _ri=0; _ri < 100; _ri++ )); do
	gather _sge _always_fail_numbered "$_ri"
done
_bench_end
_bench_report "gather 100 errors" 100
assert_eq "gather 100 error code" "${_sge.code}" "100"
# Verify all error messages present (count newline-separated lines)
typeset -i _err_count=0
typeset _err_IFS=$IFS
IFS=$'\n'
typeset _el
for _el in ${_sge.error}; do
	(( _err_count++ ))
done
IFS=$_err_IFS
assert_eq "gather 100 errors preserved" "$_err_count" "100"

# ══════════════════════════════════════════════════════════════════════════
# 13. Mixed: chain-inside-gather (100 items, 10 negative)
# ══════════════════════════════════════════════════════════════════════════
print -r -- "-- mixed chain+gather --"
Result_t _smp
_bench_start
for (( _ri = -10; _ri < 90; _ri++ )); do
	gather _smp _validate_and_transform "$_ri"
done
_bench_end
_bench_report "mixed 100 items" 100
assert_eq "mixed 10 failures" "${_smp.code}" "10"

# ══════════════════════════════════════════════════════════════════════════
# 14. Composable collect — two passes on same accumulator
# ══════════════════════════════════════════════════════════════════════════
print -r -- "-- composable collect --"
Result_t _scc
typeset -a _cc_b1=()
for (( _ri=1; _ri <= 50; _ri++ )); do _cc_b1+=("$_ri"); done
collect _scc _check_positive "${_cc_b1[@]}"

typeset -a _cc_b2=()
for (( _ri=-5; _ri <= 5; _ri++ )); do _cc_b2+=("$_ri"); done
collect _scc _check_positive "${_cc_b2[@]}"
# 6 failures: -5,-4,-3,-2,-1,0
assert_eq "composable collect 6 fails" "${_scc.code}" "6"

# ══════════════════════════════════════════════════════════════════════════
# 15. Large gather stress — 1000 items
# ══════════════════════════════════════════════════════════════════════════
print -r -- "-- gather 1000 items --"
Result_t _sg1k
_bench_start
for (( _ri=0; _ri < 1000; _ri++ )); do
	gather _sg1k _sometimes_fail "$_ri"
done
_bench_end
_bench_report "gather 1000 items" 1000
# n % 3 == 0 for 0..999: ceil(1000/3) = 334 failures
assert_eq "gather 1000 error count" "${_sg1k.code}" "334"

# ══════════════════════════════════════════════════════════════════════════
# 16. Chain deep — 1000 steps
# ══════════════════════════════════════════════════════════════════════════
print -r -- "-- chain 1000 deep --"
Result_t _scd2
_scd2.ok "0"
_bench_start
for (( _ri=0; _ri < 1000; _ri++ )); do
	chain _scd2 _increment
done
_bench_end
_bench_report "chain 1000 steps" 1000
assert_eq "chain 1000 steps result" "${_scd2.value}" "1000"

print ""
print "stress: ${pass} passed, ${fail} failed"
(( fail == 0 ))
