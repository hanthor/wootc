package main

import (
	"crypto/aes"
	"crypto/cipher"
	"errors"
	"fmt"
)

// Chromium per-value decryption (docs/session-migration.md, tuna-os/wootc#1
// item 1, second half). sealSessionPayload/openSessionPayload (in
// session_rewrap.go) move the DPAPI-recovered os_crypt master KEY across the
// vault-derived envelope. This file is the next step: using that key to
// decrypt an individual Cookies/Local Storage value, once it's been copied
// (byte-for-byte, alongside the app's other plain files) to the target.
//
// This does NOT do the remaining, larger pieces of "target-side rewrite":
// enumerating a live SQLite/LevelDB file and re-encrypting values under the
// Linux keyring. Both need testing against a real Chrome/Edge install this
// environment can't provide -- see the issue for why that's explicitly
// unclaimed. What's implemented here is the one sub-step whose correctness
// doesn't depend on a live browser: the wire format itself.
//
// Format (stable across Chrome/Chromium/Electron since ~2013, documented
// publicly and implemented identically by every major cookie-extraction
// tool -- e.g. browser_cookie3, chrome-cookies-secure): the `encrypted_value`
// BLOB column in Cookies' `cookies` table, and each value in Local Storage's
// LevelDB, is:
//
//	[3-byte ASCII prefix "v10" or "v11"] [12-byte GCM nonce] [ciphertext] [16-byte GCM tag]
//
// AES-256-GCM, no associated data. "v11" additionally authenticates a
// platform-specific static string as AAD on some Chrome versions/platforms;
// only "v10" (no AAD) is implemented here, since that's the form actually
// reachable from this DPAPI-recovered-key path -- see decryptChromiumValue's
// doc comment for what happens on an unrecognized prefix (a clear error, not
// a silent wrong answer).

const (
	chromiumValuePrefixLen = 3
	chromiumValueNonceLen  = 12
)

// decryptChromiumValue decrypts one Cookies/Local Storage encrypted_value
// blob using the os_crypt master key recovered via DPAPI (chromiumMasterKey)
// and carried across the vault-sealed envelope (openSessionPayload).
//
// Returns a descriptive error rather than guessing on anything unexpected:
// an unsupported prefix, a too-short blob, or a failed GCM tag check all
// fail closed. A "v11" prefix is reported as unsupported rather than
// attempted -- some Chrome versions add platform-specific associated data
// to v11 that isn't documented consistently enough to implement without a
// real browser to verify against; better to skip that value than produce
// a plausible-looking wrong plaintext.
func decryptChromiumValue(key []byte, blob []byte) ([]byte, error) {
	if len(key) != 32 {
		return nil, fmt.Errorf("os_crypt key must be 32 bytes, got %d", len(key))
	}
	if len(blob) < chromiumValuePrefixLen {
		return nil, errors.New("blob too short for version prefix")
	}
	prefix := string(blob[:chromiumValuePrefixLen])
	if prefix != "v10" {
		return nil, fmt.Errorf("unsupported encrypted_value prefix %q", prefix)
	}
	rest := blob[chromiumValuePrefixLen:]
	if len(rest) < chromiumValueNonceLen {
		return nil, errors.New("blob too short for nonce")
	}
	nonce, ciphertext := rest[:chromiumValueNonceLen], rest[chromiumValueNonceLen:]

	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, fmt.Errorf("aes cipher: %w", err)
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("gcm: %w", err)
	}
	plaintext, err := gcm.Open(nil, nonce, ciphertext, nil)
	if err != nil {
		return nil, fmt.Errorf("open encrypted_value: %w", err)
	}
	return plaintext, nil
}
