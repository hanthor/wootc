package main

import (
	"bytes"
	"strings"
	"testing"
)

func TestSessionEnvelopeRoundTrip(t *testing.T) {
	want := []byte("chromium master key")
	data, err := sealSessionKey("chrome", want, "vault-secret")
	if err != nil {
		t.Fatal(err)
	}
	got, err := openSessionKey(data, "chrome", "vault-secret")
	if err != nil || !bytes.Equal(got, want) {
		t.Fatalf("round trip = %q, err = %v", got, err)
	}
	if _, err := openSessionKey(data, "edge", "vault-secret"); err == nil {
		t.Fatal("expected app binding to reject a different app")
	}
	if _, err := openSessionKey(data, "chrome", "wrong-secret"); err == nil {
		t.Fatal("expected vault secret mismatch to reject the envelope")
	}
}

func TestSessionEnvelopeRejectsEmptyInputs(t *testing.T) {
	if _, err := sealSessionKey("chrome", nil, "secret"); err == nil {
		t.Fatal("expected empty Chromium key to fail")
	}
}

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
