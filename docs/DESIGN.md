# LiaCAS — Design Document

Status: living document (v0 draft). This is the blueprint that implementation
work is built against. The **reasoning behind each decision** — context,
alternatives considered, and why — is recorded in
[`DECISIONS.md`](DECISIONS.md) (ADR log). Anything genuinely unsettled lives
in §19.

---

## 1. Goals and non-goals

**Goal.** LiaCAS is a Computer Algebra System that behaves like a library with
two thin frontends:

- **Batch (primary):** read a *header* (context) and a *prompt* (new
  information) from stdin; print the resulting definitions to stdout; print
  errors to stderr.
- **REPL (wrapper):** the same engine packaged with quality-of-life features.
  The REPL adds no evaluation semantics of its own.

**Non-goals for v1** (planned features, deliberately deferred — see §17):

- General equation solving (quadratics, systems, `±`-branch selection).
- Branch/proof search over multiple candidate rewrite results.
- Assumption *propagation* (deriving new assumptions from old).

Everything else in this document is in scope for v1.

---

## 2. Concepts: the store

The engine holds one store with three compartments:

| Compartment | Written as | Meaning |
|---|---|---|
| **Rules** | `x := e` / `x = e` / `pattern = replacement [where guards]` | One-directional rewrite templates in a single list keyed by LHS. A rule whose LHS is a literal symbol is a **definition** of that symbol; a rule whose LHS contains `$` metavariables is a **pattern rule**. |
| **Assumptions** | `r > 10`, `n in INTEGER` | Context-only assertions. Consulted by guards (and later by the solver); never rewritten into. |
| **Constraints** | unsolved equations, e.g. `b + 1 = 25` when the solver cannot isolate a symbol | Recorded facts awaiting a future solver. Listed by `definitions`, replayed in output, but not acted on in v1. |

**Definitions are not separate from rules — a definition *is* a rule.** `:=`
clears all existing rules with that LHS and inserts one; `=` appends.
Because a definition is a rule, it fires during rewriting: any expression
containing `x` expands `x` to its defined expression. Ground-value
substitution (§7) is the same mechanism — substituting `b := 24` everywhere
is rewriting with the rule `b → 24`.

A symbol with several definitions (repeated `=`) holds a *conjunction*:
every defining expression must hold for the symbol. During expansion the
engine applies each definition and requires the results to agree after
simplification; disagreement is a contradiction (§12).

---

## 3. Surface syntax

### 3.1 ASCII conventions

Input is ASCII. LaTeX-style `\commands` are used **only** where ASCII has no
natural form:

| ASCII form | Written as | Notes |
|---|---|---|
| `±` | `\pm` | first-class operator |
| `→` | `->` | used in `lim` approaches |
| `≥`, `≤`, `≠` | `>=`, `<=`, `!=` | |
| `∞` | `\infty` | |
| `α`, `β`, … | `\alpha`, `\beta`, … | Greek variable names |

Everything typable stays ASCII: `sqrt`, `sin`, `cos`, `tan`, `log`, `exp`,
`lim`, `abs`.

**Command termination is free (option 2).** A `\command` name ends at its
first non-letter character (matched against the command table) — no
semantic whitespace is ever consumed as a terminator. Spaces following a
`\command` carry their full count and mean exactly what the same number of
spaces means anywhere else. This holds in batch files and the REPL alike:
`\pm 4` is plus-or-minus 4, and `\pm  b / 2 a` (double space) is
`\pm (b/(2a))` (see §3.2).

### 3.2 Whitespace as an operator

Space is significant. Three distinct roles:

| Level | Token | Meaning |
|---|---|---|
| 1 (loosest) | `=`, `!=`, `<`, `<=`, `>`, `>=`, `in` | relations |
| 2 | `+`, `-`, `\pm` | additive |
| 3 | **double space** | chunk multiplication |
| 4 | `/` | fraction; **both sides** are single-space products — the denominator swallows the following product, the numerator the preceding one |
| 5 | single space, juxtaposition, `*` | factor multiplication |
| 6 | `^` | power (right-associative) |
| 7 | atoms | numbers, variables, `( )`, function calls, `lim(...)` |

Derived rules:

- **Denominator swallow.** `a / b c` means `a / (b*c)`. A **double space**
  opts out: `a / b  c` means `(a/b) * c` — the double space ends the
  denominator. Double space is the escape hatch; single space is the default
  glue.
- **Numerator swallow.** Symmetrically, the numerator is a single-space
  product of the terms before the `/`: `a b / c` = `(a*b)/c`.
- **Inert double space adjacent to additive operators.** In `thing  + term2`
  the double space before the binary `+` is plain whitespace, *not* chunk
  multiplication. (Otherwise every aligned formula would multiply.) The same
  holds after a binary additive operator: `a \pm  b` is just `a \pm b`.
  A double space multiplies only **between two operands** — with one
  exception, below.
- **Sign spacing.** In **sign position** (start of an expression, summand, or
  chunk), spacing after a prefix sign (`-`, `+`, `\pm`) chooses the sign's
  scope — more space, looser binding, mirroring spacing between operands:
  - **Single space** — the sign binds the **first factor** of the following
    numerator: `\pm b / 2 a` = `(\pm b)/(2 a)`; `\pm b c / 2 a` =
    `((\pm b) c)/(2 a)`.
  - **Double space** — the sign applies to the **whole next chunk**, as a
    unit, fraction and all: `\pm  b / 2 a` = `\pm (b/(2 a))`. The sign's
    scope is exactly the next chunk; a further double space ends it:
    `\pm  b / 2 a  c` = `(\pm (b/(2 a))) * c`.
  Both trees have the same value (sign distributes over `/` and `*`), so
  this is tree-shape control, never a correctness question. The engine does
  not normalize one into the other; conversion is a user rewrite rule.
  The same rules hold for `-` and `+` in sign position. A sign followed by
  end of input or a binary operator (`\pm  + 4`) is a parse error.
- **`/` is left-associative:** `a / b / c` = `(a/b)/c`. Continued fractions
  need parentheses.
- **`*` sits at level 5** with single space, so `a / b * c` = `a/(b*c)`.
  Consistent with "the denominator swallows the factor product", but different
  from most languages — documented on purpose.
- **Numerator and denominator stop at:** end of chunk (a double space), a
  binary `+`/`-`/`\pm`, a relation, `)`, or end of input. Neither stops at
  `^`: `a / b^2` = `a/(b^2)` and `a b^2 / c` = `(a*b^2)/c`.

Worked example (double spaces shown as `␣␣` for legibility only — in real
input they are two literal spaces):

```
term␣␣numerator / (variable + constant) thing␣␣+ term2
```

parses as:

```
term * numerator / ((variable + constant) * thing) + term2
```

because the additive split happens first (`+ term2`), the double space then
splits `term` from the fraction chunk, and inside the chunk the denominator
swallows the single-space product `(variable + constant) * thing`.

The quadratic formula needs no parentheses around the denominator:

```
x := (-b \pm sqrt(b^2 + 4 a c)) / 2 a
```

Here `2 a` is a single-space product, so the denominator is `2a`.

### 3.3 Numbers and juxtaposition

- A maximal digit run is **one number**: `26` is twenty-six, not `2*6`.
- Digit/letter adjacency is a multiplication boundary: `2a6` = `2 * a * 6`,
  and `2 6 a` = `2 * 6 * a` (same tree).
- `a2b` = `a * 2 * b`; `(a + 1)2` and `2(a + 1)` are also multiplications.
- Decimal point stays inside the number: `2.5a` = `2.5 * a`.
- **No scientific notation.** `1e5` parses as `1 * e * 5` (letter runs are
  variables, so `e` is the variable `e`); write `10^5`.
- `2a^2` = `2 * (a^2)` since `^` binds the atom.

### 3.4 Identifiers and reserved words

- Variables are ASCII **letter runs**, optionally with a subscript
  enumeration introduced by `_`: `x`, `force`, `m`, `m_1`, `m_2`,
  `matrix_10`. Greek letters are written `\alpha` etc. Case is significant.
- **Digits only after `_`.** A maximal digit run is one number and
  digit/letter adjacency is a multiplication boundary, so `2a6` = `2 * a * 6`
  still holds and `a6` is not a valid variable name.
- A maximal letter run lexes as **one identifier**: `ab` is the variable
  `ab`; the product needs `a b` or `a*b`. This is the price of multi-letter
  names — juxtaposition of *different* variables needs a space or `*`.
- **Reserved words cannot be variables**: the function names (`sqrt sin cos
  tan asin acos atan log ln exp abs lim`), the keywords (`where in include
  definitions clear save`), and the set names (§8), exact match,
  case-sensitive. Every other letter run is a valid variable name.

### 3.5 Functions and `lim`

Functions take parenthesized arguments: `sqrt(x)`, `sin(x + y)`. `lim` is a
function with two comma-separated parameters — the approach (written with
`->`) and the function acted upon:

```
lim($x -> 0, sin($x)/$x) = 1
```

---

## 4. Statement grammar

Statements are one per line (newlines terminate; blank lines ignored).

The grammar is written EBNF-style; `"  "` below means **two literal space
characters**. `{ }` means zero-or-more, `[ ]` optional, `|` alternatives.

```
file        := statement { newline statement } ;

statement   := rule | assumption | meta ;

rule        := expr ":=" expr [ where_clause ]      -- clear rules with this LHS, insert
             | expr "="  expr [ where_clause ] ;    -- append (see §6–§9)

assumption  := expr relop expr                      -- relop: != < <= > >= in
             ;

meta        := "include" glob
             | "definitions" [ symbol ]
             | "clear" [ symbol ]
             | "save" path ;

where_clause:= "where" guard { ";" guard } ;

guard       := expr relop expr ;
```

`in` is a reserved word appearing as a relation at the relation level of the
expression grammar; membership statements are therefore just `assumption`
with `relop = in`. A `\`-command variable (`\alpha`) is an `expr` atom.

**Statement classification** (how the engine reads `expr = expr`):

1. LHS contains `$` metavariables → **pattern rule** (§9).
2. LHS is a symbol (no `$`) → **definition** (a rule keyed by that symbol,
   §2, §6); if the RHS is ground (fully numeric / already-known), it is also
   a **fact** that substitutes everywhere (§7).
3. LHS is compound (no `$`) → **equation fact**; hand it to the solver (§7).
4. Relation other than `=`, or set membership → **assumption** (§8).
5. `where` on a rule whose LHS has no `$` metavariables is a parse error
   (guards can only constrain metavariable bindings, §10).

Note the special case at level 2: a rule whose LHS is a literal symbol is a
definition, and definitions expand during rewriting (§2).

### Batch protocol

```
<header statements>
===== END HEADER =====
<prompt statements>
```

The separator line is exactly `===== END HEADER =====`. Header and prompt are
both statement sequences; the header provides context, the prompt provides
new information. The engine processes header then prompt and prints the
resulting store (§13).

`include` inside a header (or the REPL) loads statements from files:

```
include /path/to/file/*.liaheader
```

Glob expansion is supported. Paths are relative to the including file for
file-based includes and to the current working directory in the REPL.
Nested includes are allowed. **Idempotent by tracking:** each include
records the files it has already loaded (by resolved absolute path) in the
session; re-including a file (including via a cycle back to an
already-loaded file) is a **no-op**, not an error. `clear` (§14) also clears
the loaded-file tracking, so a cleared session can deliberately re-load the
same files.

---

## 5. Expression grammar and precedence

```
expr        := relation ;
relation    := summand { relop summand } ;
summand     := chunk { ("+" | "-" | "\pm") chunk } ;
chunk       := factor { "  " factor } ;                    -- double space
factor      := numerator { "/" numerator } ;               -- left-assoc
numerator   := sign term { (" " | "*") term } ;            -- single-space product
sign        := "-" | "+" | "\pm" ;                      -- optional prefix sign
term        := atom [ "^" term ] ;                         -- right-assoc power
atom        := NUMBER | VARIABLE | "\command" | SETNAME
             | "(" expr ")" | FUNC "(" expr { "," expr } ")"
             | "lim" "(" expr "->" expr "," expr ")"
             | "$" METAVAR ;
relop       := "=" | "!=" | "<" | "<=" | ">" | ">=" | "in" ;
```

Notes:

- `relation` appears only where a relation is legal (statement level, inside
  guards, inside `where` clauses).
- `\pm` at the additive level keeps both branches: `x \pm 1` is a single
  expression that the renderer prints back as `\pm` (v1 does not branch on
  it; see §17).
- Unary minus: `-x` is a negation atom at the summand position; `a - b` is
  binary subtraction.
- A summand may open with a sign applied to its **whole first chunk** via
  a double space (`\pm  b / 2 a` = `\pm (b/(2 a))`), distinct from the
  `sign` inside `numerator` (§3.2).

### 5.1 Whitespace semantics: bracket desugaring

The formal meaning of §3.2's spacing rules is a desugaring pass over the
lexed token stream. Whitespace runs are tagged SS (single space, including
`*`) and DS (double space). Two bracket kinds are inserted, one per level:

- **Chunk brackets `[ ]`** (level 3): DS inserts `] [` between operands.
  An implicit `[` opens at the start of each summand, `]` at its end.
- **Fraction brackets `( )`** (level 4): each `/` inserts `) / (`. They are
  **contained within one chunk**: the numerator reaches back only to the
  nearest chunk boundary, the denominator extends forward only to the next
  one.

```
r␣␣b / 2 a     ->  [r] [ (b) / (2a) ]       ->  r * (b/(2a))
a / b␣␣thing    ->  [ (a)/(b) ] [thing]       ->  (a/b) * thing
a b / c        ->  [ (a b)/(c) ]            ->  (a*b)/c
```

Inertness rules: DS adjacent to a binary additive operator (either side) is
dropped. A chunk that consists solely of signs cannot stand alone: the sign
applies to the **whole next chunk** — `\pm␣␣b / 2 a` -> `[\pm] [(b)/(2a)]`
-> `\pm(b/(2a))` — and the sign's scope is exactly that one chunk (`\pm␣␣b / 2 a␣␣c` -> `(\pm(b/(2a))) * c`). A chunk opening with `/` has an
implicit numerator of `1`: `a␣␣/ b` -> `[a] [(1)/(b)]` -> `a * (1/b)`.

The **implementation** is a whitespace-aware precedence-climbing parser
whose recursion levels are these brackets; no token mutation happens at
runtime. The desugaring is kept as the testable specification: tests run
both paths and require identical trees.

---

## 6. Definitions: `:=` and `=`

- `x := e` — **clear** all previous definitions of `x`, then define `x` by
  `e`.
- `x = e` — **append** `e` to the definitions of `x`. The definition list is
  a conjunction: `x` must satisfy every expression in it.

```
x := b + 1
x = 24
```

The store now holds `x := b + 1; x = 24`, and the engine attempts to
reconcile them (§7).

Patterns use the same semantics, keyed by LHS expression: `p := r` clears
all rules whose LHS equals `p`; `p = r` appends. Definitions and patterns
are one concept — see §2.

---

## 7. Facts and equations

The fact language is **equations**, compound LHS included:

```
b = 24          -- ground fact: substitute 24 for b everywhere
b + 1 = 25      -- equation: solve for b
x = 24          -- both a definition insert (a rule) and a fact
```

**v1 propagation pipeline** for each equation:

1. Substitute known ground values into both sides.
2. Simplify both sides via rules (§9).
3. If one side is a single symbol, attempt **linear isolation** (v1's only
   solving): `b + 1 = 25` → `b := 24`.
4. If solved: append the definition, substitute the new ground value
   through every definition, rule, and constraint in the store, and rewrite
   to fixpoint.
5. If not solvable by linear isolation: record as a **constraint** (§2) and
   continue.

Example trace:

```
Header:   x := b + 1
Prompt:   x = 24
Effect:   x's defs = {b + 1, 24} -> isolate: b = 23
          substitute b=23: x's defs = {24, 24} -> dedupe
Output:   b := 23
          x = 24
```

**Full equation solving is a planned feature** (§17) but is not v1. The v1
solver interface is `solve(equation) -> solved-bindings | unsolved`, and
the future solver plugs into the same slot.

---

## 8. Assumptions, sets, membership

Standalone assumptions assert context without touching definitions:

```
n in INTEGER
r > 10
```

A rule's guards combine both kinds of condition (see §10).

Built-in set registry (uppercase names, reserved):

```
COMPLEX ⊇ REAL ⊇ RATIONAL ⊇ INTEGER ⊇ NATURAL
PRIME ⊂ NATURAL
BOOLEAN
```

- **0 is in `NATURAL`** (ISO 80000-2 convention).
- `in` appears in two places with the same grammar: as a standalone
  assumption and inside `where` guards.
- Assumptions are never substituted into definitions; they are consulted by
  guard verification and, later, by the full solver.
- `x = 24` in a prompt is a fact **and** a definition insert; `x in INTEGER`
  is always only an assumption. Relational statements (`>`, `>=`, …) are
  always assumptions.

---

## 9. Rewrite rules (patterns)

A rewrite rule is a rule whose LHS contains `$` metavariables:

```
sin($x)^2 + cos($x)^2 = 1
1 * $x = $x
lim($x -> 0, sin($x)/$x) = 1
$x^2 = $x * $x
$x/$x = 1 where $x != 0
```

Semantics:

- `$x` binds **any subexpression** (not just variables), consistently within
  one pattern: in `sin($x)/$x` both occurrences must bind the same thing.
  Pattern variables on the RHS must be bound on the LHS; otherwise the rule
  is rejected at definition time.
- **Matching is up to commutativity/associativity** for `+` and `*`, with
  numeric-literal special cases (`0 + $x`, `1 * $x`). Without this, half of
  algebra is invisible to patterns. (Full AC matching is a known hard area;
  v1 implements the practical subset and §19 tracks its limits.)
- **Guards** (§10) gate firing.
- **Rules normalize rules.** When a rule is defined, its LHS and RHS are
  first run through the existing rule set, so rule A can feed rule B even
  when A was defined after B. Insertion is therefore order-insensitive for
  chains.
- **Fixpoint application, deterministic, one result.** All rules are applied
  repeatedly until nothing changes, with a step cap (implementation constant,
  ~1000). Hitting the cap is an error reported to stderr — that, plus guards,
  is the safety net against oscillating rules like `$x = $x + 1`.
- **Directionality.** Rules fire LHS→RHS only. The reverse direction is a
  separate explicit rule. v1 never searches both directions automatically
  (that is proof search, §17).
- `:=` on a pattern clears all rules with that LHS; `=` appends. Appending
  several rules with the same LHS is how you express *alternative*
  simplification paths — they apply in definition order within the fixpoint
  loop.

Chaining example (the reason fixpoint + normalization matter):

```
Rules:  sin($x)^2 + cos($x)^2 = 1
        1 * $x = $x
        lim($x -> 0, sin($x)/$x) = 1

Expr:   lim(t -> 0, sin(t)/t) * (sin(a)^2 + cos(a)^2)
Pass 1: 1 * (sin(a)^2 + cos(a)^2)       (lim rule)
Pass 2: 1 * 1                           (Pythagoras)
Pass 3: 1                               (identity rule)
```

Where rules apply: to every expression in the store, after each fact lands,
and to prompt expressions before they are stored.

---

## 10. Guards

```
$x/$x = 1 where $x != 0
sqrt($x)^2 = $x where $x in REAL; $x >= 0
($x + $y)^2 = $x^2 + 2 $x $y + $y^2
```

- `where` introduces a `;`-separated conjunction of conditions; **all** must
  hold for the rule to fire.
- Conditions are relations (`!=`, `<`, `<=`, `>`, `>=`, `=`, `in`)
  comparing a bound metavariable or a literal symbol against an expression.
- **Fail-closed verification:** a guard passes only if the engine can *prove*
  it from the store (bound numeric literals, assumed memberships, recorded
  ground values). Unverifiable ⇒ the rule does not fire. Guards never guess.
  Example: `$x != 0` passes when the store knows `$x` bound a numeric
  literal other than 0, or when the symbol is assumed nonzero; it fails
  (rule skipped) otherwise.
- Guards reference bound metavariables (`$x != 0`, `$n > 1`) and absolute
  symbols (`r > 10`, resolved against the assumption store). A guard
  referencing an unbound metavariable is a definition-time error.

---

## 11. Engine pipeline (v1)

Per statement, in order:

1. **Parse.** Errors → stderr, statement rejected, continue (batch) or
   re-prompt (REPL).
2. **Classify** (§4): rule (definition or pattern) / equation /
   assumption / meta.
3. **Rules:** normalize LHS+RHS through the existing rules; insert
   (append for `=`, clear-then-insert for `:=`).
4. **Assumptions:** insert into the assumption store.
5. **Equations:** substitute → simplify → linear-isolate (§7). Solved:
   insert the resulting definition and propagate the new ground value
   through the whole store. Unsolved: record as constraint.
6. **Fixpoint rewrite** of every rule, assumption, and constraint.
7. **Contradiction check** (§12).

---

## 12. Contradictions and errors

- **Contradictions are detected and reported to stderr; the offending
  statement is rejected and the store is left untouched.** Example:
  `x = 2` followed by `x = 3` → stderr message, `x = 3` not stored.
- Parse errors: stderr with line/column, statement rejected.
- Reserved word used as a variable, unbound `$` var on a RHS, unbound
  metavariable in a guard, `where` on a `$`-free rule, missing include file,
  fixpoint step cap exceeded: all errors, stderr, non-zero exit in batch
  mode. (Include cycles are not errors — includes are idempotent, §4.)
- v1 detects contradictions between ground values; full consistency
  checking across the store is future work (§17).

Exit codes (batch): `0` success, `1` parse error, `2` contradiction,
`3` runtime error (missing include, step cap).

---

## 13. Output contract

- Batch prints the **full store** to stdout after processing: definitions,
  rules, assumptions, constraints — each as a round-trippable statement.
- **Round-trippable by contract:** every line the engine prints must parse
  back in as a header. This makes the output a free test corpus and makes
  session save/load trivial (a saved session is stdout replayed as a
  header).
- The renderer emits minimal parentheses according to §5 precedence and
  uses explicit spacing so the printed form re-parses to the same tree
  (double spaces printed where chunk multiplication is intended).
- Errors and diagnostics go to stderr, never stdout.

---

## 14. Frontends

### Batch (primary)

```
liacas < header_prompt_input
```

1. Read stdin: header statements, separator, prompt statements.
2. Process (§11).
3. Print store to stdout; errors to stderr with exit code (§12).

### REPL (`-i`)

Same engine, line at a time. **Model:** the REPL keeps an internal header
(the accumulated store), exposes only the prompt to the user, and on each
line runs batch-equivalent processing: `internal header + new statement`.
This is why the REPL has no semantics of its own — it *is* the batch
frontend run once per line, with the previous run's output prepended as
context.

QOL commands:

| Command | Effect |
|---|---|
| `include <glob>` | Load statements from `.liaheader` files (§4). |
| `definitions` | List the current store: definitions, rules, assumptions, constraints. |
| `definitions <symbol>` | List only the definitions (rules) keyed by `<symbol>`. |
| `clear` | Remove everything — definitions, rules, assumptions, constraints, and the include tracking (§4). Blank slate. |
| `clear <symbol>` | Remove only the rules keyed by `<symbol>`, leaving assumptions and other definitions intact. |
| `save <path>` | Write the internal header (the current store, in round-trippable form, §13) to `<path>`. If the file already exists and is non-empty, **append**; otherwise create/overwrite. The saved file is directly usable as an `include` target or a batch header. |

The REPL adds **no evaluation semantics**: every statement it accepts is
processed exactly as batch would process it. Its QOL commands manipulate
the internal header (list, clear, save, extend via `include`) — header
management, not evaluation. (Further QOL — history, multi-line editing —
is frontend work that never touches the engine.)

---

## 15. Architecture

```
liacas-core (library)
├── lexer        whitespace-aware (0/1 vs 2+ spaces), \commands, numbers
├── parser       precedence hierarchy (§5) -> AST
├── store        unified rules (:=/=, symbols and patterns), assumptions,
│                constraints, sets, include tracking
├── engine       substitute -> solve/implicate -> rewrite to fixpoint (§11)
├── solver       staged: v1 substitution + linear isolation;
│                full solving plugs into the same interface later
└── render       AST -> round-trippable ASCII (§13)

frontends
├── batch (default): stdin header+prompt -> stdout store, errors -> stderr
└── repl (-i):        same engine; internal header + include /
                     definitions / clear / save
```

---

## 16. Worked traces

**Trace 1 — ground fact propagation:**

```
Header:  x := (-b \pm sqrt(b^2 + 4 a c)) / 2 a
Prompt:  b = 24
Output:  b := 24
         x := (-24 \pm sqrt(576 + 4 a c)) / 2 a
```

(`b^2` → `576`, `\pm` kept symbolic; the denominator stays `2 a`.)

**Trace 2 — equation with isolation:**

```
Header:  x := b + 1
Prompt:  x = 24
Output:  b := 23
         x = 24
```

**Trace 3 — guarded rule, fail-closed:**

```
Header:  $x/$x = 1 where $x != 0
Prompt:  a/a
Output:  a/a          (guard `a != 0` unverifiable -> rule does NOT fire)
```

But with a positive assumption about `a`:

```
Header:  $x/$x = 1 where $x != 0
         a != 0
Prompt:  a/a
Output:  1             (guard `a != 0` proven from the assumption -> fires)
```

And the guard passes automatically for numeric literals other than 0:

```
Header:  $x/$x = 1 where $x != 0
Prompt:  5/5
Output:  1             (5 is a literal != 0 -> provable -> fires)
```

**Trace 4 — chained rewriting:** see §9.

---

## 17. Roadmap

**v1 (this document's scope):**

1. Whitespace-aware lexer; expression parser with §5 precedence.
2. Unified rule store (definitions and pattern rules, §2) with `:=`/`=`
   clear/append semantics.
3. Substitution + linear-isolation solver slot.
4. Pattern matcher (AC for `+`/`*`, consistent `$` binding) + guards +
   fixpoint rewriter with step cap + rule normalization.
5. Batch frontend: header/prompt protocol, `include` with globs and
   idempotent loading, round-trippable renderer.
6. REPL wrapper: internal-header model, `include`, `definitions`/
   `definitions <symbol>`, `clear`/`clear <symbol>`, `save`.

**Planned, later (same interfaces, bigger engines):**

- Full equation solving: quadratics, systems, `±` branch selection against
  definitions (e.g. `x = 3` against the quadratic formula).
- Branch/proof search: applying all matching rules and keeping result *sets*,
  with an output-contract extension.
- Bidirectional rule search.
- Assumption propagation and full store consistency checking.
- Complete AC matching (the general AC-match problem), richer guard
  predicate library.

---

## 18. Decisions log

A summary table; the full reasoning for each decision lives in
[`DECISIONS.md`](DECISIONS.md).

| # | Decision | Resolution |
|---|---|---|
| 1 | Implication depth | v1: substitution + single-symbol linear isolation. Full solving: future (§7, §17). |
| 2 | Contradictions | Detect, report to stderr, reject the statement (store untouched) (§12). |
| 3 | Fact language | Equations, compound LHS legal (§7). |
| 4 | Pattern variable scope | `$` binds any subexpression, consistently within a pattern (§9). |
| 5 | Pattern matching | Up to AC for `+` and `*`, numeric-literal special cases (§9). |
| 6 | Guards | `where` + `;`-separated conjunction, fail-closed verification (§10). |
| 7 | Pattern `:=`/`=` | Same clear/append semantics as symbols; `=` with same LHS appends (branching); `:=` replaces (§6, §9). |
| 8 | Rule interaction | Fixpoint application, deterministic, one result, step cap; rules normalize through existing rules at definition time (§9). |
| 9 | Function parameters | Explicit `$` only; no implicit pattern variables (§3.5, §9). |
| 10 | Identifiers | Multi-letter variables allowed (letter runs, `_` subscript enumeration like `m_1`); reserved words and digits-after-letter excluded (`2a6` = `2*a*6` still holds) (§3.4). |
| 11 | Whitespace hierarchy | Double space = chunk multiplication; `/` takes single-space products on both sides; `*` at single-space level; `/` left-assoc; `^` right-assoc; DS inert adjacent to binary additive operators; formal semantics = bracket desugaring (§3.2, §5.1). |
| 12 | Numbers | Maximal digit runs; juxtaposition = multiplication (`2a6` = `2*a*6`); no scientific notation (§3.3). |
| 13 | ASCII policy | `\commands` only for non-typable symbols; `->`, `>=`, `<=`, `!=` ASCII (§3.1). |
| 14 | Sets | `NATURAL` (contains 0), `INTEGER`, `RATIONAL`, `REAL`, `COMPLEX`, `PRIME`, `BOOLEAN` (§8). |
| 15 | Statement kinds | Rules (definitions + pattern rules unified), assumptions, constraints (§2). |
| 16 | Architecture | Core library + batch (primary) + REPL wrapper with no extra semantics (§1, §15). |
| 17 | Output | Full store, round-trippable, stdout; errors stderr + exit codes (§12, §13). |
| 18 | REPL QOL | `include`, `definitions`/`definitions <symbol>`, `clear`/`clear <symbol>`, `save <path>`; internal-header model (§14). |
| 19 | Includes | Idempotent via loaded-file tracking; re-include/cycle is a no-op; `clear` resets tracking (§4). |
| 20 | REPL whitespace | After a `\command`, typed spaces carry their full count (free terminator); no REPL/batch divergence (§3.1). |
| 21 | `/` symmetry | Both numerator and denominator are single-space products (§3.2). |
| 22 | Sign spacing | Prefix sign + SS binds the first factor of the numerator (`\pm b / 2 a` = `(±b)/(2a)`); prefix sign + DS applies to the whole next chunk only (`\pm  b / 2 a` = `±(b/(2a))`); values coincide, engine never normalizes between them (§3.2, §5.1). |
| 23 | Bare `/` | A chunk opening with `/` has implicit numerator 1: `a␣␣/ b` = `a * (1/b)` (§5.1). |

## 19. Open questions

1. **Renderer spacing fidelity** — exact rules for when the renderer emits
   double spaces vs parentheses to guarantee round-tripping need to be
   pinned during implementation (§13).
2. **AC-matching completeness** — which practical AC cases beyond flat
   sums/products (nested, mixed literals) v1 must handle (§9).
3. **Expansion strategy for multi-definition symbols** — when a symbol has
   several definitions (`x = e1` then `x = e2`), v1 requires the expanded
   results to agree after simplification. Whether disagreement should also
   *drive solving* (feed the disagreement equation to the solver, §7) instead
   of only erroring is an open refinement.
