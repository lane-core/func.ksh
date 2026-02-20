#!/usr/bin/env ksh
. "${0%/*}/../init.ksh"
. "${0%/*}/helpers.ksh"

# --- Simple linear chain ---
typeset -A g1=([c]="b" [b]="a" [a]="")
Result_t r1
toposort r1 g1
assert_eq "linear status" "${r1.status}" "ok"
assert_eq "linear order" "${r1.value}" "a b c"

# --- Diamond dependency ---
typeset -A g2=([app]="lib utils" [lib]="core" [utils]="core" [core]="")
Result_t r2
toposort r2 g2
assert_eq "diamond status" "${r2.status}" "ok"
assert_before "diamond: core < lib" "${r2.value}" core lib
assert_before "diamond: core < utils" "${r2.value}" core utils
assert_before "diamond: lib < app" "${r2.value}" lib app
assert_before "diamond: utils < app" "${r2.value}" utils app

# --- No dependencies (all independent) ---
typeset -A g3=([x]="" [y]="" [z]="")
Result_t r3
toposort r3 g3
assert_eq "independent status" "${r3.status}" "ok"
# Order should be alphabetical (deterministic)
assert_eq "independent order" "${r3.value}" "x y z"

# --- Single node ---
typeset -A g4=([only]="")
Result_t r4
toposort r4 g4
assert_eq "single node" "${r4.value}" "only"

# --- Cycle detection ---
typeset -A g5=([a]="b" [b]="c" [c]="a")
Result_t r5
toposort r5 g5
assert_eq "cycle detected" "${r5.status}" "err"
assert_match "cycle message" "${r5.error}" "*cycle*"

# --- Partial cycle (some nodes ok, some in cycle) ---
typeset -A g6=([a]="" [b]="a" [c]="d" [d]="c")
Result_t r6
toposort r6 g6
assert_eq "partial cycle detected" "${r6.status}" "err"
assert_match "partial cycle nodes" "${r6.error}" "*c*d*"

# --- Dependency-only nodes (referenced but not keys) ---
typeset -A g7=([app]="lib" [lib]="implicit_dep")
Result_t r7
toposort r7 g7
assert_eq "implicit dep status" "${r7.status}" "ok"
assert_before "implicit dep order" "${r7.value}" implicit_dep lib

# --- Duplicate dependencies should not cause false cycle ---
typeset -A g8=([app]="lib lib lib" [lib]="")
Result_t r8
toposort r8 g8
assert_eq "dedup deps status" "${r8.status}" "ok"
assert_eq "dedup deps order" "${r8.value}" "lib app"

print "toposort: ${pass} passed, ${fail} failed"
(( fail == 0 ))
