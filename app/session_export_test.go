package main

import (
	"strings"
	"testing"
)

func TestSessionExportPolicyDefaultsOff(t *testing.T) {
	results := exportConsentedSessions([]SessionCandidate{
		{App: "chrome", ConsentRequired: true},
	}, nil, "secret")
	if len(results) != 1 || results[0].State != "skipped" {
		t.Fatalf("default consent result = %#v", results)
	}
	if results[0].Reason != "user did not opt in" {
		t.Fatalf("default consent reason = %q", results[0].Reason)
	}
}

func TestSessionExportSummaryIsNotACompletionClaim(t *testing.T) {
	data := sessionExportSummary([]SessionExport{{App: "chrome", State: "staged"}})
	if !strings.Contains(data, `"state": "staged"`) || strings.Contains(data, `"state": "imported"`) {
		t.Fatalf("summary = %s", data)
	}
}
