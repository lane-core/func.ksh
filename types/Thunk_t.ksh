# Thunk_t — a suspended computation (shift-down ↓N)
#
# Stores a function name and encoded arguments as an inert value.
# Execute later with `force`. Arguments are encoded via printf '%q'
# for safe round-tripping through eval.
#
# Usage:
#   Thunk_t t
#   t.new my_function arg1 "arg with spaces"
#   force r t    # executes: my_function r arg1 "arg with spaces"
#
# Reference: Arnaud Spiwack. "A dissection of L." 2014. (↓N connective)

typeset -T Thunk_t=(
    typeset fn=''
    typeset argv=''

    # 'new' rather than 'create': ksh93u+m has a nounset bug with
    # the name 'create' in type methods (spurious "parameter not set")
    function new {
        _.fn=$1
        if (( $# > 1 )); then
            typeset _encoded
            _encoded=$(printf '%q ' "${@:2}")
            _.argv=${_encoded% }
        else
            _.argv=''
        fi
    }

    function get {
        if [[ -n ${_.argv} ]]; then
            .sh.value="${_.fn} ${_.argv}"
        else
            .sh.value=${_.fn}
        fi
    }
)
