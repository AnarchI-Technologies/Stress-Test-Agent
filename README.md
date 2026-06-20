# Stress Test Agent

Resilience testing and readiness scoring for AnarchI Technologies systems.

Hardcoding freedom into the systems of tomorrow.

## Purpose

Stress Test Agent helps break systems safely, summarize evidence, and decide whether a build is ready, needs review, or is blocked.

## What Changed

- Added a tested Python report evaluator.
- Preserved the existing PowerShell harness and JSON result fixtures.
- Added readiness scoring with severity-aware failure penalties.

## Verify

```bash
python -m unittest discover -s tests -q
```

## Public Safety

Stress runs should stay isolated from live production state. Do not commit secrets, private logs, customer data, wallet material, or live runtime snapshots.
