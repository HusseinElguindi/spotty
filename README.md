# Spotty

A small replacement for Spotlight that does two things: opens apps and does sums.
No file search, no AI, no web results.

- `Sources/LauncherCore`: the UI-free core (matching, ranking, what it learns, the calculator).
  Foundation only; `swift test` covers it.
- `docs/implementation.md`: how every part works (indexing, re-indexing, matching, ranking, calculator, panel).
- `docs/design.md`: the "B · Quiet" design: sizes, type, colours, keys, motion and copy.
- `docs/plan.md`: the build plan.

```sh
swift test   # core tests
```
