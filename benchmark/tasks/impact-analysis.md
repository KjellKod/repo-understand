# Benchmark Task: Impact Analysis

## Task

If we change the primary database connection configuration, what parts of
the codebase would be affected? If this repository does not use a database,
choose the most critical external service configuration instead (e.g., API
keys, message queue connection, cache server).

## Expected Coverage

Your answer should include:
1. Where the connection or configuration is currently defined
2. All files that read or use this configuration
3. All services or modules that establish connections using it
4. Any environment-specific configuration (dev, staging, prod)
5. Potential risks or side effects of changing it

## Scoring Rubric

| Score | Criteria |
|-------|----------|
| 5 | All configuration locations found, complete dependency chain, risks identified |
| 4 | Most locations found, good dependency analysis |
| 3 | Main configuration found, partial dependency analysis |
| 2 | Some relevant files found but major gaps |
| 1 | Could not locate configuration or mostly incorrect |
