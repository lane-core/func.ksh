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
| Tensor A ⊗ B | `both r fn1 fn2` | Independent operations on same input, all must succeed. Split resources: each fn gets fresh Result_t. |
| Additive sum A ⊕ B (success side) | `first r fn1 fn2` | Try alternatives on original input, first success wins. Dual of `case_code`. |
| Exponential !A / ?A | `tap` (structural), `gather`/`collect` (operational) | `tap` is the structural match: save/run/restore is the promote/observe/discard cycle of !A. `gather`/`collect` are the operational pattern: run N independent copies against fresh Result_t values, accumulating into one (the accumulator plays the ?A role). Shell value semantics mean true linearity enforcement isn't needed — see "What We Don't Need." |
| Positive types (values) | `Result_t`, `SafeStr_t`, `SafePath_t`, `Version_t`, `Thunk_t` | Data at rest. Inert until acted on. |
| Negative types (computations) | `chain`, `match`, `force`, `sequence`, ... | Active transformations. Consume and produce values. |
| Commutative cuts | Pipeline fusion guidance | "Don't wrap a value only for the next step to unwrap it." |


## Architecture

`match` is the foundation. The dispatch hierarchy:

```
match (cut rule)
  ├── chain     = match r fn -       ok-arm only
  ├── or_else   = match r - fn       err-arm only
  └── sequence  = loop of chain      multi-step ok-path

Independent (own status checks):
  ├── both      tensor: all fns on one input, all must succeed
  ├── first     choice: try fns on one input, first success wins
  ├── guard     predicate gating
  ├── tap       observation (save/restore = implicit !)
  ├── gather    accumulate (one fn, many inputs)
  └── wrap_err  error annotation

Async (shift-down/up across fork boundary):
  ├── defer     spawn background computation → Future_t
  ├── poll      non-blocking completion check
  └── await     blocking wait, consumes Future_t → Result_t
```

Every combinator that dispatches on ok/err status bottoms out at `match`.
The independent combinators do their own status checks because they *should* —
they operate outside the single-dispatch model, running multiple functions,
evaluating predicates, or mutating fields directly.

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

`tap` is the operational equivalent of the ! (bang) modality — the
promote/observe/discard cycle. Save state promotes the value to duplicable,
run observer uses the copy, restore state discards it. This is why tap
can observe without consuming: it's working on a promoted copy.

### Tensor and choice

`both` and `first` fill the two structural gaps identified by the System L
correspondence.

`both` is the multiplicative tensor (A ⊗ B). It splits resources so each
function gets an independent copy of the input. All must succeed. This is
to `sequence` as `gather` is to `chain` — accumulate vs. short-circuit.
The typical use is running multiple validators on the same input, where you
want all error messages, not just the first one:

```ksh
both r check_nonempty -- check_min_len 8 -- check_charset '[a-z]'
# All three validators run; errors accumulated if any fail
```

`first` is additive disjunction on the success side (A ⊕ B). It tries
alternatives on the original input until one succeeds. This is the
success-side dual of `case_code`, which dispatches on error codes.

```ksh
first r parse_json parse_yaml parse_toml
# First successful parse wins; its output value is adopted
```

Key contrasts:

- `first` vs. `or_else`: `or_else` passes the *error* to the recovery
  function. `first` passes the *original value* to each alternative.
- `first` vs. `retry`: `retry` runs the *same* function N times. `first`
  runs N *different* functions once each.
- `both` vs. multiple guards via `chain`: guards short-circuit on first
  failure. `both` runs all validators and reports everything that's wrong.

### Async: defer / await / poll

`Thunk_t`/`force` implement synchronous shift-down/up — suspend a computation
as a value, resume it later, all within the current shell. `defer`/`await`
extend this across a fork boundary: the computation runs in a background
subshell and communicates its result through a file-backed channel.

The session type protocol is minimal:
- **Background** (`defer`): `!Result_t.end` — sends one Result_t, exits.
- **Parent** (`await`): `?Result_t.end` — receives one Result_t, session ends.

The channel file encodes the result as two parts: a header line (`ok` or
`err CODE`) and the body (value or error message). `await` reads this via
file descriptors (no `$()` subshell) to preserve trailing newlines.

**Linearity enforcement.** `await` consumes the future — it reads the channel,
removes the file, and resets the `Future_t` to empty state. Calling `await`
twice on the same future is an error. To make a result reusable (the `!A`
exponential), cache the `Result_t` after awaiting, or use `memo` on the
computation instead of `defer`.

**Relationship to Thunk_t/force.** Both pairs are shift-down/up:

| | Shift-down (suspend) | Shift-up (resume) | Execution |
|---|---|---|---|
| `Thunk_t`/`force` | `t.new fn args` | `force r t` | Synchronous, in-process |
| `Future_t`/`defer`+`await` | `defer f fn args` | `await r f` | Asynchronous, cross-fork |

`poll` is a non-blocking probe — it checks whether the background process has
exited (`kill -0`) and updates the `Future_t` status without consuming it.
`poll` followed by `await` is guaranteed not to block.

**Dedup mechanism.** The `-k` flag on `defer` assigns a semantic key to the
future. If a future with the same key is already pending, `defer` is a no-op.
This prevents redundant spawns when the same computation is requested multiple
times (e.g., polling git status from multiple hooks). Without `-k`, each
`defer` call spawns unconditionally.

**Nameref limitation.** Compound type namerefs (`Result_t`) don't survive fork
boundaries — a subshell gets a copy, not a reference. This is why `defer`
serializes the result to a file rather than passing it through a nameref. The
same limitation applies to `gather`'s inability to parallelize with `&`.

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

### Remaining System L connectives

The following connectives from Spiwack's dissection have no func.ksh
representation, and intentionally so:

- **Par (A ⅋ B)**: The multiplicative dual of tensor. Needs product types
  (two independent result channels) that shell doesn't have. A single
  Result_t is either ok or err, never both simultaneously.
- **With (A & B)**: Additive conjunction — "offer both, consumer picks one."
  Two `Thunk_t`s cover this: suspend both alternatives, force whichever
  one you need.
- **Zero (0) / Top (⊤) / Unit (1) / Bottom (⊥)**: The units and empties
  of the four connective families. These are identity elements with no
  runtime representation — the empty tensor, the trivially-true choice, etc.
  In shell, "do nothing" is just... not calling a function.
- **Explicit !/? (exponential modalities)**: `tap` is the structural match
  — save/run/restore is the !A promote/observe/discard cycle. `gather` and
  `collect` are the operational pattern — running N independent copies
  against fresh Result_t values, with the accumulator as the ?A absorbing
  context. Shell value semantics make explicit tracking unnecessary —
  see `dup` above.


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


## Parser Combinators

func.ksh includes a monadic parser combinator library based on Hutton &
Meijer's "Monadic Parser Combinators" (1996, Technical Report
NOTTCS-TR-96-4, University of Nottingham). The parsers live in `fn/parse/`
and are autoloaded alongside the core `fn/` combinators.

### Calling convention

Every parser takes a Result_t variable name as `$1` and a parse state
compound variable name as `$2`:

```ksh
Result_t r
typeset -C ps
parse_init ps "hello world"
p_string r ps "hello"
```

Parse state is a compound variable with `.input`, `.pos`, and `.len` fields,
initialized by `parse_init`. Parsers advance `.pos` on success and leave it
unchanged (or restore it) on failure.

After parsing, the Result_t feeds directly into func.ksh combinators:

```ksh
p_integer r ps
chain r validate_range 1 100
or_else r use_default_port
wrap_err r "config parse"
```

Error codes (`P_ERR_EOF`, `P_ERR_UNEXP`, `P_ERR_EXPECT`, `P_ERR_LABEL`)
enable `case_code` dispatch on failure type:

```ksh
p_integer r ps
case_code r $P_ERR_EOF:handle_eof $P_ERR_EXPECT:handle_bad_input
```

### Scope constraint

Result_t variables passed to parsers MUST be declared at file scope, not
inside a function. ksh93u+m compound-type namerefs resolve discipline
functions (`.ok`, `.err`) through the full scope chain for global variables,
but only 1 level deep for function-local variables. Since combinators like
`p_natural`, `p_integer`, and `p_token` add scope levels before calling
leaf parsers (`p_many1` -> `p_digit`), a function-local Result_t will
silently fail. Parse state (`typeset -C`) is not affected — only Result_t.
See "Compound type namerefs" above for details.

### Combinator pass-through

Combinators pass the caller's Result_t name through to sub-parsers rather
than creating local Result_t intermediaries. This avoids the compound-type
nameref depth limit: the sub-parser's nameref resolves to the (file-scope)
Result_t regardless of call depth. The combinator reads status/value via
its own 1-level nameref after each sub-parser returns.

### Character parsers are inlined

`p_digit`, `p_alpha`, `p_alnum`, `p_lower`, `p_upper`, and `p_space` are
inlined rather than delegating to `p_sat`. A thin wrapper like
`function p_digit { p_sat "$1" "$2" _p_is_digit; }` would add an extra
scope level that breaks when called from inside a combinator due to the
nameref depth limit described above.
