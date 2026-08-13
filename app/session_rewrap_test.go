package main

import (
	"bytes"
	"testing"
)

func TestDeriveRewrapKeyLength(t *testing.T) {
	key, err := deriveRewrapKey([]byte("vault-secret"), "chrome")
	if err != nil {
		t.Fatalf("derive: %v", err)
	}
	if len(key) != 32 {
		t.Fatalf("key length = %d, want 32", len(key))
	}
}

func TestDeriveRewrapKeyRejectsEmptyInputs(t *testing.T) {
	if _, err := deriveRewrapKey(nil, "chrome"); err == nil {
		t.Error("expected error for empty vault secret")
	}
	if _, err := deriveRewrapKey([]byte("vault-secret"), ""); err == nil {
		t.Error("expected error for empty app")
	}
}

func TestDeriveRewrapKeyIsPerAppScoped(t *testing.T) {
	secret := []byte("vault-secret")
	chromeKey, err := deriveRewrapKey(secret, "chrome")
	if err != nil {
		t.Fatalf("derive chrome: %v", err)
	}
	edgeKey, err := deriveRewrapKey(secret, "edge")
	if err != nil {
		t.Fatalf("derive edge: %v", err)
	}
	if bytes.Equal(chromeKey, edgeKey) {
		t.Error("different apps must not derive the same key from the same secret")
	}
}

func TestDeriveRewrapKeyIsDeterministic(t *testing.T) {
	secret := []byte("vault-secret")
	k1, err := deriveRewrapKey(secret, "chrome")
	if err != nil {
		t.Fatalf("derive 1: %v", err)
	}
	k2, err := deriveRewrapKey(secret, "chrome")
	if err != nil {
		t.Fatalf("derive 2: %v", err)
	}
	if !bytes.Equal(k1, k2) {
		t.Error("same secret+app must derive the same key (target-side rewrap needs to reproduce it)")
	}
}

func TestSealOpenRoundTrip(t *testing.T) {
	key, err := deriveRewrapKey([]byte("vault-secret"), "spotify")
	if err != nil {
		t.Fatalf("derive: %v", err)
	}
	plaintext := []byte("super-secret-os_crypt-key-material")

	blob, err := sealSessionPayload(key, plaintext)
	if err != nil {
		t.Fatalf("seal: %v", err)
	}
	if bytes.Contains(blob, plaintext) {
		t.Fatal("sealed blob must not contain the plaintext")
	}

	got, err := openSessionPayload(key, blob)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	if !bytes.Equal(got, plaintext) {
		t.Fatalf("round trip = %q, want %q", got, plaintext)
	}
}

func TestSealProducesDistinctBlobsEachCall(t *testing.T) {
	key, _ := deriveRewrapKey([]byte("vault-secret"), "chrome")
	plaintext := []byte("same plaintext both times")

	b1, err := sealSessionPayload(key, plaintext)
	if err != nil {
		t.Fatalf("seal 1: %v", err)
	}
	b2, err := sealSessionPayload(key, plaintext)
	if err != nil {
		t.Fatalf("seal 2: %v", err)
	}
	if bytes.Equal(b1, b2) {
		t.Error("sealing the same plaintext twice must produce different blobs (random nonce)")
	}
}

func TestOpenRejectsWrongKey(t *testing.T) {
	key1, _ := deriveRewrapKey([]byte("vault-secret"), "chrome")
	key2, _ := deriveRewrapKey([]byte("other-vault-secret"), "chrome")

	blob, err := sealSessionPayload(key1, []byte("token"))
	if err != nil {
		t.Fatalf("seal: %v", err)
	}
	if _, err := openSessionPayload(key2, blob); err == nil {
		t.Error("expected error opening with the wrong key")
	}
}

func TestOpenRejectsTamperedCiphertext(t *testing.T) {
	key, _ := deriveRewrapKey([]byte("vault-secret"), "chrome")
	blob, err := sealSessionPayload(key, []byte("token"))
	if err != nil {
		t.Fatalf("seal: %v", err)
	}
	tampered := bytes.Clone(blob)
	tampered[len(tampered)-1] ^= 0xFF // flip a byte in the GCM tag

	if _, err := openSessionPayload(key, tampered); err == nil {
		t.Error("expected error opening tampered blob")
	}
}

func TestOpenRejectsUnsupportedVersion(t *testing.T) {
	key, _ := deriveRewrapKey([]byte("vault-secret"), "chrome")
	blob, err := sealSessionPayload(key, []byte("token"))
	if err != nil {
		t.Fatalf("seal: %v", err)
	}
	blob[0] = 0xFF

	if _, err := openSessionPayload(key, blob); err == nil {
		t.Error("expected error opening a blob with an unsupported version byte")
	}
}

func TestOpenRejectsTooShortBlob(t *testing.T) {
	key, _ := deriveRewrapKey([]byte("vault-secret"), "chrome")
	if _, err := openSessionPayload(key, []byte{sessionRewrapVersion}); err == nil {
		t.Error("expected error opening a blob with no room for a nonce")
	}
	if _, err := openSessionPayload(key, nil); err == nil {
		t.Error("expected error opening an empty blob")
	}
}
