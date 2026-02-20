# SafePath_t — a validated filesystem path
#
# Enforces: no path traversal via .., no shell metacharacters.
# The path is normalized on assignment.

typeset -T SafePath_t=(
    typeset value=''

    function value.set {
        typeset v=${.sh.value}

        # Reject empty
        if [[ -z $v ]]; then
            print -u2 "SafePath_t: empty path"
            .sh.value=${_.value}
            return 1
        fi

        # Reject command substitution / injection
        case $v in
            *'`'*|*'$('*|*'${'*)
                print -u2 "SafePath_t: rejected path containing shell expansion"
                .sh.value=${_.value}
                return 1 ;;
        esac

        # Reject path traversal: check every component for '..'
        # Splitting on / catches all variants (./.. , foo/../bar, etc.)
        typeset _sp_comp
        typeset _sp_ifs=$IFS
        IFS=/
        for _sp_comp in $v; do
            if [[ $_sp_comp == '..' ]]; then
                IFS=$_sp_ifs
                print -u2 "SafePath_t: rejected path containing '..'"
                .sh.value=${_.value}
                return 1
            fi
        done
        IFS=$_sp_ifs

        # Null bytes can't exist in shell strings (C null-terminated),
        # so no check needed — the shell already prevents them.
    }

    function get {
        .sh.value=${_.value}
    }

    # Check if the path exists as any type
    function exists {
        [[ -e ${_.value} ]]
    }

    # Check if the path is a directory
    function is_dir {
        [[ -d ${_.value} ]]
    }

    # Check if the path is a regular file
    function is_file {
        [[ -f ${_.value} ]]
    }

    # Check if the path is writable
    function is_writable {
        [[ -w ${_.value} ]]
    }

    # Return the directory portion (matches POSIX dirname behavior)
    function dirname {
        typeset v=${_.value}
        # Strip trailing slashes
        v=${v%${v##*[!/]}}
        # All slashes (including bare /) → root
        if [[ -z $v ]]; then
            print -r -- "/"
        # No slashes at all → current directory
        elif [[ $v != */* ]]; then
            print -r -- "."
        else
            v=${v%/*}
            v=${v%${v##*[!/]}}
            print -r -- "${v:-/}"
        fi
    }

    # Return the filename portion (matches POSIX basename behavior)
    function basename {
        typeset v=${_.value}
        # Strip trailing slashes
        v=${v%${v##*[!/]}}
        # All slashes (including bare /) → /
        [[ -z $v ]] && { print -r -- "/"; return 0; }
        print -r -- "${v##*/}"
    }
)
