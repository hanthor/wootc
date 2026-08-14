package main

import (
	"bytes"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"testing"
)

// sealChromiumValue builds a synthetic "v10"-format encrypted_value blob the
// same way real Chromium does, so tests exercise decryptChromiumValue
// against the actual wire format rather than a round-trip through its own
// logic only.
func sealChromiumValue(t *testing.T, key, plaintext []byte) []byte {
	t.Helper()
	block, err := aes.NewCipher(key)
	if err != nil {
		t.Fatalf("aes cipher: %v", err)
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		t.Fatalf("gcm: %v", err)
	}
	nonce := make([]byte, chromiumValueNonceLen)
	if _, err := rand.Read(nonce); err != nil {
		t.Fatalf("nonce: %v", err)
	}
	out := append([]byte("v10"), nonce...)
	return gcm.Seal(out, nonce, plaintext, nil)
}

func testChromiumKey(t *testing.T) []byte {
	t.Helper()
	key := make([]byte, 32)
	if _, err := rand.Read(key); err != nil {
		t.Fatalf("key: %v", err)
	}
	return key
}

func TestDecryptChromiumValueRoundTrip(t *testing.T) {
	key := testChromiumKey(t)
	plaintext := []byte("session-cookie-value-abc123")
	blob := sealChromiumValue(t, key, plaintext)

	got, err := decryptChromiumValue(key, blob)
	if err != nil {
		t.Fatalf("decrypt: %v", err)
	}
	if !bytes.Equal(got, plaintext) {
		t.Fatalf("decrypt = %q, want %q", got, plaintext)
	}
}

func TestDecryptChromiumValueEmptyPlaintext(t *testing.T) {
	key := testChromiumKey(t)
	blob := sealChromiumValue(t, key, []byte{})

	got, err := decryptChromiumValue(key, blob)
	if err != nil {
		t.Fatalf("decrypt: %v", err)
	}
	if len(got) != 0 {
		t.Fatalf("decrypt = %q, want empty", got)
	}
}

func TestDecryptChromiumValueRejectsWrongKey(t *testing.T) {
	key := testChromiumKey(t)
	blob := sealChromiumValue(t, key, []byte("token"))

	wrongKey := testChromiumKey(t)
	if _, err := decryptChromiumValue(wrongKey, blob); err == nil {
		t.Error("expected error decrypting with the wrong key")
	}
}

func TestDecryptChromiumValueRejectsTamperedCiphertext(t *testing.T) {
	key := testChromiumKey(t)
	blob := sealChromiumValue(t, key, []byte("token"))
	tampered := bytes.Clone(blob)
	tampered[len(tampered)-1] ^= 0xFF // flip a byte in the GCM tag

	if _, err := decryptChromiumValue(key, tampered); err == nil {
		t.Error("expected error decrypting tampered blob")
	}
}

func TestDecryptChromiumValueRejectsWrongKeyLength(t *testing.T) {
	blob := sealChromiumValue(t, testChromiumKey(t), []byte("token"))
	if _, err := decryptChromiumValue([]byte("too-short"), blob); err == nil {
		t.Error("expected error for a non-32-byte key")
	}
}

func TestDecryptChromiumValueRejectsUnsupportedPrefix(t *testing.T) {
	key := testChromiumKey(t)
	blob := sealChromiumValue(t, key, []byte("token"))
	blob[0], blob[1], blob[2] = 'v', '1', '1'

	if _, err := decryptChromiumValue(key, blob); err == nil {
		t.Error("expected error for an unsupported v11 prefix")
	}
}

func TestDecryptChromiumValueRejectsShortBlob(t *testing.T) {
	if _, err := decryptChromiumValue(testChromiumKey(t), []byte("v1")); err == nil {
		t.Error("expected error for a blob too short for the version prefix")
	}
	if _, err := decryptChromiumValue(testChromiumKey(t), []byte("v10")); err == nil {
		t.Error("expected error for a blob with a prefix but no nonce")
	}
	if _, err := decryptChromiumValue(testChromiumKey(t), nil); err == nil {
		t.Error("expected error for a nil blob")
	}
}
