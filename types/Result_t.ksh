# Result_t — the core error-handling type
#
# Every fallible operation returns its outcome through a Result_t.
# Chained via the `chain` function (monadic bind), which short-circuits
# on the first error.
#
# Usage:
#   Result_t r
#   r.ok "some value"
#   r.err "something broke" 2 "${.sh.file}:${LINENO}"
#   chain r some_function arg1 arg2

typeset -T Result_t=(
    typeset status='ok'
    typeset value=''
    typeset error=''
    typeset -i code=0
    typeset origin=''

    # Reject invalid status values at assignment time
    function status.set {
        case ${.sh.value} in
            ok|err) ;;
            *) print -u2 "Result_t: invalid status '${.sh.value}'"
               .sh.value=${_.status}
               return 1 ;;
        esac
    }

    # Set a successful result
    function ok {
        _.status=ok
        _.value="$1"
        _.error=''
        _.code=0
        _.origin=''
    }

    # Set an error result
    # $1=message, $2=exit code (default 1), $3=origin (optional, e.g. "${.sh.file}:${LINENO}")
    function err {
        _.status=err
        _.error="$1"
        _.code="${2:-1}"
        _.origin="${3:-}"
        _.value=''
    }

    function is_ok {
        [[ ${_.status} == ok ]]
    }

    function is_err {
        [[ ${_.status} == err ]]
    }

    # Print .value if ok, or the default if err
    # Usage: val=$(r.value_or "fallback")
    function value_or {
        if [[ ${_.status} == ok ]]; then
            print -r -- "${_.value}"
        else
            print -r -- "$1"
        fi
    }

    # Print .value if ok, or report error and return 1
    # Usage: val=$(r.expect "should never fail") || exit 1
    function expect {
        if [[ ${_.status} == ok ]]; then
            print -r -- "${_.value}"
        else
            print -u2 "expect failed: $1: ${_.error}"
            return 1
        fi
    }

    # Write .value (or default) into a variable — no subshell needed
    # Usage: r.value_into myvar "fallback"
    function value_into {
        typeset -n _vi_out=$1
        if [[ ${_.status} == ok ]]; then
            _vi_out=${_.value}
        else
            _vi_out=${2:-}
        fi
    }

    # Write .value into a variable, or report error and return 1
    # Usage: r.expect_into myvar "context" || exit 1
    function expect_into {
        typeset -n _ei_out=$1
        if [[ ${_.status} == ok ]]; then
            _ei_out=${_.value}
        else
            print -u2 "expect failed: $2: ${_.error}"
            return 1
        fi
    }

    # Reset to initial state (useful for reusing accumulators)
    function reset {
        _.status=ok
        _.value=''
        _.error=''
        _.code=0
        _.origin=''
    }

    # Print a human-readable summary to stderr
    function report {
        if [[ ${_.status} == ok ]]; then
            print -u2 "ok: ${_.value}"
        else
            if [[ -n ${_.origin} ]]; then
                print -u2 "err[${_.code}]: ${_.error} (${_.origin})"
            else
                print -u2 "err[${_.code}]: ${_.error}"
            fi
        fi
    }
)
