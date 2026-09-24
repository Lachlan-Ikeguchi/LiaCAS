# LiaCAS — Roadmap

The build plan for the system specified in [`docs/DESIGN.md`](docs/DESIGN.md).
Each milestone is a self-contained unit of work that delivers a working,
testable LiaCAS at a strictly larger capability than the one before it, in
dependency order. A milestone is done when its acceptance checks pass; the
final milestone delivers the complete design.

Rationale for individual design choices lives in
[`docs/DECISIONS.md`](docs/DECISIONS.md).

---

## M1 — Lexing and the expression parser

**Build.** The whitespace-aware lexer (SS/DS tagging, maximal digit runs,
letter-run variables with `_` subscripts, reserved words, `\commands` ending
at their first non-letter, `->`, relations) and the precedence-climbing
parser implementing §5's hierarchy: relations → summands → chunks (DS) →
factors (`/`, left-assoc) → numerators (SS products, optional prefix sign) →
terms (`^`, right-assoc) → atoms. Including the sign-spacing rules (§3.2) and
bare-`/` implicit numerator 1.

**Acceptance.**
- Every tree in §3.2/§5.1's tables parses as specified (`r␣␣b / 2 a` →
  `r × (b/(2a))`, `\pm b / 2 a` → `(±b)/(2a)`, `\pm␣␣b / 2 a` →
  `±(b/(2a))`, bare `/` → `1/…`).
- The bracket desugaring (§5.1) runs as a test oracle: for a corpus of
  expressions, desugared-parse trees and native parse trees are identical.
- Parse errors report line/column; reserved words used as variables are
  rejected.

## M2 — The renderer and round-tripping

**Build.** The inverse of M1: AST → round-trippable ASCII (§13), minimal
parentheses per §5 precedence, explicit DS where chunk multiplication is
intended, `\pm` printed as `\pm`.

**Acceptance.**
- **Round-trip property:** for every AST the parser produces, render →
  re-parse yields the identical tree. This property becomes a standing
  fuzz test for the rest of the project.
- All §16 worked traces render exactly as printed in the design document.

## M3 — The rule store

**Build.** The unified store (§2): rules keyed by LHS (symbol definitions
and pattern rules are one concept), `:=` clear / `=` append, assumptions,
constraints, the set registry (`NATURAL` ∋ 0, `INTEGER`, `RATIONAL`,
`REAL`, `COMPLEX`, `PRIME`, `BOOLEAN`), and statement classification (§4).
`definitions`/`definitions <symbol>`, `clear`/`clear <symbol>` operate on
it (§14).

**Acceptance.**
- `x := e` then `x = f` holds both as a conjunction; `x := g` resets.
- Same semantics for patterns keyed by LHS; duplicate `=` LHS appends.
- Contradiction detection between ground values: stderr + reject statement
  (§12); exit codes 0/1/2/3 in batch.

## M4 — The pattern matcher and fixpoint rewriter

**Build.** Matching with `$` metavariables binding any subexpression
consistently; matching up to AC for `+`/`*` with numeric-literal special
cases; `where` guards with fail-closed verification against the assumption
store; fixpoint application with the step cap; rule normalization at
definition time (§9, §10).

**Acceptance.**
- The §9 chaining trace converges in three passes:
  `lim(t -> 0, sin(t)/t) * (sin(a)^2 + cos(a)^2)` → `1`.
- `$x/$x = 1 where $x != 0` does not fire on `a/a` without an assumption,
  fires with `a != 0` assumed, fires on `5/5` (§16 trace 3).
- Guards referencing unbound metavariables are definition-time errors;
  the step cap reports rather than loops (`$x = $x + 1`).

## M5 — Solver: substitution and linear isolation

**Build.** The `solve(equation, store) -> bindings | unsolved` interface
with its first capacity: ground substitution and single-symbol linear
isolation (§7.1). Solved bindings insert as definitions and propagate;
unsolved equations record as constraints and are re-attempted on store
changes.

**Acceptance.**
- §16 trace 2: header `x := b + 1`, prompt `x = 24` → `b := 23`, `x = 24`.
- `b + 1 = 25` solves; `b + c = 25` records as a constraint, no error.
- Propagation rewrites the whole store: the quadratic-formula trace
  (§16 trace 1) substitutes `b := 24` into every definition.

## M6 — Batch frontend

**Build.** The stdin protocol: header, `===== END HEADER =====` separator,
prompt; per-statement processing per §11; full-store round-trippable output
to stdout, errors to stderr with exit codes (§12, §13, §14). `include` with
glob expansion, resolved-path idempotent loading, relative-to-includer
paths (§4).

**Acceptance.**
- The §16 traces pass end-to-end via stdin, byte-exact on stdout.
- Include of an included file is a no-op; a missing include file is exit 3.
- Every batch output re-parses as a header and reconstructs the same store.

## M7 — REPL wrapper

**Build.** The internal-header model (§14): the REPL exposes only the
prompt, processes each line as batch (`internal header + statement`), and
grows the header from the engine's own output. QOL commands:
`include <glob>`, `definitions`/`definitions <symbol>`,
`clear`/`clear <symbol>`, `save <path>` (append if the target has
content); whitespace after `\commands` carries its full count uniformly
with batch (§3.1).

**Acceptance.**
- Every batch acceptance check passes through the REPL line-by-line.
- `save` output is a valid `include` target and batch header; a saved
  session resumes identically.
- The REPL adds no semantics: its acceptance suite is a subset of M6's,
  driven line-at-a-time.

## M8 — Renderer fidelity and full-store consistency

**Build.** Pin the open renderer questions (§19): exact DS-vs-parens
emission rules; expansion agreement for multi-definition symbols;
store-wide consistency checking grown from the M5 contradiction checks.

**Acceptance.**
- The round-trip fuzz corpus extends over every store compartment
  (definitions, rules with guards, assumptions, constraints).
- Multi-definition disagreement reports the conflicting pair (§19.3
  resolution decided at this milestone).

## M9 — Solver: polynomial solving

**Build.** Degree-ordered polynomial equations in one symbol, extending the
same `solve()` interface: quadratics with `±`-branch solutions, higher
degrees by factoring over the store's rules and assumptions.
`±`-branch selection against definitions (§7.1: `x = 3` vs. the quadratic
formula).

**Acceptance.**
- `x^2 + 3 x + 2 = 0` yields both bindings; each branch is checked against
  the store and contradictions reject per §12.
- The quadratic formula definition + `x = 3` selects a branch.
- All prior acceptance checks still pass (strict capability extension).

## M10 — Solver: systems

**Build.** Simultaneous linear systems, then nonlinear systems via
substitution between equations. Constraint re-attempting becomes
solver-driven across whole systems (§7.1).

**Acceptance.**
- `x + y = 3; x - y = 1` solves as a binding conjunction.
- Previously recorded constraints resolve when the store makes them
  solvable (an M5-recorded `b + c = 25` with `c = 1` known later solves).
- All prior acceptance checks still pass.

## Beyond M10 (design extensions, specified as they are adopted)

The complete design (§DESIGN.md) fixes interfaces so these extend without
redesign; each gets its own milestone when scheduled:

- **Complete AC matching** (§19.2): nested and mixed-literal cases beyond
  flat sums/products.
- **Proof/branch search**: applying all matching rules and keeping result
  *sets*, with the output-contract extension (§9).
- **Bidirectional rule search** (§9 directionality).
- **Assumption propagation**: deriving new assumptions from old (§8).
- **Richer guard predicate library** (§10).
