import unittest

from stress_test_agent import ScenarioResult, summarize_results


class StressReportTests(unittest.TestCase):
    def test_empty_summary_has_no_evidence_status(self):
        summary = summarize_results([])

        self.assertEqual(summary.status, "NO_EVIDENCE")

    def test_all_passed_is_ready(self):
        summary = summarize_results([ScenarioResult("health", True), ScenarioResult("cache", True)])

        self.assertEqual(summary.status, "READY")
        self.assertEqual(summary.readiness_score, 1.0)

    def test_critical_failure_blocks(self):
        summary = summarize_results([ScenarioResult("health", True), ScenarioResult("write gate", False, "critical")])

        self.assertEqual(summary.status, "BLOCKED")


if __name__ == "__main__":
    unittest.main()

