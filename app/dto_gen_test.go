package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

func TestGeneratedCSharpDTOsNotStale(t *testing.T) {
	// Path to checked-in DTO file
	dtoPath := filepath.Join("..", "shell", "Wootc.Shell", "Engine", "Dto.cs")
	existingContent, err := os.ReadFile(dtoPath)
	if err != nil {
		t.Fatalf("failed to read %s: %v", dtoPath, err)
	}

	// Run go run ./tools/gendto in temp mode or execute generator
	cmd := exec.Command("go", "run", "./tools/gendto", ".")
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("gendto execution failed: %v, output: %s", err, string(out))
	}

	regeneratedContent, err := os.ReadFile(dtoPath)
	if err != nil {
		t.Fatalf("failed to read regenerated %s: %v", dtoPath, err)
	}

	if string(existingContent) != string(regeneratedContent) {
		t.Fatalf("%s is stale. Run 'go generate ./...' in app/ and commit changes.", dtoPath)
	}
}
