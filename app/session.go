package main

// SessionCandidate is a per-app finding surfaced to the GUI so the user can
// consent (or not) to moving its login. It contains no token material.
type SessionCandidate struct {
	App             string `json:"app"`
	Kind            string `json:"kind"`      // "chromium" | "plainfile"
	Portable        bool   `json:"portable"`  // decryptable here?
	Recommend       string `json:"recommend"` // "copy" | "relink" | "signin"
	Note            string `json:"note"`
	ConsentRequired bool   `json:"consentRequired"`
}
