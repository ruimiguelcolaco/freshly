# CI performance baseline

Freshly keeps its four verification jobs independent so quick failures do not
wait for unrelated work. Before changing that shape, compare the critical path
(the longest job), not the sum of parallel job durations.

## 2026-08-16 measurement

Measured on GitHub's `macos-26` runners using the `CI` workflow. Step times are
rounded from the timestamps reported by GitHub Actions.

| Cache state | Core tests | App build + tests | Definitions | Localization | Critical path |
| --- | ---: | ---: | ---: | ---: | ---: |
| Cold/new cache keys | 58 s | 66 s | 10 s | <1 s | 66 s |
| Restored-prefix caches after source changes | 49 s | 52 s | 17 s | 0 s | 52 s |
| Exact warm cache keys | 43 s | 40 s | 19 s | <1 s | 43 s |

The core and definitions jobs intentionally remain separate. They compile some
of the same package sources, but run concurrently and expose a definitions
failure much earlier than a single serial job would. Consolidation is only
worthwhile if a future measurement shows a shorter end-to-end critical path.
The exact warm run shortened the critical gate by 35% from 66 to 43 seconds;
serializing definitions behind the core tests would instead lengthen it to at
least 62 seconds, so the parallel shape remains the measured winner.

To repeat the measurement, push one source-changing commit for the cold/new-key
case, followed by a documentation-only commit for the exact warm-key case. Use
job step timestamps rather than the workflow's queue and teardown time.
