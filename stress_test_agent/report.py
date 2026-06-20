from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class ScenarioResult:
    name: str
    ok: bool
    severity: str = "medium"


@dataclass(frozen=True)
class StressSummary:
    total: int
    passed: int
    failed: int
    readiness_score: float
    status: str


def summarize_results(results: list[ScenarioResult]) -> StressSummary:
    if not results:
        return StressSummary(0, 0, 0, 0.0, "NO_EVIDENCE")

    total = len(results)
    passed = sum(1 for result in results if result.ok)
    failed = total - passed
    penalty = sum(_severity_weight(result.severity) for result in results if not result.ok)
    raw_score = max(0.0, (passed / total) - penalty)
    score = round(raw_score, 4)

    if failed == 0:
        status = "READY"
    elif score >= 0.7:
        status = "REVIEW"
    else:
        status = "BLOCKED"

    return StressSummary(total, passed, failed, score, status)


def _severity_weight(severity: str) -> float:
    return {
        "low": 0.03,
        "medium": 0.08,
        "high": 0.18,
        "critical": 0.35,
    }.get(severity.lower(), 0.08)

