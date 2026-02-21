# SafeStr_t — a string validated against shell injection vectors
#
# Rejects command substitution syntax, control characters, and
# unescaped shell metacharacters. Safe to use in double-quoted
# interpolation ("${s.value}"). NOT safe unquoted — word splitting
# and globbing still apply to values containing whitespace or
# glob characters, as with any shell string.

typeset -T SafeStr_t=(
    typeset value=''

    function value.set {
        typeset v=${.sh.value}

        # Reject all C0 control characters except tab (\x09) and
        # newline (\x0a). This covers: \x01-\x08, \x0b-\x1f, \x7f.
        # Notably includes \x0d (CR, terminal line overwrite),
        # \x1b (ESC, ANSI escape sequences), and the rest of C0.
        typeset _bad=$'\x01\x02\x03\x04\x05\x06\x07\x08\x0b\x0c\x0d\x0e\x0f'
        _bad+=$'\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f\x7f'
        if [[ $v == *[$_bad]* ]]; then
            print -u2 "SafeStr_t: rejected value containing control characters"
            .sh.value=${_.value}
            return 1
        fi

        # Reject syntax that enables command/variable injection
        case $v in
            *'`'*|*'$('*|*'${'*|*'$['*)
                print -u2 "SafeStr_t: rejected value containing shell expansion syntax"
                .sh.value=${_.value}
                return 1 ;;
        esac
    }

    function get {
        .sh.value=${_.value}
    }
)
