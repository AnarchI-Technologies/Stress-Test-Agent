# Stress Test Agent

An engineering demonstration by Alexander Gudde: resilience testing and evidence-based readiness scoring.

## Purpose

Stress Test Agent helps break systems safely, summarize evidence, and decide whether a build is ready, needs review, or is blocked.

This public project demonstrates Alexander's approach to failure analysis, bounded testing, and release decisions. Related product work lives at [AnarchI Technologies](https://github.com/AnarchI-Technologies-MAIN).

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
