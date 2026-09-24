# LiaCAS — Design Document

Status: living document (v0 draft). This is the blueprint that implementation
work is built against. Decisions are recorded in §18; anything genuinely
unsettled lives in §19.

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

The engine holds one store with four compartments:

| Compartment | Written as | Meaning |
|---|---|---|
| **Definitions** | `x := e` (clear + define), `x = e` (append) | The symbol `x` is defined by a *conjunction* of expressions: every listed expression must hold for `x`. |
| **Rewrite rules** | `pattern = replacement [where guards]` | One-directional substitution templates used to simplify expressions. |
| **Assumptions** | `r > 10`, `n in INTEGER` | Context-only assertions. Consulted by guards (and later by the solver); never substituted into definitions. |
| **Constraints** | unsolved equations, e.g. `b + 1 = 25` when the solver cannot isolate a symbol | Recorded facts awaiting a future solver. Listed by `definitions`, replayed in output, but not acted on in v1. |

Uniformity rule: patterns use the same `:=` / `=` semantics as symbols — `:=`
clears all existing rules with the same LHS, `=` appends a rule to that list.
There is exactly one definition-store concept in the system.

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

**Command termination:** one space following a `\command` is consumed as the
terminator (TeX behaviour). `\pm  b` therefore reads as `\pm b`.

### 3.2 Whitespace as an operator

Space is significant. Three distinct roles:

| Level | Token | Meaning |
|---|---|---|
| 1 (loosest) | `=`, `!=`, `<`, `<=`, `>`, `>=`, `in` | relations |
| 2 | `+`, `-`, `\pm` | additive |
| 3 | **double space** | chunk multiplication |
| 4 | `/` | fraction; the denominator swallows the following **single-space** product |
| 5 | single space, juxtaposition, `*` | factor multiplication |
| 6 | `^` | power (right-associative) |
| 7 | atoms | numbers, variables, `( )`, function calls, `lim(...)` |

Derived rules:

- **Denominator swallow.** `a / b c` means `a / (b*c)`. A **double space**
  opts out: `a / b  c` means `(a/b) * c` — the double space ends the
  denominator. Double space is the escape hatch; single space is the default
  glue.
- **Inert double space before additive operators.** In `thing  + term2` the
  double space before the binary `+` is plain whitespace, *not* chunk
  multiplication. (Otherwise every aligned formula would multiply.) A double
  space only multiplies between two operands.
- **`/` is left-associative:** `a / b / c` = `(a/b)/c`. Continued fractions
  need parentheses.
- **`*` sits at level 5** with single space, so `a / b * c` = `a/(b*c)`.
  Consistent with "the denominator swallows the factor product", but different
  from most languages — documented on purpose.
- **The denominator stops at:** end of chunk, a binary `+`/`-`/`\pm`, a
  relation, `)`, or end of input. It does **not** stop at `^`: `a / b^2` =
  `a/(b^2)`.

Worked example (double spaces shown as `␣␣` for legibility only — in real
input they are two literal spaces):

```
term␣␣numerator / (variable + constant) thing␣␠+ term2
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
- **No scientific notation.** `1e5` is a parse error (`e` is a variable);
  write `10^5`.
- `2a^2` = `2 * (a^2)` since `^` binds the atom.

### 3.4 Identifiers and reserved words

- Variables are **single ASCII letters** (`a`–`z`, `A`–`Z`) or Greek via
  `\alpha` etc. This is what makes `2a6` splittable.
- Multi-letter sequences are **reserved words only**: `sqrt sin cos tan asin
  acos atan log ln exp abs lim where in include definitions clear`. Case is
  significant.
- An unknown multi-letter sequence is a **parse error**, never a silent
  product of single letters.

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

```
file        := statement { newline statement } ;

statement   := definition | assumption | meta ;

definition  := expr ":=" expr [ where_clause ]      -- clear + define
             | expr "="  expr [ where_clause ] ;    -- append (see §6–§9)

assumption  := expr relop expr                      -- relop: != < <= > >= in
             | expr "in" SETNAME ;

meta        := "include" glob
             | "definitions"
             | "clear" ;

where_clause:= "where" guard { ";" guard } ;

guard       := expr relop expr ;
```

A `\`-command variable (`\alpha`) is an `expr` atom.

**Statement classification** (how the engine reads `expr = expr`):

1. LHS contains `$` metavariables → **rewrite rule** (§9).
2. LHS is a single symbol (no `$`) → **definition append**; if the RHS is
   ground (fully numeric / already-known), it is also a **fact** that
   substitutes everywhere (§7).
3. LHS is compound (no `$`) → **equation fact**; hand it to the solver (§7).
4. Relation other than `=`, or set membership → **assumption** (§8).

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
file-based includes and to the current working directory in the REPL. Nested
includes are allowed; **include cycles are an error**.

---

## 5. Expression grammar and precedence

```
expr        := relation ;
relation    := summand { relop summand } ;
summand     := chunk { ("+" | "-" | "\pm") chunk } ;
chunk       := factor { "  " factor } ;                    -- double space
factor      := numerator { "/" numerator } ;               -- left-assoc
numerator   := term { (" " | "*") term } ;                 -- single-space product
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

The same semantics apply to rewrite rules, keyed by LHS pattern: `p := r`
clears all rules whose LHS equals `p`; `p = r` appends.

---

## 7. Facts and equations

The fact language is **equations**, compound LHS included:

```
b = 24          -- ground fact: substitute 24 for b everywhere
b + 1 = 25      -- equation: solve for b
x = 24          -- both a definition append and a fact
```

**v1 propagation pipeline** for each equation:

1. Substitute known ground values into both sides.
2. Simplify both sides via rewrite rules (§9).
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
r^x = 1 where x in COMPLEX; r > 10        -- as a rule's guards, see §10
```

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
- `x = 24` in a prompt is a fact **and** a definition append; `x in INTEGER`
  is always only an assumption. Relational statements (`>`, `>=`, …) are
  always assumptions.

---

## 9. Rewrite rules (patterns)

A rewrite rule is a definition whose LHS contains `$` metavariables:

```
sin($x)^2 + cos($x)^2 = 1
1 * $x = $x
lim($x -> 0, sin($x)/$x) = 1
r^x = 1 where x in COMPLEX; r > 10
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
r^x = 1 where x in COMPLEX; r > 10
$x/$x = 1 where $x != 0
```

- `where` introduces a `;`-separated conjunction of conditions; **all** must
  hold for the rule to fire.
- Conditions are relations (`!=`, `<`, `<=`, `>`, `>=`, `=`, `in`).
- **Fail-closed verification:** a guard passes only if the engine can *prove*
  it from the store (bound numeric literals, assumed memberships, recorded
  ground values). Unverifiable ⇒ the rule does not fire. Guards never guess.
- Guards can reference bound metavariables (`$x != 0`, `$n > 1`) and
  absolute symbols (`r > 10`, resolved against the assumption store).

---

## 11. Engine pipeline (v1)

Per statement, in order:

1. **Parse.** Errors → stderr, statement rejected, continue (batch) or
   re-prompt (REPL).
2. **Classify** (§4): rule / definition / equation / assumption / meta.
3. **Rules:** normalize LHS+RHS through the existing rules; insert
   (append for `=`, clear-then-insert for `:=`).
4. **Assumptions:** insert into the assumption store.
5. **Equations:** substitute → simplify → linear-isolate (§7). Solved:
   append definition and propagate the new ground value through the whole
   store. Unsolved: record as constraint.
6. **Fixpoint rewrite** of every definition, rule, and constraint.
7. **Contradiction check** (§12).

---

## 12. Contradictions and errors

- **Contradictions are detected and reported to stderr; the offending
  statement is rejected and the store is left untouched.** Example:
  `x = 2` followed by `x = 3` → stderr message, `x = 3` not stored.
- Parse errors: stderr with line/column, statement rejected.
- Unknown multi-letter identifier, unbound `$` var on a RHS, include cycle,
  missing include file, fixpoint step cap exceeded: all errors, stderr,
  non-zero exit in batch mode.
- v1 detects contradictions between ground values; full consistency
  checking across the store is future work (§17).

Exit codes (batch): `0` success, `1` parse error, `2` contradiction,
`3` runtime error (missing include, step cap, cycle).

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

Same engine, line at a time, with QOL commands:

| Command | Effect |
|---|---|
| `include <glob>` | Load statements from `.liaheader` files (§4). |
| `definitions` | List the current store: definitions, rules, assumptions, constraints. |
| `clear` | Remove everything — definitions, rules, assumptions, constraints. Blank slate. |

The REPL adds **no evaluation semantics**. Everything it can do, batch can
do; the REPL only wraps the loop with convenience. (Further QOL — history,
multi-line editing, session save via stdout capture — is frontend work that
never touches the engine.)

---

## 15. Architecture

```
liacas-core (library)
├── lexer        whitespace-aware (0/1 vs 2+ spaces), \commands, numbers
├── parser       precedence hierarchy (§5) -> AST
├── store        definitions (:=/=), rules, assumptions, constraints, sets
├── engine       substitute -> solve/implicate -> rewrite to fixpoint (§11)
├── solver       staged: v1 substitution + linear isolation;
│                full solving plugs into the same interface later
└── render       AST -> round-trippable ASCII (§13)

frontends
├── batch (default): stdin header+prompt -> stdout store, errors -> stderr
└── repl (-i):        same engine + include / definitions / clear
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

**Trace 3 — guarded rule:**

```
Header:  x/$x = 1 where $x != 0          (rejected: see note)
```

Correct form — `$` vars must bind, so the rule is:

```
         $x/$x = 1 where $x != 0
Prompt:  a/a
Output:  1                                       (guard `a != 0` unverifiable?
                                                 then the rule does NOT fire;
                                                 with `a in NONZERO` assumed
                                                 it fires and yields 1)
```

**Trace 4 — chained rewriting:** see §9.

---

## 17. Roadmap

**v1 (this document's scope):**

1. Whitespace-aware lexer; expression parser with §5 precedence.
2. Store with `:=`/`=` clear/append semantics (symbols and patterns).
3. Substitution + linear-isolation solver slot.
4. Pattern matcher (AC for `+`/`*`, consistent `$` binding) + guards +
   fixpoint rewriter with step cap + rule normalization.
5. Batch frontend: header/prompt protocol, `include` with globs and cycle
   detection, round-trippable renderer.
6. REPL wrapper: `include`, `definitions`, `clear`.

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
| 10 | Multi-letter identifiers | Reserved words only; unknown → parse error (§3.4). |
| 11 | Whitespace hierarchy | Double space = chunk multiplication; `/` swallows single-space products; `*` at single-space level; `/` left-assoc; `^` right-assoc; double space inert before `+`/`-` (§3.2). |
| 12 | Numbers | Maximal digit runs; juxtaposition = multiplication (`2a6` = `2*a*6`); no scientific notation (§3.3). |
| 13 | ASCII policy | `\commands` only for non-typable symbols; `->`, `>=`, `<=`, `!=` ASCII (§3.1). |
| 14 | Sets | `NATURAL` (contains 0), `INTEGER`, `RATIONAL`, `REAL`, `COMPLEX`, `PRIME`, `BOOLEAN` (§8). |
| 15 | Statement kinds | Definitions, rewrite rules, assumptions, constraints (§2). |
| 16 | Architecture | Core library + batch (primary) + REPL wrapper with no extra semantics (§1, §15). |
| 17 | Output | Full store, round-trippable, stdout; errors stderr + exit codes (§12, §13). |
| 18 | REPL QOL | `include`, `definitions`, `clear` (§14). |

## 19. Open questions

1. **`clear` scope** — currently specified as full store reset (definitions,
   rules, assumptions, constraints). Alternative: definitions only, leaving
   assumptions intact. Default stands until someone needs the alternative.
2. **`NONZERO`-style guard sets** — trace 3 shows guards like `$x != 0`
   failing closed without a positive assumption. Should v1 ship a
   `NONZERO` set (or `\where $x in REAL \ {0}`) to make such rules usable?
3. **REPL persistence** — should the REPL grow an explicit `save` command,
   or is "redirect output to a `.liaheader`" sufficient given the
   round-trip contract?
4. **Renderer spacing fidelity** — exact rules for when the renderer emits
   double spaces vs parentheses to guarantee round-tripping need to be
   pinned during implementation (§13).
5. **AC-matching completeness** — which practical AC cases beyond flat
   sums/products (nested, mixed literals) v1 must handle (§9).
