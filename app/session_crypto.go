package main

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"io"
)

const sessionEnvelopeVersion = 1

// sessionEnvelope is the transport format written by the Windows half. The
// DPAPI-recovered Chromium key is never staged in clear; it is sealed with a
// key derived from the Linux user's vault secret. The target can use this key
// to decrypt Chromium payloads and re-encrypt them with its native keyring.
type sessionEnvelope struct {
	Version    int    `json:"version"`
	App        string `json:"app"`
	Algorithm  string `json:"algorithm"`
	Salt       []byte `json:"salt"`
	Nonce      []byte `json:"nonce"`
	Ciphertext []byte `json:"ciphertext"`
}

func sealSessionKey(app string, chromiumKey []byte, vaultSecret string) ([]byte, error) {
	if app == "" || len(chromiumKey) == 0 || vaultSecret == "" {
		return nil, fmt.Errorf("session rewrap requires app, key, and vault secret")
	}
	salt := make([]byte, 32)
	if _, err := io.ReadFull(rand.Reader, salt); err != nil {
		return nil, fmt.Errorf("session salt: %w", err)
	}
	key := deriveSessionKey(vaultSecret, salt)
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, fmt.Errorf("session cipher: %w", err)
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("session AEAD: %w", err)
	}
	nonce := make([]byte, gcm.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return nil, fmt.Errorf("session nonce: %w", err)
	}
	ciphertext := gcm.Seal(nil, nonce, chromiumKey, []byte(app))
	envelope := sessionEnvelope{
		Version: sessionEnvelopeVersion, App: app, Algorithm: "AES-256-GCM/HKDF-SHA256",
		Salt: salt, Nonce: nonce, Ciphertext: ciphertext,
	}
	return json.Marshal(envelope)
}

func openSessionKey(data []byte, app, vaultSecret string) ([]byte, error) {
	if app == "" || vaultSecret == "" {
		return nil, fmt.Errorf("session envelope requires app and vault secret")
	}
	var envelope sessionEnvelope
	if err := json.Unmarshal(data, &envelope); err != nil {
		return nil, fmt.Errorf("session envelope: %w", err)
	}
	if envelope.Version != sessionEnvelopeVersion || envelope.App != app || envelope.Algorithm != "AES-256-GCM/HKDF-SHA256" {
		return nil, fmt.Errorf("unsupported session envelope")
	}
	if len(envelope.Salt) != 32 {
		return nil, fmt.Errorf("invalid session salt")
	}
	key := deriveSessionKey(vaultSecret, envelope.Salt)
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil || len(envelope.Nonce) != gcm.NonceSize() {
		return nil, fmt.Errorf("invalid session nonce")
	}
	plain, err := gcm.Open(nil, envelope.Nonce, envelope.Ciphertext, []byte(app))
	if err != nil {
		return nil, fmt.Errorf("session authentication failed")
	}
	return plain, nil
}

func deriveSessionKey(secret string, salt []byte) []byte {
	// HKDF extract/expand with a fixed context keeps this transport key
	// separate from the password hash stored in vault.json.
	extract := hmac.New(sha256.New, salt)
	extract.Write([]byte(secret))
	prk := extract.Sum(nil)
	expand := hmac.New(sha256.New, prk)
	expand.Write([]byte("wootc session rewrap v1\x00"))
	expand.Write([]byte{1})
	return expand.Sum(nil)
}
