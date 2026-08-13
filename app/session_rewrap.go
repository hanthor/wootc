package main

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"errors"
	"fmt"
	"io"

	"golang.org/x/crypto/hkdf"
)

// Session rewrap primitives (docs/session-migration.md, tuna-os/wootc#1
// item 2): the platform-neutral half of "re-encrypt the payload under a
// key derived from the wootc vault secret". The DPAPI decrypt that
// produces the plaintext (Windows-only, session_windows.go) and the
// target-side libsecret/kwallet rewrite are separate, larger pieces not
// covered here — see that issue for the remaining checklist.
//
// Format: per-app HKDF-SHA256 key derived from the vault secret, sealed
// with AES-256-GCM. A version byte prefixes the blob so a future format
// change is detectable instead of silently misparsed.

const sessionRewrapVersion = 1

// deriveRewrapKey derives a 32-byte AES-256 key from the vault secret,
// scoped to a single app via HKDF's info parameter. Per-app scoping means
// a leaked key for one app's staged blob doesn't expose another app's.
func deriveRewrapKey(vaultSecret []byte, app string) ([]byte, error) {
	if len(vaultSecret) == 0 {
		return nil, errors.New("vault secret must not be empty")
	}
	if app == "" {
		return nil, errors.New("app must not be empty")
	}
	h := hkdf.New(sha256.New, vaultSecret, []byte("wootc-session-rewrap-v1"), []byte(app))
	key := make([]byte, 32)
	if _, err := io.ReadFull(h, key); err != nil {
		return nil, fmt.Errorf("derive rewrap key: %w", err)
	}
	return key, nil
}

// sealSessionPayload encrypts plaintext under key with AES-256-GCM,
// producing [version(1) | nonce(12) | ciphertext+tag]. Staged as
// install\slurp\session\<app>.enc by the caller.
func sealSessionPayload(key, plaintext []byte) ([]byte, error) {
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, fmt.Errorf("aes cipher: %w", err)
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("gcm: %w", err)
	}
	nonce := make([]byte, gcm.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		return nil, fmt.Errorf("nonce: %w", err)
	}
	out := make([]byte, 0, 1+len(nonce)+len(plaintext)+gcm.Overhead())
	out = append(out, sessionRewrapVersion)
	out = append(out, nonce...)
	out = gcm.Seal(out, nonce, plaintext, nil)
	return out, nil
}

// openSessionPayload reverses sealSessionPayload. Used by the target-side
// rewrite (not implemented here) and by tests.
func openSessionPayload(key, blob []byte) ([]byte, error) {
	if len(blob) < 1 {
		return nil, errors.New("blob too short")
	}
	if blob[0] != sessionRewrapVersion {
		return nil, fmt.Errorf("unsupported session payload version %d", blob[0])
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, fmt.Errorf("aes cipher: %w", err)
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("gcm: %w", err)
	}
	ns := gcm.NonceSize()
	rest := blob[1:]
	if len(rest) < ns {
		return nil, errors.New("blob too short for nonce")
	}
	nonce, ciphertext := rest[:ns], rest[ns:]
	plaintext, err := gcm.Open(nil, nonce, ciphertext, nil)
	if err != nil {
		return nil, fmt.Errorf("open: %w", err)
	}
	return plaintext, nil
}
