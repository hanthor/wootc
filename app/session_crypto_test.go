package main

import (
	"bytes"
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
