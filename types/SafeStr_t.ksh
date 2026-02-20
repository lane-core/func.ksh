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
        if [[ $v == *$'\x01'* || $v == *$'\x02'* || $v == *$'\x03'* || \
              $v == *$'\x04'* || $v == *$'\x05'* || $v == *$'\x06'* || \
              $v == *$'\x07'* || $v == *$'\x08'* || \
              $v == *$'\x0b'* || $v == *$'\x0c'* || $v == *$'\x0d'* || \
              $v == *$'\x0e'* || $v == *$'\x0f'* || \
              $v == *$'\x10'* || $v == *$'\x11'* || $v == *$'\x12'* || \
              $v == *$'\x13'* || $v == *$'\x14'* || $v == *$'\x15'* || \
              $v == *$'\x16'* || $v == *$'\x17'* || $v == *$'\x18'* || \
              $v == *$'\x19'* || $v == *$'\x1a'* || $v == *$'\x1b'* || \
              $v == *$'\x1c'* || $v == *$'\x1d'* || $v == *$'\x1e'* || \
              $v == *$'\x1f'* || $v == *$'\x7f'* ]]; then
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
