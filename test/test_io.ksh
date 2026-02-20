#!/usr/bin/env ksh
. "${0%/*}/../init.ksh"
. "${0%/*}/helpers.ksh"

# Setup test directory
typeset testdir
testdir=$(mktemp -d)

# --- safe_tmpfile ---
Result_t r1
safe_tmpfile r1 "$testdir"
assert_eq "tmpfile status" "${r1.status}" "ok"
assert_match "tmpfile path" "${r1.value}" "${testdir}/tmp.*"

# --- safe_write ---
Result_t r2
safe_write r2 "${testdir}/hello.txt" "hello world"
assert_eq "write status" "${r2.status}" "ok"

# --- safe_read ---
Result_t r3
safe_read r3 "${testdir}/hello.txt"
assert_eq "read status" "${r3.status}" "ok"
assert_eq "read contents" "${r3.value}" "hello world"

# --- round-trip ---
Result_t r4
safe_write r4 "${testdir}/round.txt" "round trip data"
Result_t r5
safe_read r5 "${testdir}/round.txt"
assert_eq "round-trip" "${r5.value}" "round trip data"

# --- safe_write append ---
Result_t r6
safe_write r6 "${testdir}/append.txt" "line1"
Result_t r7
safe_write -a r7 "${testdir}/append.txt" "line2"
Result_t r8
safe_read r8 "${testdir}/append.txt"
assert_match "append result" "${r8.value}" "line1*line2"

# --- safe_read errors ---
Result_t r9
safe_read r9 "${testdir}/nonexistent"
assert_eq "read missing file" "${r9.status}" "err"
assert_match "read missing msg" "${r9.error}" "*no such file*"

Result_t r10
safe_read r10 "$testdir"
assert_eq "read directory" "${r10.status}" "err"
assert_match "read dir msg" "${r10.error}" "*not a regular file*"

# --- safe_write error: bad directory ---
Result_t r11
safe_write r11 "${testdir}/nonexistent_dir/file.txt" "data"
assert_eq "write bad dir" "${r11.status}" "err"

# --- safe_write atomicity: target should have content or not exist ---
Result_t r12
safe_write r12 "${testdir}/atomic.txt" "complete data"
assert_eq "atomic write" "${r12.status}" "ok"
Result_t r13
safe_read r13 "${testdir}/atomic.txt"
assert_eq "atomic read back" "${r13.value}" "complete data"

# --- safe_write preserves permissions (portable chmod fix) ---
Result_t r14
safe_write r14 "${testdir}/perms.txt" "initial"
chmod 755 "${testdir}/perms.txt"
Result_t r15
safe_write r15 "${testdir}/perms.txt" "updated"
typeset perms
perms=$(stat -f '%OLp' "${testdir}/perms.txt" 2>/dev/null) ||
    perms=$(stat -c '%a' "${testdir}/perms.txt" 2>/dev/null) || true
assert_eq "write preserves perms" "$perms" "755"

# --- safe_write: bare filename (no directory prefix) ---
typeset _save_pwd=$PWD
cd "$testdir"
Result_t r_bare
safe_write r_bare "bare.txt" "bare file content"
assert_eq "write bare filename" "${r_bare.status}" "ok"
Result_t r_bare2
safe_read r_bare2 "${testdir}/bare.txt"
assert_eq "read bare filename" "${r_bare2.value}" "bare file content"
cd "$_save_pwd"

# ---- Chain-mode IO ----

# --- safe_read via chain: path from .value ---
Result_t rc1
rc1.ok "${testdir}/hello.txt"
chain rc1 safe_read
assert_eq "chain safe_read status" "${rc1.status}" "ok"
assert_eq "chain safe_read value" "${rc1.value}" "hello world"

# --- safe_read via chain: error propagates ---
Result_t rc2
rc2.ok "${testdir}/no_such_file"
chain rc2 safe_read
assert_eq "chain safe_read err" "${rc2.status}" "err"
assert_match "chain safe_read err msg" "${rc2.error}" "*no such file*"

# --- safe_write via chain: content from .value ---
Result_t rc3
rc3.ok "chain-written content"
chain rc3 safe_write "${testdir}/chain_write.txt"
assert_eq "chain safe_write status" "${rc3.status}" "ok"
Result_t rc3_verify
safe_read rc3_verify "${testdir}/chain_write.txt"
assert_eq "chain safe_write verify" "${rc3_verify.value}" "chain-written content"

# --- safe_write via chain: append mode (flag after result var) ---
Result_t rc4
rc4.ok "appended via chain"
chain rc4 safe_write -a "${testdir}/chain_write.txt"
assert_eq "chain safe_write -a status" "${rc4.status}" "ok"
Result_t rc4_verify
safe_read rc4_verify "${testdir}/chain_write.txt"
assert_match "chain safe_write -a verify" "${rc4_verify.value}" "*chain-written*appended via chain"

# --- safe_read + safe_write full chain pipeline ---
Result_t rc5
safe_write rc5 "${testdir}/pipeline_src.txt" "pipeline data"
Result_t rc6
rc6.ok "${testdir}/pipeline_src.txt"
chain rc6 safe_read
chain rc6 safe_write "${testdir}/pipeline_dst.txt"
assert_eq "chain read→write status" "${rc6.status}" "ok"
Result_t rc6_verify
safe_read rc6_verify "${testdir}/pipeline_dst.txt"
assert_eq "chain read→write verify" "${rc6_verify.value}" "pipeline data"

# --- safe_fetch via chain: URL scheme check with .value ---
Result_t rc7
rc7.ok "ftp://bad.scheme/file"
chain rc7 safe_fetch
assert_eq "chain fetch rejects ftp" "${rc7.status}" "err"

# --- safe_fetch -o via chain: flag after result var ---
Result_t rc8
rc8.ok "ftp://bad.scheme/file"
chain rc8 safe_fetch -o "${testdir}/fetch_out"
assert_eq "chain fetch -o rejects ftp" "${rc8.status}" "err"

# --- safe_fetch: URL scheme validation (no network needed) ---
Result_t r16
safe_fetch r16 "ftp://example.com/file"
assert_eq "fetch rejects ftp scheme" "${r16.status}" "err"
assert_match "fetch scheme msg" "${r16.error}" "*unsupported URL scheme*"

Result_t r17
safe_fetch -o r17 "https://example.com/file"
assert_eq "fetch -o missing path" "${r17.status}" "err"
assert_match "fetch -o msg" "${r17.error}" "*requires output path*"

# Cleanup
rm -rf "$testdir"

print "io: ${pass} passed, ${fail} failed"
(( fail == 0 ))
