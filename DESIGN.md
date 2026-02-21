# func.ksh Design Notes

func.ksh is a functional programming library for ksh93u+m. Its architecture
is grounded in System L, the linear sequent calculus described in Arnaud
Spiwack's "A Dissection of L" (2014).

This isn't decoration — the correspondence identifies which primitives are
fundamental, which are derived, and what structural gaps remain. System L
told us exactly what was missing (and what wasn't) before we wrote a line
of code.

Reference: Arnaud Spiwack. "A dissection of L." 2014. Licensed CC-BY 4.0.
Repository: https://github.com/aspiwack/dissect-L


## Theoretical Correspondence

| System L | func.ksh | Role |
|----------|----------|------|
| Cut rule `⟨t\|u⟩` | `match r ok_fn err_fn` | The single fundamental dispatch. Everything flows through here. |
| μ-binder `μx.c` | `chain r fn` | Ok-arm of cut. `match r fn -`. Monadic bind (>>=). |
| Dual μ-binder `μ̃x.c` | `or_else r fn` | Err-arm of cut. `match r - fn`. Recovery/fallback. |
| Additive sum A ⊕ B | `case_code r code1:fn1 code2:fn2` | Tagged choice eliminated by case analysis on error codes. |
| Shift-down ↓N | `Thunk_t t; t.new fn args` | Suspend a computation as a value. |
| Shift-up ↑P | `force r t` | Resume a suspended computation. |
| Exponential !A / ?A | `gather`/`collect` | Closest analogue, not exact. !A allows reuse of a linear resource; `gather` runs N independent copies of an operation against fresh Result_t values, accumulating into one. The accumulator Result_t plays the ?A role (absorbing context). Shell value semantics mean true linearity enforcement isn't needed — see "What We Don't Need." |
| Positive types (values) | `Result_t`, `SafeStr_t`, `SafePath_t`, `Version_t`, `Thunk_t` | Data at rest. Inert until acted on. |
| Negative types (computations) | `chain`, `match`, `force`, `sequence`, ... | Active transformations. Consume and produce values. |
| Commutative cuts | Pipeline fusion guidance | "Don't wrap a value only for the next step to unwrap it." |


## Architecture

`match` is the foundation. The dispatch hierarchy:

```
match (cut rule)
  ├── chain  = match r fn -        ok-arm only
  ├── or_else = match r - fn       err-arm only
  └── sequence = loop of chain     multi-step ok-path
```

Every combinator that dispatches on ok/err status bottoms out at `match`.
The combinators that do their own status checks are the ones that *should*:
`guard` (predicate evaluation, not function dispatch), `tap` (observation
without mutation), `gather` (accumulation, never short-circuits), and
`wrap_err` (field mutation, not dispatch).

### Composition patterns

The primitives compose through argument forwarding. `chain r fn extra_args`
calls `fn r extra_args`, so any combinator that follows the `fn result_var
[args...]` calling convention can be nested:

```ksh
chain r force my_thunk          # ok-gated thunk execution
chain r memo expensive_fn       # ok-gated cached execution
match r force_t1 force_t2       # dispatch between two suspended strategies
```


### Observation and retry

`tap`, `tap_ok`, and `tap_err` let you observe a result mid-pipeline without
affecting it. The observer runs, state is saved and restored, the pipeline
continues. `tap_ok` and `tap_err` are gated variants that only fire on the
matching status — the common case is logging errors without touching the
success path, or vice versa.

`retry` resets the result to `ok` with the original input value before each
attempt, giving the function a clean slate every time. This makes it safe
to retry operations that set `.err` as their failure mode.

### Avoiding subshells

Several `Result_t` methods exist in pairs — one that prints (for use in
`$(...)` command substitution) and one that writes into a variable via
nameref:

| Subshell form | Nameref form | Difference |
|--------------|--------------|------------|
| `val=$(r.value_or "default")` | `r.value_into var "default"` | Writes to `var` directly, no fork |
| `val=$(r.expect "ctx")` | `r.expect_into var "ctx"` | Writes to `var`, returns 1 on err |

The nameref forms avoid forking a subshell for each extraction. In tight
loops or pipelines that extract values repeatedly, this is the difference
between ~50,000 ops/sec and ~5,000 ops/sec. Use the subshell forms for
one-shot extractions where clarity matters more than speed.


## Polarity

System L distinguishes positive types (values, data at rest) from negative
types (computations, things that consume input). func.ksh already has this
distinction:

- **`types/`** — positive. `Result_t`, `SafeStr_t`, `SafePath_t`,
  `Version_t`, `Thunk_t`. These are inert structures. They hold data and
  validate it, but they don't dispatch or transform on their own.

- **`fn/`** — negative. `chain`, `match`, `force`, `guard`, `sequence`,
  `gather`, `collect`, `memo`, etc. These are active: they consume a
  `Result_t`, do something, and produce an updated `Result_t`.

There's no reason to encode this distinction in directory names or naming
conventions beyond what already exists. The `types/` vs `fn/` split is the
polarity distinction. Renaming things to `pos/` and `neg/` would add
ceremony without runtime benefit.


## What We Don't Need

### `dup` (explicit resource duplication)

System L's `!` modality handles explicit duplication of linear resources.
In a language with pointers or move semantics, you need `dup` to safely
copy a value that would otherwise be consumed.

Shell strings are value types. Every assignment is a copy. There is no
aliasing, no use-after-free, no move semantics. The `!` modality solves a
problem ksh doesn't have.

```ksh
# This already works — it's a value copy, not a reference
Result_t r2
r2.ok "${r.value}"
```

### Commutative cut fusion (as a combinator)

"Functions in a chain should operate at the same abstraction level."

This is a design principle, not a primitive. If step N wraps a value in
a structure and step N+1 immediately unwraps it, that's a commutative cut
that should be fused — but the fix is to rewrite the pipeline, not to add
a combinator that detects the pattern at runtime.

### `weaken` / `contract` (structural rules)

Linear logic restricts weakening (discarding unused values) and contraction
(using a value more than once). In func.ksh, `Result_t` variables are just
shell variables — they can be ignored or read multiple times without
ceremony. These structural rules are automatically satisfied by the shell's
value semantics.


## Patterns

### safe_fetch dual-mode

`safe_fetch` handles both HTTP headers-only (`-I`) and full body fetches
depending on what the caller needs. It validates URL schemes, captures curl
exit codes into Result_t error codes, and produces structured output. The
error codes map directly to curl's exit codes, making `case_code` a natural
fit for dispatch:

```ksh
safe_fetch r "$url"
case_code r 6:handle_dns_failure 22:handle_http_error default:handle_unknown
```

### Parallel gather

`gather` runs N independent operations, each against its own fresh Result_t,
and accumulates results into one. It doesn't fork — it's sequential in the
current shell. True parallelism would require subshells, and namerefs can't
cross fork boundaries (see "ksh93u+m Quirks" below).

For I/O-bound work where you'd want real parallelism, the pattern is to use
background processes for the external commands and gather the results:

```ksh
# Fan out external commands
curl "$url1" > /tmp/r1 &
curl "$url2" > /tmp/r2 &
wait

# Gather results in the current shell
gather r items parse_response
```

### Nameref limitation across forks

`typeset -n` namerefs resolve in the current shell's scope. A subshell
(`$(...)`, `( ... )`, or a pipeline component) gets a copy of the variable,
not a reference to the original. Modifications via nameref in a subshell
are silently lost.

This is why every combinator modifies the Result_t directly rather than
returning a new one — there's no way to return a compound variable from a
subshell. It also means `gather` can't parallelize with `&` and still
accumulate into a shared Result_t.


## Memoization

`memo` provides function-level result caching. The cache key includes the
function name, the current result state, and any extra arguments. All key
fields are `printf '%q'`-encoded and joined with `\x1f` (unit separator)
to prevent delimiter collisions — a value containing `:` or any other
printable character cannot collide with a differently-structured key.

Cache values are also encoded via `printf '%q'` and decoded via
`eval set --` — the same encode/decode pattern used by `Thunk_t`/`force`.
This is safe by construction: the encoded string is always produced by
`printf '%q'`, never by untrusted input.

The cache is a global associative array (`_FUNC_KSH_MEMO`) that persists
for the shell session. `memo_clear` resets it, optionally scoped to a
specific function name.

`memo` is most useful when wrapping functions that call external commands
(curl, jq, file operations) where the shell function call overhead is
negligible compared to the real work. For pure arithmetic functions that
run in microseconds, the cache lookup overhead exceeds the compute cost —
don't memoize those.


## ksh93u+m Quirks

### Compound type namerefs have a 1-level scope depth limit

When `typeset -n ref=varname` targets a compound type (`typeset -T`
instance like `Result_t`), the variable must be declared in the
immediate calling scope. Discipline functions (`.ok`, `.err`, `.is_ok`,
etc.) fail to resolve if the target is 2+ function scopes away.

```ksh
function outer {
    Result_t r
    middle r
}
function middle {
    typeset -n _m_r=$1        # nameref to r, 1 scope up — works
    _m_r.ok "hello"           # discipline function resolves
    inner "$1"
}
function inner {
    typeset -n _i_r=$1        # nameref to r, 2 scopes up — FAILS
    _i_r.ok "hello"           # "not found" error
}
```

This is why `try_cmd` needs its Result_t target in the immediate caller.
If you're writing a function that takes a Result_t name and internally
calls `try_cmd`, use a local Result_t for try_cmd and transfer the
result to the caller's Result_t via your 1-level nameref:

```ksh
function my_operation {
    typeset -n _mo_r=$1       # 1-level nameref to caller's Result_t
    Result_t _mo_tmp          # local for try_cmd (1-level from here)
    try_cmd _mo_tmp command git clone -- "$url" "$dest"
    if _mo_tmp.is_err; then
        _mo_r.err "clone failed: ${_mo_tmp.error}" ${_mo_tmp.code}
        return 0
    fi
    _mo_r.ok "$dest"
}
```

Simple namerefs (to scalars and indexed arrays) don't have this
limitation — they resolve through the full dynamic scope chain.
The constraint is specific to compound types with discipline functions.

### `create` is a reserved type method name

ksh93u+m's type system treats `create` specially. A type method named
`create` triggers a spurious `nounset` warning (`1: parameter not set`)
on every call, even when positional parameters are correctly set. The
method still executes correctly, but the stderr noise is unacceptable.

Other method names (`ok`, `err`, `new`, `make`, `init`, etc.) do not
trigger this. `Thunk_t` uses `.new` instead of `.create` for this reason.
