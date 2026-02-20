#!/usr/bin/env ksh
# Run all func.ksh tests

typeset -i total_pass=0 total_fail=0 suites=0
typeset testdir=${0%/*}

for test in "$testdir"/test_*.ksh; do
    [[ -f $test ]] || continue
    (( suites++ ))
    print "--- ${test##*/} ---"
    output=$(ksh "$test" 2>&1) || true
    print -r -- "$output"

    # Extract pass/fail counts from last line
    typeset last_line=${output##*$'\n'}
    if [[ $last_line == *passed* ]]; then
        typeset p=${last_line%%passed*}
        p=${p##*: }
        p=${p// /}
        typeset f=${last_line#*,}
        f=${f%%failed*}
        f=${f// /}
        # Validate parsed values are numeric
        if [[ $p == +([0-9]) && $f == +([0-9]) ]]; then
            (( total_pass += p ))
            (( total_fail += f ))
        else
            (( total_fail++ ))
            print "  (malformed summary — treating as failure)"
        fi
    else
        (( total_fail++ ))
        print "  (no summary — treating as failure)"
    fi
    print ""
done

print "=== TOTAL: ${total_pass} passed, ${total_fail} failed (${suites} suites) ==="
(( total_fail == 0 ))
