# Benchmark Walkthrough

Step-by-step guide to measuring whether repo-understand scaffolding
actually helps AI agents work faster, cheaper, and more accurately.

## What you're measuring

Three things:
1. **Time** — does the agent finish faster with scaffolding?
2. **Tokens** — does the full agent session cost fewer tokens?
3. **Accuracy** — does the agent produce a better answer?

The agent runs in **full agent mode** with file access (Read, Glob, Grep).
Without scaffolding, it must explore the codebase from scratch. With
scaffolding, the generated docs are in the repo for it to discover.

## Prerequisites

- `jq` installed
- `claude` CLI installed and authenticated
- A target repository to analyze

Set up a convenience variable:

```bash
BENCHMARK_DIR=/path/to/repo-understand/benchmark
```

## Part 1: Run the generic tasks

There are 3 built-in tasks that work on any repository.

### Task 1: Explain architecture

```bash
# Baseline (no scaffolding — agent explores from scratch)
$BENCHMARK_DIR/benchmark.sh /path/to/target/repo \
  $BENCHMARK_DIR/tasks/explain-architecture.md --without-scaffolding

# With scaffolding (generated docs are in the repo for the agent to find)
$BENCHMARK_DIR/benchmark.sh /path/to/target/repo \
  $BENCHMARK_DIR/tasks/explain-architecture.md --with-scaffolding
```

### Task 2: Find an endpoint

```bash
$BENCHMARK_DIR/benchmark.sh /path/to/target/repo \
  $BENCHMARK_DIR/tasks/find-endpoint.md --without-scaffolding

$BENCHMARK_DIR/benchmark.sh /path/to/target/repo \
  $BENCHMARK_DIR/tasks/find-endpoint.md --with-scaffolding
```

### Task 3: Impact analysis

```bash
$BENCHMARK_DIR/benchmark.sh /path/to/target/repo \
  $BENCHMARK_DIR/tasks/impact-analysis.md --without-scaffolding

$BENCHMARK_DIR/benchmark.sh /path/to/target/repo \
  $BENCHMARK_DIR/tasks/impact-analysis.md --with-scaffolding
```

### Generate the report

```bash
$BENCHMARK_DIR/report.sh
```

This reads all result JSON files from `benchmark/results/` and produces
`benchmark/results/benchmark-report.md` with a comparison table.

## Part 2: Judge accuracy

After running tasks, you can have a separate agent score each result.
This is automated — no manual scoring needed.

```bash
# Judge a specific result file
$BENCHMARK_DIR/benchmark.sh /path/to/target/repo \
  $BENCHMARK_DIR/tasks/explain-architecture.md \
  --judge benchmark/results/20260222_143000_explain-architecture_without.json

# With an answer key (for domain-specific tasks)
$BENCHMARK_DIR/benchmark.sh /path/to/target/repo \
  /path/to/custom-task.md \
  --judge benchmark/results/some_result.json \
  --answer-key /path/to/answer-key.md
```

The judge pass:
1. Reads the original task and the agent's response from the result file
2. Optionally reads an answer key (ground truth)
3. Scores accuracy (1-5), completeness (1-5), and counts hallucinations
4. Writes the scores back into the result JSON file
5. Re-running `report.sh` will include the accuracy table

## Part 3: Write domain-specific tasks

The generic tasks test general understanding. But the real value of
scaffolding shows up on **domain-specific questions** — the kind where
an agent without context would have to dig through many files across
multiple packages to piece together the answer.

### What makes a good domain-specific task?

A good task:
- Crosses package or module boundaries
- Requires understanding how multiple systems interact
- Has a non-obvious answer that requires tracing through code
- Would take an agent many file reads to figure out from scratch

### Example: writing a domain-specific task

Say your repo has a payment processing system that spans multiple
services. You might create a task file like this:

```markdown
# Benchmark Task: Payment Retry Pipeline

## Task

When a payment fails, trace the complete retry lifecycle from the
initial failure event to the final resolution (success or permanent
failure). Identify all services involved, queue mechanisms, and
retry policies.

## Expected Coverage

Your answer should include:
1. Which service detects the initial payment failure
2. How the failure event is published (queue, event bus, webhook)
3. Which service(s) handle the retry logic
4. The retry policy (intervals, max attempts, backoff strategy)
5. How permanent failure is determined and what happens next
6. Any notification side effects (emails, alerts, webhooks)

## Scoring Rubric

| Score | Criteria |
|-------|----------|
| 5 | Complete lifecycle traced, all services identified, retry policy correct |
| 4 | Most of the pipeline traced, minor gaps |
| 3 | Main flow understood but missing cross-service connections |
| 2 | Partial trace, major gaps |
| 1 | Could not trace the pipeline or mostly incorrect |

## Difficulty

- Without scaffolding: 5/5 (must discover cross-service flow)
- With scaffolding: 2/5 (docs show service boundaries and dependencies)
```

Save it anywhere. The benchmark harness takes any markdown file as a task:

```bash
# Run your domain-specific task
$BENCHMARK_DIR/benchmark.sh /path/to/target/repo \
  /path/to/your-custom-task.md --without-scaffolding

$BENCHMARK_DIR/benchmark.sh /path/to/target/repo \
  /path/to/your-custom-task.md --with-scaffolding

# Judge with answer key
$BENCHMARK_DIR/benchmark.sh /path/to/target/repo \
  /path/to/your-custom-task.md \
  --judge benchmark/results/<result-file>.json \
  --answer-key /path/to/answer-key.md
```

### Tips for domain-specific tasks

- **Keep an answer key.** Write down the correct answer separately. Pass
  it to `--answer-key` so the judge can score against ground truth.
- **Pick tasks where scaffolding should help.** Cross-cutting concerns,
  multi-package flows, and "where does X live?" questions benefit most.
- **Pick one task where scaffolding should NOT help.** Something very
  localized (e.g., "what does this specific function do?") serves as a
  control — scaffolding shouldn't make a difference there.

## Part 4: Interpret the results

After running all tasks and judging them, generate the report:

```bash
$BENCHMARK_DIR/report.sh
```

The report shows two tables per task:

**Performance:**
```
| Metric         | Without Scaffolding | With Scaffolding | Delta |
|----------------|--------------------:|-----------------:|------:|
| Duration (s)   |                 45  |              18  |  -60% |
| Input Tokens   |              85000  |           32000  |  -62% |
| Output Tokens  |               3200  |            2800  |  -12% |
| Total Tokens   |              88200  |           34800  |  -61% |
| Agent Turns    |                 12  |               5  |  -58% |
```

**Accuracy (if judged):**
```
| Metric              | Without Scaffolding | With Scaffolding | Delta |
|---------------------|--------------------:|-----------------:|------:|
| Accuracy (1-5)      |                  3  |               4  |  +33% |
| Completeness (1-5)  |                  2  |               5  | +150% |
| Hallucinations      |                  3  |               0  | -100% |
```

### What to look for

**Duration** is the primary metric. Lower duration with scaffolding means
the agent reached its answer faster because it didn't need to explore as
many files.

**Agent Turns** shows how many tool-use round trips the agent needed.
Fewer turns with scaffolding means the generated docs provided enough
context to reduce exploration.

**Total Tokens** reflects the full session cost. With scaffolding, total
session tokens should be lower if the agent explores less.

**Accuracy and Completeness** show whether the agent's answer was correct
and thorough. Scaffolding should improve both by giving the agent accurate
structural information upfront.

**Hallucinations** count fabricated claims. Agents without scaffolding are
more likely to guess at repo structure and get it wrong.

### Options

```bash
# Use a different model
$BENCHMARK_DIR/benchmark.sh /path/to/repo task.md --model opus --without-scaffolding

# Set a higher budget cap per run (default: $0.50)
$BENCHMARK_DIR/benchmark.sh /path/to/repo task.md --max-budget 2.00 --without-scaffolding
```

### Running multiple times

For reliable numbers, run each condition 3+ times and look at averages.
Single runs can vary due to model non-determinism. The report
automatically averages across multiple runs of the same task/condition.

## Where things go

| What | Where | Persists? |
|------|-------|-----------|
| Task definitions | `benchmark/tasks/*.md` | Yes — committed |
| Custom task files | Anywhere you choose | Up to you |
| Result JSON files | `benchmark/results/*.json` | No — gitignored |
| Comparison report | `benchmark/results/benchmark-report.md` | No — gitignored |
| Scaffolding (with condition) | Target repo (cleaned up after) | No — removed after run |
