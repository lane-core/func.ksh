# Future_t — a handle to a background computation (async shift-down ↓N)
#
# Extends the shift-down concept from Thunk_t (synchronous, in-process)
# into asynchronous territory: the computation runs in a background
# subshell and communicates its Result_t through a file-backed channel.
#
# Session type:  !Result_t.end  (background sends one result, session ends)
# Dual:          ?Result_t.end  (parent receives one result, session ends)
#
# The result file is the channel. Linearity is enforced: `await` consumes
# the future by reading and removing the result file. To make a result
# reusable (!A exponential), wrap with `memo` or an application-level cache.
#
# Usage:
#   Future_t f
#   defer f my_function arg1 arg2
#   poll f && print "done"       # non-blocking check
#   await r f                    # blocking wait, yields Result_t
#
# Reference:
#   Arnaud Spiwack. "A dissection of L." 2014. (↓N / ↑P connectives)
#   Session types: Honda 1993, Honda/Vasconcelos/Kubo 1998.

typeset -T Future_t=(
    typeset -i pid=0
    typeset channel=''
    typeset key=''

    # Discipline: restrict status to valid values
    typeset status='empty'
    function status.set {
        case ${.sh.value} in
            empty|pending|resolved|failed) ;;
            *) print -u2 "Future_t: invalid status '${.sh.value}'"
               .sh.value=${_.status}
               return 1 ;;
        esac
    }

    function is_pending {
        [[ ${_.status} == pending ]]
    }

    function is_resolved {
        [[ ${_.status} == resolved ]]
    }

    function is_failed {
        [[ ${_.status} == failed ]]
    }

    function reset {
        _.pid=0
        _.channel=''
        _.key=''
        _.status=empty
    }
)
