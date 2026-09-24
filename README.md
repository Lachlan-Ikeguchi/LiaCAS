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
| `clear` | Remove all definitions, rules, assumptions, constraints |

The REPL adds no evaluation semantics of its own — everything it can do,
batch can do.

## Syntax at a glance

- ASCII input; LaTeX-style `\commands` only for non-typable symbols
  (`\pm`, `\infty`, `\alpha`); `->`, `>=`, `<=`, `!=` for arrows and
  relations.
- **Whitespace is an operator**: a double space is chunk multiplication,
  and `/` swallows the following single-space product, so the quadratic
  formula needs no parentheses around `2 a`.
- `x := e` clears and defines; `x = e` appends to the definitions of `x`.
- `$x` in a definition makes it a rewrite rule — `$x` binds any
  subexpression, with optional `where` guards:
  `r^x = 1 where x in COMPLEX; r > 10`.
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
