#!/usr/bin/env ksh
. "${0%/*}/../init.ksh"
. "${0%/*}/helpers.ksh"

# =============================================================================
# State management
# =============================================================================

typeset -C s1
parse_init s1 "hello"
assert_eq "init input" "${s1.input}" "hello"
assert_eq "init pos" "${s1.pos}" "0"
assert_eq "init len" "${s1.len}" "5"

# =============================================================================
# Primitives
# =============================================================================

Result_t rp1; typeset -C sp1; parse_init sp1 "abc"
p_return rp1 sp1 "yes"
assert_eq "p_return ok" "${rp1.value}" "yes"
assert_eq "p_return pos unchanged" "${sp1.pos}" "0"

Result_t rp2; typeset -C sp2; parse_init sp2 "abc"
p_fail rp2 sp2 "nope"
assert_eq "p_fail err" "${rp2.status}" "err"
assert_eq "p_fail message" "${rp2.error}" "nope"

Result_t rp3; typeset -C sp3; parse_init sp3 "xy"
p_item rp3 sp3
assert_eq "p_item first" "${rp3.value}" "x"
assert_eq "p_item pos" "${sp3.pos}" "1"
rp3.reset
p_item rp3 sp3
assert_eq "p_item second" "${rp3.value}" "y"
rp3.reset
p_item rp3 sp3
assert_eq "p_item eof" "${rp3.status}" "err"

Result_t rp4; typeset -C sp4; parse_init sp4 "a"
p_eof rp4 sp4
assert_eq "p_eof not at end" "${rp4.status}" "err"
sp4.pos=1
rp4.reset
p_eof rp4 sp4
assert_eq "p_eof at end" "${rp4.status}" "ok"

# =============================================================================
# Character parsers
# =============================================================================

Result_t rc1; typeset -C sc1; parse_init sc1 "a"
p_char rc1 sc1 "a"
assert_eq "p_char match" "${rc1.value}" "a"
assert_eq "p_char advances" "${sc1.pos}" "1"

Result_t rc2; typeset -C sc2; parse_init sc2 "b"
p_char rc2 sc2 "a"
assert_eq "p_char mismatch" "${rc2.status}" "err"
assert_eq "p_char no advance" "${sc2.pos}" "0"

Result_t rc3; typeset -C sc3; parse_init sc3 "hello world"
p_string rc3 sc3 "hello"
assert_eq "p_string match" "${rc3.value}" "hello"
assert_eq "p_string pos" "${sc3.pos}" "5"

Result_t rc4; typeset -C sc4; parse_init sc4 "help"
p_string rc4 sc4 "hello"
assert_eq "p_string mismatch" "${rc4.status}" "err"

Result_t rc5; typeset -C sc5; parse_init sc5 "5"
p_digit rc5 sc5
assert_eq "p_digit match" "${rc5.value}" "5"

Result_t rc6; typeset -C sc6; parse_init sc6 "a"
p_digit rc6 sc6
assert_eq "p_digit mismatch" "${rc6.status}" "err"

Result_t rc7; typeset -C sc7; parse_init sc7 "+"
p_one_of rc7 sc7 "+-*/"
assert_eq "p_one_of match" "${rc7.value}" "+"

Result_t rc8; typeset -C sc8; parse_init sc8 "x"
p_one_of rc8 sc8 "+-*/"
assert_eq "p_one_of mismatch" "${rc8.status}" "err"

Result_t rc9; typeset -C sc9; parse_init sc9 "x"
p_none_of rc9 sc9 "+-*/"
assert_eq "p_none_of match" "${rc9.value}" "x"

Result_t rc10; typeset -C sc10; parse_init sc10 "+"
p_none_of rc10 sc10 "+-*/"
assert_eq "p_none_of mismatch" "${rc10.status}" "err"

# =============================================================================
# Monadic bind
# =============================================================================

# Parse a digit, then use it to decide the next parser
function _test_bind_cont {
    typeset -n _r=$1 _s=$2
    typeset _digit=$3
    if [[ $_digit == "1" ]]; then
        p_string "$1" "$2" "st"
    else
        p_string "$1" "$2" "nd"
    fi
}

Result_t rb1; typeset -C sb1; parse_init sb1 "1st"
p_bind rb1 sb1 p_digit _test_bind_cont
assert_eq "p_bind value" "${rb1.value}" "st"
assert_eq "p_bind pos" "${sb1.pos}" "3"

Result_t rb2; typeset -C sb2; parse_init sb2 "2nd"
p_bind rb2 sb2 p_digit _test_bind_cont
assert_eq "p_bind alt path" "${rb2.value}" "nd"

# =============================================================================
# Sequencing
# =============================================================================

function _p_comma { p_char "$1" "$2" ","; }

Result_t rs1; typeset -C ss1; parse_init ss1 ",x"
p_then rs1 ss1 _p_comma p_alpha
assert_eq "p_then keeps right" "${rs1.value}" "x"
assert_eq "p_then pos" "${ss1.pos}" "2"

Result_t rs2; typeset -C ss2; parse_init ss2 "x,"
p_left rs2 ss2 p_alpha _p_comma
assert_eq "p_left keeps left" "${rs2.value}" "x"
assert_eq "p_left pos" "${ss2.pos}" "2"

Result_t rs3; typeset -C ss3; parse_init ss3 "!x"
p_then rs3 ss3 _p_comma p_alpha
assert_eq "p_then fails on p1" "${rs3.status}" "err"
assert_eq "p_then no advance on fail" "${ss3.pos}" "0"

# =============================================================================
# Choice with backtracking
# =============================================================================

function _p_hello { p_string "$1" "$2" "hello"; }
function _p_help { p_string "$1" "$2" "help"; }
function _p_world { p_string "$1" "$2" "world"; }

Result_t ro1; typeset -C so1; parse_init so1 "help me"
p_or ro1 so1 _p_hello _p_help
assert_eq "p_or second wins" "${ro1.value}" "help"
assert_eq "p_or backtrack works" "${so1.pos}" "4"

Result_t ro2; typeset -C so2; parse_init so2 "hello there"
p_or ro2 so2 _p_hello _p_help
assert_eq "p_or first wins" "${ro2.value}" "hello"

Result_t ro3; typeset -C so3; parse_init so3 "world"
p_choice ro3 so3 _p_hello _p_help _p_world
assert_eq "p_choice third" "${ro3.value}" "world"
assert_eq "p_choice pos" "${so3.pos}" "5"

Result_t ro4; typeset -C so4; parse_init so4 "xyz"
p_choice ro4 so4 _p_hello _p_help _p_world
assert_eq "p_choice all fail" "${ro4.status}" "err"

# =============================================================================
# Repetition
# =============================================================================

Result_t rm1; typeset -C sm1; parse_init sm1 "12345abc"
p_many rm1 sm1 p_digit
assert_eq "p_many digits" "${rm1.value}" "12345"
assert_eq "p_many stops" "${sm1.pos}" "5"

Result_t rm2; typeset -C sm2; parse_init sm2 "abc"
p_many rm2 sm2 p_digit
assert_eq "p_many zero matches" "${rm2.status}" "ok"
assert_eq "p_many zero value" "${rm2.value}" ""
assert_eq "p_many zero pos" "${sm2.pos}" "0"

Result_t rm3; typeset -C sm3; parse_init sm3 "123"
p_many1 rm3 sm3 p_digit
assert_eq "p_many1 ok" "${rm3.value}" "123"

Result_t rm4; typeset -C sm4; parse_init sm4 "abc"
p_many1 rm4 sm4 p_digit
assert_eq "p_many1 zero fails" "${rm4.status}" "err"

Result_t rm5; typeset -C sm5; parse_init sm5 "   x"
p_skip_many rm5 sm5 p_space
assert_eq "p_skip_many" "${sm5.pos}" "3"
assert_eq "p_skip_many value empty" "${rm5.value}" ""

# =============================================================================
# Structural
# =============================================================================

function _p_lparen { p_char "$1" "$2" "("; }
function _p_rparen { p_char "$1" "$2" ")"; }

Result_t rb3; typeset -C sb3; parse_init sb3 "(42)"
function _p_digits { p_many1 "$1" "$2" p_digit; }
p_between rb3 sb3 _p_lparen _p_rparen _p_digits
assert_eq "p_between value" "${rb3.value}" "42"
assert_eq "p_between pos" "${sb3.pos}" "4"

# sep_by
function _p_comma2 { p_char "$1" "$2" ","; }
function _p_word { p_many1 "$1" "$2" p_alpha; }

Result_t rse1; typeset -C sse1; parse_init sse1 "a,bb,ccc"
p_sep_by rse1 sse1 _p_word _p_comma2
assert_eq "p_sep_by value" "${rse1.value}" $'a\nbb\nccc'

Result_t rse2; typeset -C sse2; parse_init sse2 ""
p_sep_by rse2 sse2 _p_word _p_comma2
assert_eq "p_sep_by empty" "${rse2.value}" ""
assert_eq "p_sep_by empty ok" "${rse2.status}" "ok"

Result_t rse3; typeset -C sse3; parse_init sse3 "a,bb"
p_sep_by1 rse3 sse3 _p_word _p_comma2
assert_eq "p_sep_by1 value" "${rse3.value}" $'a\nbb'

Result_t rse4; typeset -C sse4; parse_init sse4 ""
p_sep_by1 rse4 sse4 _p_word _p_comma2
assert_eq "p_sep_by1 empty fails" "${rse4.status}" "err"

# option
Result_t rop1; typeset -C sop1; parse_init sop1 "+5"
function _p_plus { p_char "$1" "$2" "+"; }
p_option rop1 sop1 _p_plus "none"
assert_eq "p_option match" "${rop1.value}" "+"

Result_t rop2; typeset -C sop2; parse_init sop2 "5"
p_option rop2 sop2 _p_plus "none"
assert_eq "p_option default" "${rop2.value}" "none"
assert_eq "p_option no advance" "${sop2.pos}" "0"

# =============================================================================
# Expression parsing: chainl1
# =============================================================================

function _p_add_op { p_one_of "$1" "$2" "+-"; }
function _p_num { p_many1 "$1" "$2" p_digit; }

Result_t rcl1; typeset -C scl1; parse_init scl1 "1+2-3"
p_chainl1 rcl1 scl1 _p_num _p_add_op
assert_eq "chainl1 expr" "${rcl1.value}" "1 + 2 - 3"
assert_eq "chainl1 pos" "${scl1.pos}" "5"

Result_t rcl2; typeset -C scl2; parse_init scl2 "42"
p_chainl1 rcl2 scl2 _p_num _p_add_op
assert_eq "chainl1 single" "${rcl2.value}" "42"

Result_t rcl3; typeset -C scl3; parse_init scl3 "abc"
p_chainl1 rcl3 scl3 _p_num _p_add_op
assert_eq "chainl1 no operand" "${rcl3.status}" "err"

# chainr1
function _p_pow_op { p_char "$1" "$2" "^"; }

Result_t rcr1; typeset -C scr1; parse_init scr1 "2^3^4"
p_chainr1 rcr1 scr1 _p_num _p_pow_op
assert_eq "chainr1 expr" "${rcr1.value}" "2 ^ 3 ^ 4"

# =============================================================================
# Lexical
# =============================================================================

Result_t rl1; typeset -C sl1; parse_init sl1 $'  \t  x'
p_spaces rl1 sl1
assert_eq "p_spaces skips" "${sl1.pos}" "5"

Result_t rl2; typeset -C sl2; parse_init sl2 "hello   world"
p_symbol rl2 sl2 "hello"
assert_eq "p_symbol value" "${rl2.value}" "hello"
assert_eq "p_symbol skips ws" "${sl2.pos}" "8"

Result_t rl3; typeset -C sl3; parse_init sl3 "42  rest"
p_natural rl3 sl3
assert_eq "p_natural value" "${rl3.value}" "42"
assert_eq "p_natural skips ws" "${sl3.pos}" "4"

Result_t rl4; typeset -C sl4; parse_init sl4 "-7 rest"
p_integer rl4 sl4
assert_eq "p_integer neg" "${rl4.value}" "-7"
assert_eq "p_integer skips ws" "${sl4.pos}" "3"

Result_t rl5; typeset -C sl5; parse_init sl5 "+3"
p_integer rl5 sl5
assert_eq "p_integer pos sign" "${rl5.value}" "+3"

Result_t rl6; typeset -C sl6; parse_init sl6 "99"
p_integer rl6 sl6
assert_eq "p_integer no sign" "${rl6.value}" "99"

Result_t rl7; typeset -C sl7; parse_init sl7 "foo_bar  rest"
p_ident rl7 sl7
assert_eq "p_ident value" "${rl7.value}" "foo_bar"
assert_eq "p_ident skips ws" "${sl7.pos}" "9"

Result_t rl8; typeset -C sl8; parse_init sl8 "_priv"
p_ident rl8 sl8
assert_eq "p_ident underscore" "${rl8.value}" "_priv"

Result_t rl9; typeset -C sl9; parse_init sl9 "42abc"
p_ident rl9 sl9
assert_eq "p_ident digit start" "${rl9.status}" "err"

# p_token wraps any parser
Result_t rl10; typeset -C sl10; parse_init sl10 "abc   rest"
p_token rl10 sl10 _p_word
assert_eq "p_token value" "${rl10.value}" "abc"
assert_eq "p_token skips ws" "${sl10.pos}" "6"

# =============================================================================
# Utility: label, peek, not, map
# =============================================================================

Result_t ru1; typeset -C su1; parse_init su1 "xyz"
p_label ru1 su1 "a digit" p_digit
assert_eq "p_label err" "${ru1.status}" "err"
assert_match "p_label msg" "${ru1.error}" "*expected a digit*"

Result_t ru2; typeset -C su2; parse_init su2 "abc"
p_peek ru2 su2 p_alpha
assert_eq "p_peek ok" "${ru2.value}" "a"
assert_eq "p_peek no consume" "${su2.pos}" "0"

Result_t ru3; typeset -C su3; parse_init su3 "abc"
p_not ru3 su3 p_digit
assert_eq "p_not succeeds" "${ru3.status}" "ok"

Result_t ru4; typeset -C su4; parse_init su4 "5"
p_not ru4 su4 p_digit
assert_eq "p_not fails" "${ru4.status}" "err"

function _double { print -r -- "$(( $1 * 2 ))"; }
Result_t ru5; typeset -C su5; parse_init su5 "21"
p_map ru5 su5 _p_num _double
assert_eq "p_map transforms" "${ru5.value}" "42"

# =============================================================================
# End-to-end: key=value config parser
# =============================================================================

# Grammar: lines of "key = value" separated by newlines
# key = identifier, value = everything until newline or EOF

function _p_eq { p_char "$1" "$2" "="; }
function _p_nl { p_char "$1" "$2" $'\n'; }

function _p_value_char {
    typeset -n _r=$1 _s=$2
    if (( _s.pos >= _s.len )); then
        _r.err "end of input"
        return 0
    fi
    typeset _c=${_s.input:_s.pos:1}
    if [[ $_c == $'\n' ]]; then
        _r.err "newline"
        return 0
    fi
    (( _s.pos++ ))
    _r.ok "$_c"
}

# Parse one key=value pair using the pass-through pattern.
# The caller's Result_t name is forwarded to each sub-parser.
function _p_kv_pair {
    typeset -n _r=$1 _s=$2
    typeset _ref=$1 _sref=$2
    typeset -i _saved=${_s.pos}

    # key (with trailing whitespace via p_ident)
    p_ident "$_ref" "$_sref"
    if [[ ${_r.status} == err ]]; then _s.pos=$_saved; return 0; fi
    typeset _key=${_r.value}

    # = (p_ident already skipped trailing ws before =)
    p_char "$_ref" "$_sref" "="
    if [[ ${_r.status} == err ]]; then _s.pos=$_saved; return 0; fi

    _p_skip_spaces "$_sref"

    # value: everything until newline or EOF
    p_many1 "$_ref" "$_sref" _p_value_char
    if [[ ${_r.status} == err ]]; then _s.pos=$_saved; return 0; fi
    typeset _val=${_r.value}

    _r.ok "${_key}=${_val}"
}

Result_t re1; typeset -C se1
parse_init se1 $'name = Alice\nage = 30\ncity = Portland'
p_sep_by re1 se1 _p_kv_pair _p_nl
assert_eq "config parser ok" "${re1.status}" "ok"
assert_eq "config parser value" "${re1.value}" $'name=Alice\nage=30\ncity=Portland'

# Single entry
Result_t re2; typeset -C se2
parse_init se2 "host = localhost"
p_sep_by re2 se2 _p_kv_pair _p_nl
assert_eq "config single" "${re2.value}" "host=localhost"

# Empty input
Result_t re3; typeset -C se3
parse_init se3 ""
p_sep_by re3 se3 _p_kv_pair _p_nl
assert_eq "config empty" "${re3.value}" ""

# =============================================================================
# Regression tests from code review
# =============================================================================

# --- C1/C2: p_chainr1 trailing operator should succeed with single operand ---
Result_t rcr2; typeset -C scr2; parse_init scr2 "2^"
p_chainr1 rcr2 scr2 _p_num _p_pow_op
assert_eq "chainr1 trailing op" "${rcr2.value}" "2"
assert_eq "chainr1 trailing op pos" "${scr2.pos}" "1"

# --- p_chainr1 single operand (no operator at all) ---
Result_t rcr3; typeset -C scr3; parse_init scr3 "7"
p_chainr1 rcr3 scr3 _p_num _p_pow_op
assert_eq "chainr1 single operand" "${rcr3.value}" "7"
assert_eq "chainr1 single pos" "${scr3.pos}" "1"

# --- N2: p_between missing close should fail and backtrack ---
Result_t rb4; typeset -C sb4; parse_init sb4 "(42"
p_between rb4 sb4 _p_lparen _p_rparen _p_digits
assert_eq "between missing close" "${rb4.status}" "err"
assert_eq "between missing close pos" "${sb4.pos}" "0"

# --- p_between missing content should fail and backtrack ---
Result_t rb5; typeset -C sb5; parse_init sb5 "()"
p_between rb5 sb5 _p_lparen _p_rparen _p_digits
assert_eq "between empty content" "${rb5.status}" "err"
assert_eq "between empty content pos" "${sb5.pos}" "0"

# --- p_integer sign-only input should fail ---
Result_t rl11; typeset -C sl11; parse_init sl11 "-"
p_integer rl11 sl11
assert_eq "integer sign only" "${rl11.status}" "err"
assert_eq "integer sign only pos" "${sl11.pos}" "0"

Result_t rl12; typeset -C sl12; parse_init sl12 "+"
p_integer rl12 sl12
assert_eq "integer plus only" "${rl12.status}" "err"

# --- p_label on success should pass value through ---
Result_t ru6; typeset -C su6; parse_init su6 "5"
p_label ru6 su6 "a digit" p_digit
assert_eq "label success status" "${ru6.status}" "ok"
assert_eq "label success value" "${ru6.value}" "5"

# --- p_one_of with special characters ---
Result_t rc11; typeset -C sc11; parse_init sc11 "["
p_one_of rc11 sc11 '[]*()'
assert_eq "one_of special match" "${rc11.value}" "["

Result_t rc12; typeset -C sc12; parse_init sc12 "*"
p_one_of rc12 sc12 '[]*()'
assert_eq "one_of glob char" "${rc12.value}" "*"

Result_t rc13; typeset -C sc13; parse_init sc13 "x"
p_one_of rc13 sc13 '[]*()'
assert_eq "one_of special miss" "${rc13.status}" "err"

# --- p_string empty string argument ---
Result_t rc14; typeset -C sc14; parse_init sc14 "abc"
p_string rc14 sc14 ""
assert_eq "string empty match" "${rc14.status}" "ok"
assert_eq "string empty no advance" "${sc14.pos}" "0"

# --- p_many1 on empty input ---
Result_t rm6; typeset -C sm6; parse_init sm6 ""
p_many1 rm6 sm6 p_digit
assert_eq "many1 empty fails" "${rm6.status}" "err"

# =============================================================================
# Error codes (P_ERR_*) and .origin
# =============================================================================

# p_item EOF → P_ERR_EOF, origin = position
Result_t rec1; typeset -C sec1; parse_init sec1 ""
p_item rec1 sec1
assert_eq "item eof code" "${rec1.code}" "$P_ERR_EOF"
assert_eq "item eof origin" "${rec1.origin}" "0"

# p_eof not-at-end → P_ERR_EXPECT
Result_t rec2; typeset -C sec2; parse_init sec2 "x"
p_eof rec2 sec2
assert_eq "eof code" "${rec2.code}" "$P_ERR_EXPECT"
assert_eq "eof origin" "${rec2.origin}" "0"

# p_char mismatch → P_ERR_EXPECT
Result_t rec3; typeset -C sec3; parse_init sec3 "b"
p_char rec3 sec3 "a"
assert_eq "char expect code" "${rec3.code}" "$P_ERR_EXPECT"
assert_eq "char expect origin" "${rec3.origin}" "0"

# p_char EOF → P_ERR_EOF
Result_t rec4; typeset -C sec4; parse_init sec4 ""
p_char rec4 sec4 "a"
assert_eq "char eof code" "${rec4.code}" "$P_ERR_EOF"

# p_sat unexpected → P_ERR_UNEXP
Result_t rec5; typeset -C sec5; parse_init sec5 "x"
p_sat rec5 sec5 _p_is_digit
assert_eq "sat unexp code" "${rec5.code}" "$P_ERR_UNEXP"
assert_eq "sat unexp origin" "${rec5.origin}" "0"

# p_string mismatch → P_ERR_EXPECT, origin = start position
Result_t rec6; typeset -C sec6; parse_init sec6 "xxhello"
sec6.pos=2
p_string rec6 sec6 "world"
assert_eq "string expect code" "${rec6.code}" "$P_ERR_EXPECT"
assert_eq "string expect origin" "${rec6.origin}" "2"

# p_digit unexpected → P_ERR_UNEXP
Result_t rec7; typeset -C sec7; parse_init sec7 "x"
p_digit rec7 sec7
assert_eq "digit unexp code" "${rec7.code}" "$P_ERR_UNEXP"

# p_one_of unexpected → P_ERR_UNEXP
Result_t rec8; typeset -C sec8; parse_init sec8 "x"
p_one_of rec8 sec8 "abc"
assert_eq "one_of unexp code" "${rec8.code}" "$P_ERR_UNEXP"

# p_none_of unexpected → P_ERR_UNEXP
Result_t rec9; typeset -C sec9; parse_init sec9 "a"
p_none_of rec9 sec9 "abc"
assert_eq "none_of unexp code" "${rec9.code}" "$P_ERR_UNEXP"

# p_ident EOF → P_ERR_EOF
Result_t rec10; typeset -C sec10; parse_init sec10 ""
p_ident rec10 sec10
assert_eq "ident eof code" "${rec10.code}" "$P_ERR_EOF"

# p_ident bad start → P_ERR_EXPECT
Result_t rec11; typeset -C sec11; parse_init sec11 "42"
p_ident rec11 sec11
assert_eq "ident expect code" "${rec11.code}" "$P_ERR_EXPECT"

# p_not unexpected → P_ERR_UNEXP
Result_t rec12; typeset -C sec12; parse_init sec12 "5"
p_not rec12 sec12 p_digit
assert_eq "not unexp code" "${rec12.code}" "$P_ERR_UNEXP"
assert_eq "not unexp origin" "${rec12.origin}" "0"

# p_fail with explicit code and origin
Result_t rec13; typeset -C sec13; parse_init sec13 "x"
p_fail rec13 sec13 "custom error" 99
assert_eq "fail custom code" "${rec13.code}" "99"
assert_eq "fail custom origin" "${rec13.origin}" "0"

# origin tracks mid-input position
Result_t rec14; typeset -C sec14; parse_init sec14 "abc!"
sec14.pos=3
p_alpha rec14 sec14
assert_eq "mid-input origin" "${rec14.origin}" "3"

# =============================================================================
# p_label annotation (wrap_err style)
# =============================================================================

Result_t rlb1; typeset -C slb1; parse_init slb1 "!"
p_label rlb1 slb1 "identifier" p_ident
assert_eq "label annotates" "${rlb1.status}" "err"
assert_match "label has context" "${rlb1.error}" "expected identifier:*"
assert_match "label preserves detail" "${rlb1.error}" "*expected identifier at position 0*"
assert_eq "label code" "${rlb1.code}" "$P_ERR_LABEL"
assert_eq "label origin" "${rlb1.origin}" "0"

# Label on success still passes through
Result_t rlb2; typeset -C slb2; parse_init slb2 "foo"
p_label rlb2 slb2 "identifier" p_ident
assert_eq "label success" "${rlb2.status}" "ok"
assert_eq "label success value" "${rlb2.value}" "foo"

# =============================================================================
# case_code integration
# =============================================================================

function _test_handle_eof {
    typeset -n _r=$1
    _r.ok "recovered-from-eof"
}
function _test_handle_expect {
    typeset -n _r=$1
    _r.ok "recovered-from-expect"
}

# Parse failure → case_code dispatches on P_ERR_EOF
Result_t rcc1; typeset -C scc1; parse_init scc1 ""
p_integer rcc1 scc1
case_code rcc1 $P_ERR_EOF:_test_handle_eof $P_ERR_EXPECT:_test_handle_expect
assert_eq "case_code eof recovery" "${rcc1.value}" "recovered-from-eof"

# Parse failure → case_code dispatches on P_ERR_EXPECT
Result_t rcc2; typeset -C scc2; parse_init scc2 "abc"
p_char rcc2 scc2 "x"
case_code rcc2 $P_ERR_EOF:_test_handle_eof $P_ERR_EXPECT:_test_handle_expect
assert_eq "case_code expect recovery" "${rcc2.value}" "recovered-from-expect"

# case_code on ok result passes through
Result_t rcc3; typeset -C scc3; parse_init scc3 "5"
p_digit rcc3 scc3
case_code rcc3 $P_ERR_EOF:_test_handle_eof
assert_eq "case_code ok passthrough" "${rcc3.value}" "5"

# case_code with default handler
function _test_handle_any {
    typeset -n _r=$1
    _r.ok "caught-any"
}

Result_t rcc4; typeset -C scc4; parse_init scc4 "!"
p_digit rcc4 scc4
case_code rcc4 $P_ERR_EOF:_test_handle_eof default:_test_handle_any
assert_eq "case_code default" "${rcc4.value}" "caught-any"

print "parse.ksh: ${pass} passed, ${fail} failed"
(( fail == 0 ))
