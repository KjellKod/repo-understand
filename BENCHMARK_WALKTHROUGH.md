# Benchmark Walkthrough

Step-by-step guide to measuring whether repo-understand scaffolding
actually helps AI agents work faster and cheaper on your codebase.

## What you're measuring

One question: **does having the generated docs reduce token usage and
improve accuracy when an agent works on your repo?**

You run the same task twice — once without scaffolding (baseline), once
with — and compare the results.

## Prerequisites

- `jq` installed
- Either the `claude` CLI or `ANTHROPIC_API_KEY` set in your environment
- A target repository to analyze

Set up a convenience variable for the benchmark directory:

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

# With scaffolding (agent gets generated docs as context)
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

## Part 2: Write domain-specific tasks

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

Save it anywhere — the benchmark harness takes any markdown file as a
task:

```bash
# Run your domain-specific task
$BENCHMARK_DIR/benchmark.sh /path/to/target/repo \
  /path/to/your-custom-task.md --without-scaffolding

$BENCHMARK_DIR/benchmark.sh /path/to/target/repo \
  /path/to/your-custom-task.md --with-scaffolding
```

### Tips for domain-specific tasks

- **Keep an answer key.** Write down the correct answer separately so you
  can score the agent's response accurately.
- **Pick tasks where scaffolding should help.** Cross-cutting concerns,
  multi-package flows, and "where does X live?" questions benefit most.
- **Pick one task where scaffolding should NOT help.** Something very
  localized (e.g., "what does this specific function do?") serves as a
  control — scaffolding shouldn't make a difference there.

## Part 3: Interpret the results

After running all tasks, generate the report:

```bash
$BENCHMARK_DIR/report.sh
```

The report shows a table like this for each task:

```
| Metric         | Without Scaffolding | With Scaffolding | Delta |
|----------------|--------------------:|-----------------:|------:|
| Input Tokens   |              45000  |           12000  |  -73% |
| Output Tokens  |               2100  |            1800  |  -14% |
| Total Tokens   |              47100  |           13800  |  -71% |
| Duration (s)   |                 38  |              12  |  -68% |
```

### What to look for

**Input tokens** is the primary metric. Lower input tokens with
scaffolding means the agent didn't need to explore as many files —
the generated docs gave it the context it needed upfront.

**Duration** should correlate with input tokens — fewer file reads
means faster completion.

**Output tokens** may not change much. The agent writes roughly the
same answer either way.

**Quality** requires manual scoring using the rubric in each task file.
Read both responses side by side and score each 1-5. The scaffolded
response should be more accurate and have fewer hallucinations because
the agent started with correct structural information.

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
| Scaffolding (during benchmark) | `/tmp/benchmark-scaffold.XXXXXX/` | No — auto-deleted |
