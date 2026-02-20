#!/usr/bin/env ksh
. "${0%/*}/../init.ksh"
. "${0%/*}/helpers.ksh"

# ---- SafeStr_t ----
SafeStr_t s1
s1.value="hello world"
assert_eq "safestr accepts normal" "${s1.value}" "hello world"

s1.value="with-dashes_and.dots"
assert_eq "safestr accepts identifiers" "${s1.value}" "with-dashes_and.dots"

SafeStr_t s2
s2.value='safe'
s2.value='$(rm -rf /)' 2>/dev/null
assert_eq "safestr rejects cmd sub" "${s2.value}" "safe"

SafeStr_t s3
s3.value='ok'
s3.value='hello `world`' 2>/dev/null
assert_eq "safestr rejects backtick" "${s3.value}" "ok"

SafeStr_t s4
s4.value='ok'
s4.value=$'bad\x07bell' 2>/dev/null
assert_eq "safestr rejects control" "${s4.value}" "ok"

# ---- SafePath_t ----
SafePath_t p1
p1.value="/usr/local/bin"
assert_eq "safepath accepts absolute" "${p1.value}" "/usr/local/bin"

SafePath_t p2
p2.value="relative/path"
assert_eq "safepath accepts relative" "${p2.value}" "relative/path"

SafePath_t p3
p3.value="/safe"
p3.value="../../../etc/passwd" 2>/dev/null
assert_eq "safepath rejects traversal" "${p3.value}" "/safe"

SafePath_t p4
p4.value="/safe"
p4.value="" 2>/dev/null
assert_eq "safepath rejects empty" "${p4.value}" "/safe"

SafePath_t p5
p5.value="/safe"
p5.value='$(whoami)/file' 2>/dev/null
assert_eq "safepath rejects expansion" "${p5.value}" "/safe"

# test methods on real paths
SafePath_t p6
p6.value="/usr/local/bin"
assert_eq "safepath dirname" "$(p6.dirname)" "/usr/local"
assert_eq "safepath basename" "$(p6.basename)" "bin"

# safepath dirname/basename edge cases (POSIX behavior)
SafePath_t p_bare
p_bare.value="filename"
assert_eq "safepath dirname bare" "$(p_bare.dirname)" "."
assert_eq "safepath basename bare" "$(p_bare.basename)" "filename"

SafePath_t p_trail
p_trail.value="/usr/local/"
assert_eq "safepath dirname trailing slash" "$(p_trail.dirname)" "/usr"
assert_eq "safepath basename trailing slash" "$(p_trail.basename)" "local"

SafePath_t p_root
p_root.value="/"
assert_eq "safepath dirname root" "$(p_root.dirname)" "/"
assert_eq "safepath basename root" "$(p_root.basename)" "/"

# ---- Version_t ----
Version_t v1
v1.raw="1.2.3"
assert_eq "version parses major" "${v1.major}" "1"
assert_eq "version parses minor" "${v1.minor}" "2"
assert_eq "version parses patch" "${v1.patch}" "3"
assert_eq "version display" "${v1}" "1.2.3"

Version_t v2
v2.raw="2.0.0-alpha"
assert_eq "version pre-release" "${v2.pre}" "alpha"
assert_eq "version display pre" "${v2}" "2.0.0-alpha"

# Two-component version
Version_t v3
v3.raw="1.0"
assert_eq "version two-component" "${v3.major}" "1"
assert_eq "version two-comp patch" "${v3.patch}" "0"

# Reject bad versions
Version_t v4
v4.raw="1.0.0"
v4.raw="not.a.version" 2>/dev/null
assert_eq "version rejects bad" "${v4.raw}" "1.0.0"

# Comparison
Version_t va vb
va.raw="1.2.3"
vb.raw="1.2.4"
assert_eq "version cmp less" "$(va.cmp vb)" "-1"

vb.raw="1.2.3"
assert_eq "version cmp equal" "$(va.cmp vb)" "0"

vb.raw="1.2.2"
assert_eq "version cmp greater" "$(va.cmp vb)" "1"

# Pre-release sorts before release
va.raw="1.0.0-alpha"
vb.raw="1.0.0"
assert_eq "version pre < release" "$(va.cmp vb)" "-1"

# ---- SafeStr_t: $[ rejected ----
SafeStr_t s5
s5.value='ok'
s5.value='$[1+1]' 2>/dev/null
assert_eq "safestr rejects bracket exp" "${s5.value}" "ok"

# ---- SafePath_t: ./.. traversal bypass (issue #5) ----
SafePath_t p7
p7.value="/safe"
p7.value="./.." 2>/dev/null
assert_eq "safepath rejects dot-slash-dotdot" "${p7.value}" "/safe"

SafePath_t p8
p8.value="/safe"
p8.value="foo/./../../etc" 2>/dev/null
assert_eq "safepath rejects embedded dotdot" "${p8.value}" "/safe"

# ---- Version_t: semver pre-release ordering ----
# Numeric identifiers sort numerically (1 < 2 < 10)
Version_t vc vd
vc.raw="1.0.0-alpha.1"
vd.raw="1.0.0-alpha.10"
assert_eq "version pre numeric sort" "$(vc.cmp vd)" "-1"

# Numeric < alphanumeric per semver
vc.raw="1.0.0-1"
vd.raw="1.0.0-alpha"
assert_eq "version numeric < alpha" "$(vc.cmp vd)" "-1"

# Shorter pre-release < longer when common prefix is equal
vc.raw="1.0.0-alpha"
vd.raw="1.0.0-alpha.1"
assert_eq "version shorter pre < longer" "$(vc.cmp vd)" "-1"

# Equal pre-releases
vc.raw="1.0.0-rc.1"
vd.raw="1.0.0-rc.1"
assert_eq "version pre equal" "$(vc.cmp vd)" "0"

# ---- SafeStr_t: carriage return rejected ----
SafeStr_t s6
s6.value='ok'
s6.value=$'sneaky\x0doverwrite' 2>/dev/null
assert_eq "safestr rejects CR" "${s6.value}" "ok"

# ---- SafeStr_t: escape character rejected ----
SafeStr_t s7
s7.value='ok'
s7.value=$'ansi\x1b[31mred' 2>/dev/null
assert_eq "safestr rejects ESC" "${s7.value}" "ok"

# ---- SafeStr_t: tab and newline are allowed ----
SafeStr_t s8
s8.value=$'tab\there\nnewline'
assert_eq "safestr allows tab+newline" "${s8.value}" $'tab\there\nnewline'

print "types: ${pass} passed, ${fail} failed"
(( fail == 0 ))
