# func.ksh — safe shell primitives for ksh93u+m
# Source this file to initialize the library:
#   . /path/to/func.ksh/init.ksh

# Guard against double-sourcing
[[ -n ${_FUNC_KSH_INIT:-} ]] && return 0

# Require ksh93u+m
case ${.sh.version} in
    *93u+m*) ;;
    *) print -u2 "func.ksh: requires ksh93u+m (found: ${.sh.version})"
       return 1 ;;
esac

# Resolve library root from this file's location
_FUNC_KSH_ROOT=${.sh.file%/*}

# Safety baseline
set -o nounset -o pipefail -o noclobber

# Error trap — diagnostic only, does not abort
# Only fires when FUNC_KSH_TRACE is set (avoids noise from expected failures
# like is_ok/is_err returning false)
function _func_ksh_err_handler {
    [[ -n ${FUNC_KSH_TRACE:-} ]] &&
        print -u2 "func.ksh: error at ${1}:${2} (exit ${3})"
    return 0
}
trap '_func_ksh_err_handler "${.sh.file}" "${LINENO}" "$?"' ERR

# Cleanup temp files on exit (explicit return 0 avoids
# triggering ERR trap when the variable is unset)
function _func_ksh_cleanup {
    if [[ -n ${_FUNC_KSH_ERRTMP:-} ]]; then
        rm -f "$_FUNC_KSH_ERRTMP"
    fi
    # Clean up async channel files
    if [[ -d ${_FUNC_KSH_ASYNC_DIR:-} ]]; then
        rm -rf "$_FUNC_KSH_ASYNC_DIR" 2>/dev/null
    fi
    return 0
}
trap '_func_ksh_cleanup' EXIT

# Global state for memo combinator (associative array cache)
typeset -A _FUNC_KSH_MEMO

# Async channel directory (Future_t result files live here)
_FUNC_KSH_ASYNC_DIR="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/func_ksh_${UID:-$(id -u)}"
if [[ ! -d $_FUNC_KSH_ASYNC_DIR ]]; then
    mkdir -m 0700 -p "$_FUNC_KSH_ASYNC_DIR" 2>/dev/null
fi

# Source type definitions (order matters — no deps first)
for _f in "${_FUNC_KSH_ROOT}"/types/*.ksh; do
    [[ -f $_f ]] && . "$_f"
done
unset _f

# Register autoloaded functions
FPATH="${_FUNC_KSH_ROOT}/fn${FPATH:+:${FPATH}}"
for _f in "${_FUNC_KSH_ROOT}"/fn/*; do
    [[ -f $_f ]] && autoload "${_f##*/}"
done
unset _f

_FUNC_KSH_INIT=1
