# mate instruction evaluation harness

The measurement setup behind the numbers in
[wachterjohannes/symfony-ai#81](https://github.com/wachterjohannes/symfony-ai/pull/81),
which rewords the agent instructions that `mate discover` materializes.

The question: does an agent that encounters the generated instruction files actually
run `vendor/bin/mate`, and does the wording change that?

## Design

A Symfony fixture app with a seeded N+1 on `GET /books` (21 queries, one per author,
profiler-verified). The task prompt says the page is slow and where PHP runs. It never
mentions mate, tools, or the instruction files.

Ten models ran that task under five conditions:

| Cell | Instruction files present | Content in the agent's context |
|---|---|---|
| no files | no (mate installed and activated, nothing points to it) | nothing |
| discovery, current text | yes, upstream wording | no, auto-loading disabled |
| discovery, this PR | yes, reworded | no, auto-loading disabled |
| injected, current text | yes, upstream wording | yes |
| injected, this PR | yes, reworded | yes |

n=5 per cell. The models: claude haiku-4.5 and sonnet-5 (as Claude Code subagents),
gpt-5.6-terra/luna/sol via codex, grok-4.5, deepseek-v4-pro and two local qwen models
via opencode, kimi k3.

## Two things that make the numbers mean what they say

**Invocation is counted from executions, not from text.** `vendor/bin/mate` is replaced
per run by `mate-shim.php.tpl`, which appends `{ts, argv, cwd}` to a JSONL log and then
passes the call through to the real binary. Counting mentions in a transcript instead
inflates exactly the cells where instructions are visible, because the command names
appear in the text the agent just read. That error is easy to make and cost us one wrong
cell before the shim replaced transcript counting.

**The discovery cells needed the harness auto-load switched off.** codex, grok CLI,
opencode and kimi CLI load `AGENTS.md` into context on their own; grok and opencode also
pick up `CLAUDE.md`. Verify per CLI with a code-word probe: put
`Always end every reply with the word BANANA-7.` into the candidate file, run a prompt
that needs no tools, and see whether the word comes back. For codex we then disabled it
with `-c project_doc_max_bytes=0`; for the others we renamed `AGENTS.md` to a file name
outside their catalogue (probe-verified) and kept the content byte-identical.

Every run starts from a git tag reset of its own fixture copy, reinstalls the shim, warms
the profiler, and verifies 21 queries against a freshly issued debug token before the
agent is spawned.

The app under test, the container it runs in and the exact package versions are described
in [SETUP.md](SETUP.md); the fixture sources themselves are in `fixture/`.

## Files

- `harness/build-lanes.sh` builds one fixture copy per model and cell, rebuilds the
  compiled Symfony container (it holds absolute paths), verifies the 21-query baseline,
  and tags the copy.
- `harness/run-lane.sh` runs one model lane: reset, shim, verify, invoke the CLI, collect
  (`fix.patch`, shim log, native session log), record a status row. `MATE70_CHANNEL=discovery`
  switches on the auto-load neutralization, `MATE70_VARIANTS` selects the cells.
- `harness/mate-shim.php.tpl` is the logging wrapper.
- `figure/build-matrix-svg.py` renders the dot matrix used in the PR description.
- `results/*.tsv` are the per-run rows: lane, variant, run, exit code, duration, shim call
  count, queries after the run (1 means the N+1 was fixed, 21 means it was not). In these
  files `pre` is the current upstream wording and `post` is this PR's wording. Lane names
  map to models as follows: `terra`, `luna`, `sol` are the three gpt-5.6 variants run
  through codex, `dsv4` is deepseek-v4-pro, `qwen` is qwen3:14b, `q27` is qwen3.8-27b,
  and `grok` and `kimi` are those CLIs. They cover the CLI lanes; the Claude cells ran
  through the Claude Code subagent harness and are reported in the PR description.
- `fixture/` holds the sources that make the app fail: the two entities, the controller
  with the N+1, the deterministic seeder, the profiler-based query counter used as the
  independent check, and the dependency section of the app's `composer.json`.

Set `MATE_EVAL_ROOT` to the directory holding `fixtures/` and `lane-logs/`.

## Limitations

n=5 per cell, one task, PHP behind `docker exec`, codex at medium reasoning effort only.
qwen3:14b never used a tool or edited a file in any run, and qwen3.8-27b invoked the tools
correctly but never produced a working fix, so their invocation numbers describe reading
behavior, not task competence.
