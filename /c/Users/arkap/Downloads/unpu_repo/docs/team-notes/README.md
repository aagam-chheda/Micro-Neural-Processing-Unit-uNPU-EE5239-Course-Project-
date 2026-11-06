# Team notes

Explanatory documents written by a teammate (originally pushed to the
repository root, moved here on 2026-10-01 so the root stays clean). They are
kept exactly as written; nothing in them has been edited.

- `Quick Reference.md` — one-page summary of the design and the RTL modules.
- `Arch and Hierarchy Explanation.md` — longer architecture and module guide.

Status of these files:

- They are **not** part of the certified record (`docs/freeze-report-v2.md`)
  and have **not** been reviewed against the RTL by the Planning/Execution
  sessions. Where they disagree with the RTL, the RTL and
  `docs/session-handoff.md` win.
- They predate the back-end decision in `docs/session-handoff.md` §18: they
  name Genus for synthesis and ICC for place-and-route in the file-layout
  sections. The flow is now Design Compiler, ICC2, Calibre and PrimeTime.
- Nothing in the build, the testbenches or the scripts reads this directory.
