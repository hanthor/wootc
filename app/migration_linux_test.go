//go:build linux

package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestValidFlatpakID(t *testing.T) {
	for _, id := range []string{"org.mozilla.firefox", "com.visualstudio.code"} {
		if !validFlatpakID(id) {
			t.Errorf("expected valid Flatpak ID %q", id)
		}
	}
	for _, id := range []string{"", "org/foo", "..", "org.example;rm"} {
		if validFlatpakID(id) {
			t.Errorf("expected invalid Flatpak ID %q", id)
		}
	}
}

func TestReadSessionConsentsFailClosed(t *testing.T) {
	path := filepath.Join(t.TempDir(), "session-consent.json")
	if err := os.WriteFile(path, []byte(`{"chrome":true}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if !readSessionConsents(path)["chrome"] {
		t.Fatal("expected consent to be read")
	}
	if got := readSessionConsents(filepath.Join(t.TempDir(), "missing")); len(got) != 0 {
		t.Fatalf("missing consent file = %#v", got)
	}
}
