# LiaCAS

LiaCAS is a Computer Algebra System, written in Zig.

- **Design document:** [`docs/DESIGN.md`](docs/DESIGN.md) — the blueprint
  implementation is built against. Syntax, semantics, decisions log, and
  worked traces all live there.
- **Status:** design phase. The engine described in the design document is
  not implemented yet; `src/` currently holds the Zig project scaffold.

## Usage

LiaCAS behaves like a library with two thin frontends.

### stdin-stdout (batch, primary)

Reads a *header* (context) and a *prompt* (new information) from stdin,
separated by the line `===== END HEADER =====`, processes them, and prints
the resulting definitions to stdout. Errors go to stderr.

```console
$ liacas <<'EOF'
x := (-b \pm sqrt(b^2 + 4 a c)) / 2 a
===== END HEADER =====
b = 24
EOF
b := 24
x := (-24 \pm sqrt(576 + 4 a c)) / 2 a
```

Headers can pull in definitions from files:

```
include /path/to/file/*.liaheader
```

### Interactive (REPL)

Command line switch `-i`. The same engine wrapped with quality-of-life
commands:

| Command | Effect |
|---|---|
| `include <glob>` | Load definitions from `.liaheader` files |
| `definitions` | List all current definitions, rules, assumptions, constraints |
| `definitions <symbol>` | List only the definitions of `<symbol>` |
| `clear` | Remove all definitions, rules, assumptions, constraints |
| `save <path>` | Write the accumulated session header to a `.liaheader` file (appends if the file has content) |

The REPL adds no evaluation semantics of its own — everything it can do,
batch can do.

## Syntax at a glance

- ASCII input; LaTeX-style `\commands` only for non-typable symbols
  (`\pm`, `\infty`, `\alpha`); `->`, `>=`, `<=`, `!=` for arrows and
  relations.
- **Whitespace is an operator**: a double space is chunk multiplication,
  and `/` takes single-space products on both sides, so the quadratic
  formula needs no parentheses around `2 a`.
- Definitions are rewrite rules: `x := e` clears and defines; `x = e`
  appends; either way, expressions containing `x` expand to its
  definition.
- Multi-character variables are supported (`force`, `m_1`, `m_2`);
  reserved words (`sqrt`, `sin`, `where`, set names, …) cannot be
  variables.
- `$x` in a rule makes it a pattern — `$x` binds any subexpression, with
  optional `where` guards: `$x/$x = 1 where $x != 0`.
- Built-in sets: `NATURAL` (includes 0), `INTEGER`, `RATIONAL`, `REAL`,
  `COMPLEX`, `PRIME`, `BOOLEAN`.

See [`docs/DESIGN.md`](docs/DESIGN.md) for the full grammar, the evaluation
pipeline, and the decisions log.

## Build

Requires Zig 0.15.2 (see `build.zig.zon`).

```console
zig build              # build
zig build test         # run tests
```
