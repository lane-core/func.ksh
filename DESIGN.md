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
| Exponential !A | `gather`/`collect` | Duplicate a linear resource: run N independent operations, accumulate results. |
| Exponential ?A | Accumulator `Result_t` in gather | The context that absorbs duplicated results. |
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


## Memoization

`memo` provides function-level result caching. The cache key includes the
function name, the current result state, and any extra arguments:

```
ok:fn_name:value:extra_args     — for ok-status inputs
err:fn_name:error:code:extra_args — for err-status inputs
```

Results are encoded via `printf '%q'` and decoded via `eval set --` — the
same encode/decode pattern used by `Thunk_t`/`force`. This is safe by
construction: the encoded string is always produced by `printf '%q'`, never
by untrusted input.

The cache is a global associative array (`_FUNC_KSH_MEMO`) that persists
for the shell session. `memo_clear` resets it, optionally scoped to a
specific function name.

`memo` is most useful when wrapping functions that call external commands
(curl, jq, file operations) where the shell function call overhead is
negligible compared to the real work. For pure arithmetic functions that
run in microseconds, the cache lookup overhead exceeds the compute cost —
don't memoize those.


## ksh93u+m Quirks

### `create` is a reserved type method name

ksh93u+m's type system treats `create` specially. A type method named
`create` triggers a spurious `nounset` warning (`1: parameter not set`)
on every call, even when positional parameters are correctly set. The
method still executes correctly, but the stderr noise is unacceptable.

Other method names (`ok`, `err`, `new`, `make`, `init`, etc.) do not
trigger this. `Thunk_t` uses `.new` instead of `.create` for this reason.
