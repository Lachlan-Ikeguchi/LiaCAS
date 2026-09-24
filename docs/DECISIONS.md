# LiaCAS — Design Rationale (ADR log)

This file records *why* the decisions in [`DESIGN.md`](DESIGN.md) were made:
the context, the alternatives considered, and the arguments that settled each
choice. Anyone with a copy of the repository should be able to understand the
design's reasoning without consulting external discussion threads.

Entries are ordered roughly chronologically. Each entry ends with a pointer
to the section of `DESIGN.md` that specifies the decision.

---

## ADR-001: Whitespace as an operator (double space, `/` swallow)

**Context.** ASCII math demands heavy parenthesization for fractions, which
was the founding gripe of this project. Conventional precedence also makes
`... / 2 a` parse as `(…/2) * a`, which silently breaks the way people write
the quadratic formula.

**Decision.** Space becomes significant with three roles: single space =
factor multiplication, double space = chunk multiplication (looser than
`/`), and `/` takes **single-space products on both sides** as its
numerator and denominator. Double space is the escape hatch that pulls a
factor out of a denominator; single space is the default glue.

**Alternatives.**
- Standard precedence (`a / b * c` = `(a/b)*c`): rejected — the founding
  use case `(-b \pm sqrt(b^2 + 4ac)) / 2a` would require explicit parens.
- Implicit multiplication binding tighter than `/` always: rejected —
  there would be no way to escape the swallow when you *want* `(a/b)*c`.
  Double space provides the opt-out symmetrically.

**Formalization.** The spacing rules are defined by the bracket desugaring
(ADR-009): DS inserts chunk brackets, `/` inserts fraction brackets
contained within one chunk. `r␣␣b / 2a` is `r × (b/(2a))` — the DS seals the
first chunk before `/` appears, so `r` cannot be pulled into the numerator.

**Consequences.** `/` is left-associative (`a / b / c` = `(a/b)/c`); `*`
sits at single-space level (`a / b * c` = `a/(b*c)`), documented as an
intentional difference from most languages. Spec: §3.2, §5.1.

## ADR-002: Definitions are rewrite rules (unified store)

**Context.** An early draft kept "definitions" and "rewrite rules" as
separate store compartments. Review pointed out this is artificial: if `x`
is defined equal to an expression, other expressions containing `x` should
expand to it — which is exactly what a rewrite rule does.

**Decision.** One concept: the store holds rules keyed by LHS. A rule whose
LHS is a literal symbol is a *definition*; a rule whose LHS contains `$`
metavariables is a *pattern rule*. Both fire during rewriting. Ground-value
substitution (`b := 24`) is the same mechanism — the rule `b → 24`.

**Alternatives.** Separate stores with separate application logic:
rejected as duplicated machinery with no observable difference.

**Consequences.** `x := e` clears then defines; `x = e` appends; both apply
uniformly to symbols and patterns, so there is exactly one clear/append
semantics to implement and explain. Spec: §2, §6, §9.

## ADR-003: `:=` clears, `=` appends

**Context.** The two assignment operators needed distinct meanings.

**Decision.** `x := e` clears all previous definitions of `x` and defines
it by `e`; `x = e` appends `e` to the definitions of `x`, making the list a
conjunction (`x` must satisfy every definition).

**Reasoning.** The clear/append split matches how mathematical writing
reuses `=` (adding conditions) versus how a specification resets a symbol.
Uniformity with patterns (ADR-002) came for free.

**Consequences.** Multiple `=` definitions can contradict; contradiction
handling is ADR-005. Appending rules with the same pattern LHS is how
alternative simplification paths are expressed. Spec: §6.

## ADR-004: Pattern variables bind any subexpression, with `where` guards

**Context.** Patterns like `lim($x -> 0, sin($x)/$x) = 1` were the
motivating example for the rewrite engine. Early discussion restricted `$x`
to variables; that makes most useful rules unwritable.

**Decision.** `$x` binds any subexpression, consistently within one
pattern. Rules carry optional `where` guards — a `;`-separated conjunction
of relations, verified **fail-closed** (a guard passes only if provable
from the store; unverifiable means the rule does not fire). Guards may
reference bound metavariables (`$x != 0`) or absolute symbols resolved
against the assumption store.

**Alternatives.**
- Unguarded rules: rejected — `$x/$x = 1` would ship a wrong
  simplification at `$x = 0`. Guards are a correctness requirement, not
  decoration.
- Fail-open guards (fire unless disproven): rejected — an engine that
  guesses produces silently wrong algebra.
- A special `NONZERO` set for nonzero-ness: rejected in review — the
  direct form (`x != 0` as a standalone assumption) is simpler and covers
  the case without new vocabulary.

**Consequences.** Rules are one-directional; the reverse is a separate
explicit rule. Matching is up to AC for `+`/`*` (ADR-013). Spec: §9, §10.

## ADR-005: Contradictions detected, reported to stderr, statement rejected

**Context.** `x = 2` followed by `x = 3` — what should happen?

**Decision.** The contradiction is detected and reported on stderr; the
offending statement is **rejected** and the store is left untouched.

**Alternatives.** Quarantine the contradictory definitions and continue:
rejected — a CAS that keeps a corrupted store produces confident nonsense
downstream.

**Consequences.** Batch exit code 2 for contradictions; full store-wide
consistency checking is deferred with the solver (§17). Spec: §12.

## ADR-006: Facts are equations; solver staged as S1–S3

**Context.** Prompts carry "new information with implications for known
definitions" — e.g. header `x := b + 1`, prompt `x = 24` should derive
`b := 23`. How deep should implication go?

**Decision.** The fact language is equations (compound LHS legal:
`b + 1 = 25`). The solver is a single `solve(equation, store)` interface
with **staged capability** (DESIGN §7.1): S1 substitution + linear
isolation, S2 polynomial solving with `±`-branch selection, S3 systems.
Unsolved equations are recorded as *constraints* and re-attempted as
solver capability grows. The stages are built as milestones M5/M9/M10 of
[`ROADMAP.md`](../ROADMAP.md); each strictly extends the previous.

**Alternatives.**
- Substitution-only: rejected — `b + 1 = 25` is too basic to fail on.
- Full solver first: rejected — a full solver (quadratics, systems,
  `±`-branch selection) is a project on its own; the staged interface lets
  it slot in later without redesign.

**Consequences.** Multi-definition symbols must agree after expansion
(§2); disagreement-driven solving is an open refinement (§19). Spec: §7.

## ADR-007: Assumption store as a third statement kind

**Context.** Guards like `r > 10` need context that is not a definition —
substituting `r > 10` into expressions is meaningless.

**Decision.** Statements classify into rules (definitions/patterns),
assumptions (`r > 10`, `n in INTEGER`), and constraints. Assumptions are
consulted by guard verification and the future solver but never rewritten
into. `x = 24` is a fact *and* a definition insert; relations and set
membership are always assumptions.

**Consequences.** Built-in sets (`NATURAL` ∋ 0 per ISO 80000-2,
`INTEGER`, `RATIONAL`, `REAL`, `COMPLEX`, `PRIME`, `BOOLEAN`) are reserved
uppercase names; `in` appears both standalone and inside `where` with the
same grammar. Spec: §8.

## ADR-008: ASCII surface with LaTeX commands only where needed

**Context.** Input must be ASCII — `±` and friends are annoying or
impossible to type. But ASCII also lacks arrows and relations.

**Decision.** `\commands` are used only for non-typable symbols (`\pm`,
`\infty`, `\alpha`); everything typable stays ASCII (`->`, `>=`, `<=`,
`!=`, `sqrt`, `sin`, `lim`). Commands end at their first non-letter
character (a fixed table) — see ADR-010 for spaces.

**Alternatives.** Full LaTeX (`\geq`, `\rightarrow`): rejected — verbose
for things ASCII already types fine. Unicode input: rejected by
requirement. Spec: §3.1.

## ADR-009: Bracket desugaring as the formal whitespace semantics

**Context.** The spacing rules of ADR-001 were first written as prose and
a precedence table. Discussion showed prose invites ambiguity: a
single-kind bracket notation could be misread (`[r][b]/[2a]` as
`(r·b)/(2a)`, which would make DS a no-op and destroy the denominator
escape hatch).

**Decision.** The formal semantics is a desugaring pass over the lexed
token stream with **two bracket kinds**: chunk brackets `[ ]` inserted by
DS (implicit `[` opens each summand), and fraction brackets `( )`
inserted by `/`, **contained within one chunk** — the numerator reaches
back only to the nearest chunk boundary, the denominator forward only to
the next one. `r␣␣b / 2a` → `[r] [(b)/(2a)]` → `r × (b/(2a))`.

**Implementation.** The runtime parser is a whitespace-aware
precedence-climbing parser whose recursion levels *are* these brackets —
no token mutation happens at runtime. The desugaring is kept as the
testable specification: tests run both paths and require identical trees.

**Alternatives.** Sign-merge special case (a lone-sign chunk reaches into
the next chunk's numerator): rejected — it crosses levels and broke the
escape-hatchet symmetry; the chunk-level merge of ADR-011 replaces it.
Spec: §5.1.

## ADR-010: `\command` termination is free (no semantic space consumed)

**Context.** TeX consumes one space after a control word as its
terminator. If LiaCAS did the same *semantically*, typing `\pm  b`
(double space intent) would deliver only a single space's meaning — and a
REPL-only compensation hack (typed N spaces ⇒ semantic N−1, triple-space
for a real DS) was drafted, then rejected as confusing.

**Decision.** A command name ends at its first non-letter character,
matched against the fixed command table. **No semantic whitespace is ever
consumed as a terminator.** Spaces after a `\command` carry their full
count and mean exactly what the same number of spaces means anywhere
else — in batch files and the REPL alike.

**Alternatives.**
- TeX-style semantic terminator: rejected — it silently eats a
  semantic space and breaks round-tripping ambiguities.
- REPL preprocessing that auto-appends one space: rejected — equivalent
  behavior to the chosen rule, but it creates a REPL/batch divergence;
  a renderer-printed line would re-parse differently as a header,
  breaking the round-trip contract. Engine-level counting keeps batch
  and REPL identical.

**Consequences.** `\pm 4` is plus-or-minus 4; `\pm␣␣b / 2 a` is
`±(b/(2a))` (via ADR-011). No triple-space trick exists. Spec: §3.1.

## ADR-011: Sign spacing — SS binds the first factor, DS binds the whole next chunk

**Context.** What does a double space after a prefix sign mean? Four
readings were considered across several rounds: (a) inert (sign attaches
to the next chunk's numerator — DS a no-op after signs); (b) signed
chunk: `±␣␣X` groups the signed quantity as one numerator unit; (c)
additive-level prefix: the sign escapes the fraction; (d) the sign-only
chunk **merges with the whole next chunk**, fraction and all.

**Decision.** (d). In sign position:
- **Single space** — the sign binds the **first factor** of the following
  numerator: `\pm b / 2 a` = `(±b)/(2a)`, matching written math
  (`-b/2a` on a page reads as `(−b)/(2a)`).
- **Double space** — the sign applies to the **whole next chunk**, as a
  unit, fraction and all: `\pm␣␣b / 2 a` = `±(b/(2a))`. The sign's scope
  is exactly the next chunk — a further DS ends it
  (`\pm␣␣b / 2 a␣␣c` = `(±(b/(2a))) × c`).

**Reasoning.** Option (a) made DS after a sign a no-op, leaving the
whole-fraction reading inexpressible without parens. Option (b) required
a special exception to the bracket model (the sign reaching *through*
fraction brackets into a numerator — crossing levels). Option (d) falls
out of the bracket model with no exceptions: a chunk cannot consist
solely of signs, so it merges at **chunk level** with what follows. It
also generalizes the operand-spacing principle: more space = looser
binding, for operands and signs alike. Both trees have the same value
(sign distributes over `/` and `*`), so the engine never normalizes
between them — this is tree-shape control for patterns and rendering.

**Consequences.** DS adjacent to a *binary* additive operator remains
inert (either side). A sign with no chunk to apply to is a parse error.
Spec: §3.2, §5.1.

## ADR-012: Bare `/` gets an implicit numerator of 1

**Context.** Edge case surfaced by the desugaring: `a␣␣/ b` puts `/` at
the start of a chunk with no left operand.

**Decision.** QOL over strictness: a chunk opening with `/` reads as
`1 / …`, so `a␣␣/ b` = `a × (1/b)`.

**Alternatives.** Parse error ("`/` needs a left operand"): considered
the safer default, rejected in discussion as needless noise for a
harmless, readable intent.

**Consequences.** Reciprocal chains are writable without parens.
Spec: §5.1.

## ADR-013: Pattern matching up to AC for `+` and `*`

**Context.** Literal-tree matching makes half of algebra invisible to
patterns: `$x + 0 = $x` would not match `0 + a`.

**Decision.** Matching is up to commutativity/associativity for `+` and
`*`, with numeric-literal special cases (`0 + $x`, `1 * $x`).

**Consequences.** General AC matching is a known hard area; the engine
implements the practical subset first and tracks completeness limits in
DESIGN §19, with complete AC matching as a roadmap extension. Spec: §9.

## ADR-014: Fixpoint rewriting, deterministic, with step cap; rules normalize rules

**Context.** Rules should chain: a `lim` rule's output feeding a trig
identity enabling further simplification — the founding scenario.

**Decision.** All rules apply repeatedly until nothing changes
(deterministic, single result), with a step cap (~1000) whose breach is a
reported error — the safety net against oscillators like `$x = $x + 1`,
together with guards. When a rule is defined, its LHS and RHS are first
normalized through the existing rule set, so rule A can feed rule B even
when A was defined after B — insertion is order-insensitive for chains.

**Alternatives.** Keeping result *sets* from all matching rules (true
branching): deferred with proof search — it changes the output contract
and explodes combinatorially. One-pass application: rejected — chains
are the point.

**Consequences.** The base engine is deterministic; branch search is a
roadmap extension behind an output-contract extension. Spec: §9.

## ADR-015: Multi-letter variables with `_` subscripts; reserved words excluded

**Context.** The first draft restricted variables to single letters so
`2a6` could lex as `2*a*6`. Review rejected that as a severe limitation.

**Decision.** Variables are maximal ASCII letter runs, optionally with a
`_`-subscript enumeration (`x`, `force`, `m_1`, `matrix_10`). Digits are
only valid after `_`, so `2a6` = `2*a*6` still holds and `a6` is not a
variable. Function names, keywords, and set names are reserved (exact,
case-sensitive match); every other letter run is a variable.

**Consequences.** `ab` is one variable — juxtaposition of *different*
variables now needs a space or `*`. That is the accepted price of
multi-letter names. Unknown multi-letter identifiers are no longer an
error class. Spec: §3.4.

## ADR-016: Includes are idempotent by tracking, not cycle-error

**Context.** The first draft made include cycles an error. Review: just
remember what has been loaded.

**Decision.** Each include records resolved absolute paths; re-including
an already-loaded file (including via a cycle) is a **no-op**. `clear`
also clears the tracking so a cleared session can deliberately re-load
the same files.

**Consequences.** The exit-code table loses the cycle error. Spec: §4, §12.

## ADR-017: REPL = batch with an internal header; QOL commands

**Context.** The REPL must not grow its own semantics — it is a wrapper.

**Decision.** The REPL keeps an internal header (the accumulated store),
exposes only the prompt, and processes each line exactly as batch would
(`internal header + new statement`). QOL commands manage the header:
`include <glob>`, `definitions` / `definitions <symbol>`, `clear` /
`clear <symbol>` (clears only that symbol's rules), `save <path>` (writes
the store in round-trippable form; appends if the file has content).

**Consequences.** Round-tripping (ADR-018) makes `save` trivial — a
saved session is stdout replayed as a header. Spec: §14.

## ADR-018: Output is round-trippable by contract

**Context.** What exactly does batch print, and can a session resume?

**Decision.** The full store is printed to stdout, each item as a
statement that **must parse back in as a header** and produce the same
store. The renderer emits minimal parentheses per the precedence rules
and explicit spacing (double spaces where chunk multiplication is
intended).

**Consequences.** Every printed line is a free parser test; session
save/load reduces to file I/O; renderer spacing fidelity is tracked as
an implementation-time open question (§19). Spec: §13.

## ADR-019: Numbers — maximal digit runs, no scientific notation

**Context.** How should digit sequences lex now that variables are letter
runs (ADR-015)?

**Decision.** A maximal digit run is one number (`26` is twenty-six);
digit/letter adjacency is multiplication (`2a6` = `2*a*6`, `2 6 a` the
same tree); decimals stay inside the number (`2.5a` = `2.5 * a`); `1e5`
is `1 * e * 5` (`e` is a variable); scientific notation is written
`10^5`. `^` binds the atom: `2a^2` = `2 * (a^2)`. Paren juxtaposition
multiplies: `(a + 1)2`.

**Consequences.** No `e` ambiguity exceptions to implement. Spec: §3.3.

## ADR-020: Architecture — core library, batch primary, REPL wrapper

**Context.** How do the two frontends relate?

**Decision.** `liacas-core` (lexer, parser, store, engine, solver slot,
renderer) is the system; the batch frontend (stdin header+prompt →
stdout store, errors to stderr with exit codes) is the primary interface,
"a library that behaves like a CLI"; the REPL is a wrapper adding QOL
only. The solver is one `solve()` interface with staged capability
(ADR-006), built across milestones M5–M10.

**Consequences.** Every feature is testable through batch alone; the
REPL is thin enough to rewrite without touching semantics. Spec: §15.
