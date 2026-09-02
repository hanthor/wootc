package main

import (
	"testing"
)

func TestStepCatalogue_AllStepsWellFormed(t *testing.T) {
	if len(AllSteps) == 0 {
		t.Fatal("AllSteps is empty")
	}

	seenIDs := make(map[string]bool)
	for _, s := range AllSteps {
		if s.ID == "" {
			t.Errorf("Step with empty ID found: %+v", s)
		}
		if s.Label == "" {
			t.Errorf("Step %s has empty label", s.ID)
		}
		switch s.Owner {
		case "installer", "deployer", "firstboot":
			// valid
		default:
			t.Errorf("Step %s has invalid owner: %q", s.ID, s.Owner)
		}
		if seenIDs[s.ID] {
			t.Errorf("Duplicate step ID in AllSteps: %s", s.ID)
		}
		seenIDs[s.ID] = true
	}
}

func TestStepCatalogue_InstallerStepsParity(t *testing.T) {
	var expectedLabels []string
	for _, s := range AllSteps {
		if s.Owner == "installer" {
			expectedLabels = append(expectedLabels, s.Label)
		}
	}

	if len(InstallerStepLabels) != len(expectedLabels) {
		t.Fatalf("InstallerStepLabels count (%d) != expected installer steps (%d)",
			len(InstallerStepLabels), len(expectedLabels))
	}

	for i, label := range expectedLabels {
		if InstallerStepLabels[i] != label {
			t.Errorf("InstallerStepLabels[%d] = %q, want %q", i, InstallerStepLabels[i], label)
		}
	}

	// Verify App.GetInstallSteps() returns the identical slice
	a := &App{}
	appSteps := a.GetInstallSteps()
	if len(appSteps) != len(expectedLabels) {
		t.Fatalf("GetInstallSteps() count (%d) != expected (%d)", len(appSteps), len(expectedLabels))
	}
	for i, label := range expectedLabels {
		if appSteps[i] != label {
			t.Errorf("GetInstallSteps()[%d] = %q, want %q", i, appSteps[i], label)
		}
	}
}

func TestStepCatalogue_ConstantsMatch(t *testing.T) {
	// Verify key constants generated from payload/steps.tsv
	if StepCheckPC != "check-pc" || StepLabelCheckPC != "Checking your PC" {
		t.Errorf("StepCheckPC mismatch: %s / %s", StepCheckPC, StepLabelCheckPC)
	}
	if StepMakeBootable != "make-bootable" || StepLabelMakeBootable != "Making Linux bootable on your machine" {
		t.Errorf("StepMakeBootable mismatch: %s / %s", StepMakeBootable, StepLabelMakeBootable)
	}
	if StepFisherman != "fisherman" || StepLabelFisherman != "Downloading and installing your Linux system..." {
		t.Errorf("StepFisherman mismatch: %s / %s", StepFisherman, StepLabelFisherman)
	}
	if StepFirstbootEvidence != "firstboot-evidence" || StepLabelFirstbootEvidence != "Recording first-boot evidence" {
		t.Errorf("StepFirstbootEvidence mismatch: %s / %s", StepFirstbootEvidence, StepLabelFirstbootEvidence)
	}
}
