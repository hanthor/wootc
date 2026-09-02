// Code generated from payload/steps.tsv by gen-steps.py; DO NOT EDIT.

package main

// Step represents a step or phase in the unified step catalogue.
type Step struct {
	ID    string `json:"id"`
	Owner string `json:"owner"`
	Label string `json:"label"`
}

// AllSteps contains all steps across installer, deployer, and firstboot owners.
var AllSteps = []Step{
	{ID: "check-pc", Owner: "installer", Label: "Checking your PC"},
	{ID: "prepare-windows", Owner: "installer", Label: "Preparing Windows"},
	{ID: "setting-up", Owner: "installer", Label: "Setting things up"},
	{ID: "finding-files", Owner: "installer", Label: "Finding your files"},
	{ID: "make-room", Owner: "installer", Label: "Making room for Linux"},
	{ID: "download-linux", Owner: "installer", Label: "Downloading Linux"},
	{ID: "download-system", Owner: "installer", Label: "Downloading your Linux system"},
	{ID: "prepare-startup-menu", Owner: "installer", Label: "Preparing the startup menu"},
	{ID: "prepare-linux", Owner: "installer", Label: "Getting Linux prepared"},
	{ID: "make-bootable", Owner: "installer", Label: "Making Linux bootable on your machine"},
	{ID: "save-settings", Owner: "installer", Label: "Saving your settings"},
	{ID: "save-bitlocker-key", Owner: "installer", Label: "Saving your BitLocker recovery key"},
	{ID: "inspect-apps", Owner: "installer", Label: "Looking at your installed apps"},
	{ID: "check-signed-in-apps", Owner: "installer", Label: "Checking your signed-in apps"},
	{ID: "cloud-drives", Owner: "installer", Label: "Looking for your cloud drives"},
	{ID: "collect-look-wifi", Owner: "installer", Label: "Collecting your look and Wi-Fi"},
	{ID: "finishing-up", Owner: "installer", Label: "Finishing up"},
	{ID: "ntfs-mounted", Owner: "deployer", Label: "Preparing your disk..."},
	{ID: "scratch-setup", Owner: "deployer", Label: "Preparing your disk..."},
	{ID: "network-wait", Owner: "deployer", Label: "Waiting for a network connection - plug in a network cable if this takes a while..."},
	{ID: "bundle-ingest", Owner: "deployer", Label: "Loading your downloaded system - no internet needed..."},
	{ID: "registry-preflight", Owner: "deployer", Label: "Connecting to the software library..."},
	{ID: "fisherman", Owner: "deployer", Label: "Downloading and installing your Linux system..."},
	{ID: "verification", Owner: "deployer", Label: "Almost there - making sure everything is perfect..."},
	{ID: "reboot", Owner: "deployer", Label: "All set! Starting your new Linux system..."},
	{ID: "firstboot-evidence", Owner: "firstboot", Label: "Recording first-boot evidence"},
}

// InstallerStepLabels contains the ordered labels of Phase-1 installer steps.
var InstallerStepLabels = []string{
	"Checking your PC",
	"Preparing Windows",
	"Setting things up",
	"Finding your files",
	"Making room for Linux",
	"Downloading Linux",
	"Downloading your Linux system",
	"Preparing the startup menu",
	"Getting Linux prepared",
	"Making Linux bootable on your machine",
	"Saving your settings",
	"Saving your BitLocker recovery key",
	"Looking at your installed apps",
	"Checking your signed-in apps",
	"Looking for your cloud drives",
	"Collecting your look and Wi-Fi",
	"Finishing up",
}

// Step ID constants
const (
	StepCheckPC = "check-pc"
	StepPrepareWindows = "prepare-windows"
	StepSettingUp = "setting-up"
	StepFindingFiles = "finding-files"
	StepMakeRoom = "make-room"
	StepDownloadLinux = "download-linux"
	StepDownloadSystem = "download-system"
	StepPrepareStartupMenu = "prepare-startup-menu"
	StepPrepareLinux = "prepare-linux"
	StepMakeBootable = "make-bootable"
	StepSaveSettings = "save-settings"
	StepSaveBitLockerKey = "save-bitlocker-key"
	StepInspectApps = "inspect-apps"
	StepCheckSignedInApps = "check-signed-in-apps"
	StepCloudDrives = "cloud-drives"
	StepCollectLookWifi = "collect-look-wifi"
	StepFinishingUp = "finishing-up"
	StepNtfsMounted = "ntfs-mounted"
	StepScratchSetup = "scratch-setup"
	StepNetworkWait = "network-wait"
	StepBundleIngest = "bundle-ingest"
	StepRegistryPreflight = "registry-preflight"
	StepFisherman = "fisherman"
	StepVerification = "verification"
	StepReboot = "reboot"
	StepFirstbootEvidence = "firstboot-evidence"
)

// Step Label constants
const (
	StepLabelCheckPC = "Checking your PC"
	StepLabelPrepareWindows = "Preparing Windows"
	StepLabelSettingUp = "Setting things up"
	StepLabelFindingFiles = "Finding your files"
	StepLabelMakeRoom = "Making room for Linux"
	StepLabelDownloadLinux = "Downloading Linux"
	StepLabelDownloadSystem = "Downloading your Linux system"
	StepLabelPrepareStartupMenu = "Preparing the startup menu"
	StepLabelPrepareLinux = "Getting Linux prepared"
	StepLabelMakeBootable = "Making Linux bootable on your machine"
	StepLabelSaveSettings = "Saving your settings"
	StepLabelSaveBitLockerKey = "Saving your BitLocker recovery key"
	StepLabelInspectApps = "Looking at your installed apps"
	StepLabelCheckSignedInApps = "Checking your signed-in apps"
	StepLabelCloudDrives = "Looking for your cloud drives"
	StepLabelCollectLookWifi = "Collecting your look and Wi-Fi"
	StepLabelFinishingUp = "Finishing up"
	StepLabelNtfsMounted = "Preparing your disk..."
	StepLabelScratchSetup = "Preparing your disk..."
	StepLabelNetworkWait = "Waiting for a network connection - plug in a network cable if this takes a while..."
	StepLabelBundleIngest = "Loading your downloaded system - no internet needed..."
	StepLabelRegistryPreflight = "Connecting to the software library..."
	StepLabelFisherman = "Downloading and installing your Linux system..."
	StepLabelVerification = "Almost there - making sure everything is perfect..."
	StepLabelReboot = "All set! Starting your new Linux system..."
	StepLabelFirstbootEvidence = "Recording first-boot evidence"
)
