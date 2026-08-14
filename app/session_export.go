package main

import "fmt"

// exportConsentedSessions is the single consent gate for online session
// handling. Keeping it outside the Windows implementation makes the policy
// testable and ensures a future platform cannot accidentally export by
// default.
func exportConsentedSessions(candidates []SessionCandidate, consent map[string]bool, secret string) []SessionExport {
	results := make([]SessionExport, 0, len(candidates))
	for _, candidate := range candidates {
		result := SessionExport{App: candidate.App, State: "skipped"}
		switch {
		case !candidate.ConsentRequired:
			result.Reason = "app is not eligible for token migration"
		case !consent[candidate.App]:
			result.Reason = "user did not opt in"
		default:
			if err := exportSession(candidate.App, secret, true); err != nil {
				result.State = "failed"
				result.Reason = err.Error()
			} else {
				result.State = "staged"
				result.Reason = "protected envelope staged; Linux app import still required"
			}
		}
		results = append(results, result)
	}
	return results
}

func sessionExportSummary(results []SessionExport) string {
	data, err := marshalJSON(results)
	if err != nil {
		return fmt.Sprintf("[] /* failed to serialize session export summary: %v */", err)
	}
	return string(data)
}
