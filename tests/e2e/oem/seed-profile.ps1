# seed-profile.ps1
# Populates a comprehensive, realistic "typical" Windows user profile for testing wootc.
#
# Covers:
#   1. Standard personal folders (Documents, Pictures, Downloads, Music, Videos, Desktop)
#   2. Browser profiles & preferences (Google Chrome, Microsoft Edge, Mozilla Firefox)
#   3. MS Office / Productivity components (Custom dictionary, templates, fonts, autocorrect)
#   4. Developer & productivity applications (VS Code settings/keybindings/snippets/extensions,
#      Discord, Spotify, Telegram Desktop, VLC, GIMP, OBS Studio, Steam library, Git config)
#   5. Windows Registry entries (Installed apps in Uninstall keys, URL associations, Run startup keys, Theme/Accent color)
#   6. Canary marker wootc-e2e-userdata.txt for E2E persistence assertions

param(
    [string]$Username = "wootc",
    [string]$Drive = "C:",
    [string]$RunId = "test-run",
    [switch]$IncludeRegistry = $true
)

$ErrorActionPreference = "Stop"

if (-not $Drive.EndsWith(":")) {
    $Drive = "${Drive}:"
}

$userProfile = "$Drive\Users\$Username"
$appDataRoaming = "$userProfile\AppData\Roaming"
$appDataLocal = "$userProfile\AppData\Local"

Write-Host "[seed-profile] Seeding pre-filled Windows profile for '$Username' at '$userProfile' (RunId: $RunId)..."

function Ensure-Directory([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Write-TextFile([string]$Path, [string]$Content, [string]$Encoding = "UTF8") {
    $parent = Split-Path -Parent $Path
    Ensure-Directory $parent
    Set-Content -LiteralPath $Path -Value $Content -Encoding $Encoding -Force
}

# ── 1. Standard Personal Folders ─────────────────────────────────────────────
$docsDir = "$userProfile\Documents"
$picsDir = "$userProfile\Pictures"
$downDir = "$userProfile\Downloads"
$musicDir = "$userProfile\Music"
$videoDir = "$userProfile\Videos"
$deskDir = "$userProfile\Desktop"

Ensure-Directory $docsDir
Ensure-Directory $picsDir
Ensure-Directory $downDir
Ensure-Directory $musicDir
Ensure-Directory $videoDir
Ensure-Directory $deskDir

# Canary marker required by E2E runner for data persistence proof
Write-TextFile "$docsDir\wootc-e2e-userdata.txt" "wootc-e2e-userdata $RunId" "ASCII"

# Realistic documents and files
Write-TextFile "$docsDir\Work\Quarterly_Report.docx" "Fake Word Document Content for Quarterly Report"
Write-TextFile "$docsDir\Work\Notes.txt" "Meeting notes: Linux migration plan and requirements."
Write-TextFile "$docsDir\Finance\2025_Tax_Return.pdf" "%PDF-1.4 Mock Tax Return PDF Document Content"
Write-TextFile "$docsDir\Projects\wootc-notes.md" "# wootc Notes`nTesting with pre-filled Windows profile."

Write-TextFile "$picsDir\wallpaper.jpg" "JPEG_MOCK_IMAGE_DATA_WALLPAPER" "ASCII"
Write-TextFile "$picsDir\Vacation\beach.jpg" "JPEG_MOCK_IMAGE_DATA_VACATION" "ASCII"
Write-TextFile "$picsDir\Screenshots\screenshot_01.png" "PNG_MOCK_IMAGE_DATA_SCREENSHOT" "ASCII"

Write-TextFile "$downDir\sample_installer.exe" "MOCK_EXE_BINARY_DATA" "ASCII"
Write-TextFile "$downDir\dataset.zip" "PK_ZIP_MOCK_ARCHIVE_DATA" "ASCII"

Write-TextFile "$musicDir\SampleArtist - SampleSong.mp3" "MOCK_MP3_AUDIO_DATA" "ASCII"
Write-TextFile "$videoDir\family_trip.mp4" "MOCK_MP4_VIDEO_DATA" "ASCII"
Write-TextFile "$deskDir\Daily_Tasks.txt" "1. Check emails`n2. Test wootc migration`n3. Review Linux apps"

# ── 2. Browser Profiles & Preferences ────────────────────────────────────────
# Google Chrome
$chromeUserData = "$appDataLocal\Google\Chrome\User Data\Default"
Ensure-Directory $chromeUserData
$chromeBookmarksJson = @'
{
  "checksum": "d41d8cd98f00b204e9800998ecf8427e",
  "roots": {
    "bookmark_bar": {
      "children": [
        {
          "date_added": "13300000000000000",
          "id": "1",
          "name": "GitHub - TunaOS",
          "type": "url",
          "url": "https://github.com/tuna-os/wootc"
        },
        {
          "date_added": "13300000000000001",
          "id": "2",
          "name": "Linux Documentation",
          "type": "url",
          "url": "https://docs.kernel.org"
        },
        {
          "children": [
            {
              "date_added": "13300000000000002",
              "id": "4",
              "name": "DuckDuckGo",
              "type": "url",
              "url": "https://duckduckgo.com"
            }
          ],
          "date_added": "13300000000000003",
          "id": "3",
          "name": "Dev Tools",
          "type": "folder"
        }
      ],
      "date_added": "13300000000000000",
      "id": "0",
      "name": "Bookmarks bar",
      "type": "folder"
    },
    "other": { "children": [], "date_added": "0", "id": "other", "name": "Other bookmarks", "type": "folder" },
    "synced": { "children": [], "date_added": "0", "id": "synced", "name": "Mobile bookmarks", "type": "folder" }
  },
  "version": 1
}
'@
Write-TextFile "$chromeUserData\Bookmarks" $chromeBookmarksJson
Write-TextFile "$chromeUserData\History" "SQLite format 3 - Mock Chrome History Database" "ASCII"
Write-TextFile "$chromeUserData\Preferences" '{"browser":{"show_home_button":true}}'

# Microsoft Edge
$edgeUserData = "$appDataLocal\Microsoft\Edge\User Data\Default"
Ensure-Directory $edgeUserData
Write-TextFile "$edgeUserData\Bookmarks" $chromeBookmarksJson
Write-TextFile "$edgeUserData\History" "SQLite format 3 - Mock Edge History Database" "ASCII"

# Mozilla Firefox
$firefoxDir = "$appDataRoaming\Mozilla\Firefox"
$firefoxProfileRel = "Profiles/typical.default-release"
$firefoxProfileDir = "$firefoxDir\$firefoxProfileRel"
Ensure-Directory $firefoxProfileDir

$firefoxProfilesIni = @"
[Install0]
Default=$firefoxProfileRel

[Profile0]
Name=default
IsRelative=1
Path=$firefoxProfileRel
Default=1

[General]
StartWithLastProfile=1
Version=2
"@
Write-TextFile "$firefoxDir\profiles.ini" $firefoxProfilesIni
Write-TextFile "$firefoxProfileDir\places.sqlite" "SQLite format 3 - Mock Firefox Places History/Bookmarks" "ASCII"
$firefoxLoginsJson = @'
{
  "nextId": 2,
  "logins": [
    {
      "id": 1,
      "hostname": "https://github.com",
      "httpRealm": null,
      "formSubmitURL": "https://github.com/session",
      "usernameField": "login",
      "passwordField": "password",
      "encryptedUsername": "alice",
      "encryptedPassword": "password123",
      "guid": "{11111111-2222-3333-4444-555555555555}"
    }
  ],
  "version": 3
}
'@
Write-TextFile "$firefoxProfileDir\logins.json" $firefoxLoginsJson
Write-TextFile "$firefoxProfileDir\prefs.js" 'user_pref("browser.startup.homepage", "https://github.com/tuna-os/wootc");'
Write-TextFile "$firefoxProfileDir\extensions.json" '{"addons":[{"id":"uBlock0@raymondhill.net","name":"uBlock Origin"}]}'

# ── 3. MS Office / Productivity Components ──────────────────────────────────
$uproofDir = "$appDataRoaming\Microsoft\UProof"
Ensure-Directory $uproofDir
# CUSTOM.DIC with CRLF
Write-TextFile "$uproofDir\CUSTOM.DIC" "Kubernetes`r`nwootc`r`nTunaOS`r`ncontainerd`r`nMicroOS`r`n" "UTF8"

$templatesDir = "$appDataRoaming\Microsoft\Templates"
Ensure-Directory $templatesDir
Write-TextFile "$templatesDir\Report.dotx" "MOCK_WORD_TEMPLATE_DATA_REPORT" "ASCII"
Write-TextFile "$templatesDir\Invoice.xltx" "MOCK_EXCEL_TEMPLATE_DATA_INVOICE" "ASCII"
Write-TextFile "$templatesDir\Presentation.potx" "MOCK_POWERPOINT_TEMPLATE_DATA" "ASCII"

$officeDir = "$appDataRoaming\Microsoft\Office"
Ensure-Directory $officeDir
# default.acl: UTF-16LE with sample replacement pairs (e.g. tehm => them, teh => the)
$aclBytes = [System.Text.Encoding]::Unicode.GetBytes("tehm`0them`0teh`0the`0woot`0wootc`0")
[System.IO.File]::WriteAllBytes("$officeDir\default.acl", $aclBytes)

$fontsDir = "$appDataLocal\Microsoft\Windows\Fonts"
Ensure-Directory $fontsDir
Write-TextFile "$fontsDir\Calibri.ttf" "MOCK_TRUETYPE_FONT_CALIBRI" "ASCII"
Write-TextFile "$fontsDir\Cambria.ttf" "MOCK_TRUETYPE_FONT_CAMBRIA" "ASCII"

# ── 4. Developer & Creative & Comms Applications ────────────────────────────
# VS Code
$vscUserDir = "$appDataRoaming\Code\User"
$vscSnippetsDir = "$vscUserDir\snippets"
Ensure-Directory $vscSnippetsDir
$vscSettings = @'
{
  "editor.fontSize": 14,
  "editor.tabSize": 4,
  "editor.renderWhitespace": "selection",
  "workbench.colorTheme": "Default Dark+",
  "files.autoSave": "afterDelay"
}
'@
$vscKeybindings = @'
[
  {
    "key": "ctrl+shift+t",
    "command": "workbench.action.terminal.toggleTerminal"
  }
]
'@
$vscSnippet = @'
{
  "Header": {
    "prefix": "docheader",
    "body": [
      "# -*- coding: utf-8 -*-",
      "\"\"\"$TM_FILENAME: ${1:Description}\"\"\""
    ]
  }
}
'@
Write-TextFile "$vscUserDir\settings.json" $vscSettings
Write-TextFile "$vscUserDir\keybindings.json" $vscKeybindings
Write-TextFile "$vscSnippetsDir\python.json" $vscSnippet

$vscExtDir = "$userProfile\.vscode\extensions"
Ensure-Directory "$vscExtDir\ms-python.python-2024.1.0"
Ensure-Directory "$vscExtDir\golang.go-0.41.0"
Write-TextFile "$vscExtDir\ms-python.python-2024.1.0\package.json" '{"name":"python","publisher":"ms-python","version":"2024.1.0"}'
Write-TextFile "$vscExtDir\golang.go-0.41.0\package.json" '{"name":"go","publisher":"golang","version":"0.41.0"}'

# Comms apps
Ensure-Directory "$appDataRoaming\discord"
Write-TextFile "$appDataRoaming\discord\settings.json" '{"DCA_USER_SETTINGS":{"theme":"dark"}}'

Ensure-Directory "$appDataRoaming\Slack"
Write-TextFile "$appDataRoaming\Slack\storage.json" '{"teams":{}}'

Ensure-Directory "$appDataRoaming\Spotify"
Write-TextFile "$appDataRoaming\Spotify\prefs" 'autologin.username="alice"'

Ensure-Directory "$appDataRoaming\Telegram Desktop\tdata"
Write-TextFile "$appDataRoaming\Telegram Desktop\tdata\settingss" "MOCK_TELEGRAM_TDATA_PAYLOAD" "ASCII"

# Media / Creative apps
Ensure-Directory "$appDataRoaming\vlc"
Write-TextFile "$appDataRoaming\vlc\vlcrc" "volume=256`n[main]`n"

Ensure-Directory "$appDataRoaming\GIMP\2.10"
Write-TextFile "$appDataRoaming\GIMP\2.10\gimprc" "(language `"en`")`n"

Ensure-Directory "$appDataRoaming\obs-studio\basic\scenes"
Write-TextFile "$appDataRoaming\obs-studio\basic\scenes\default.json" '{"name":"Default Scene"}'

# Git config
Write-TextFile "$userProfile\.gitconfig" "[user]`n`tname = $Username`n`temail = ${Username}@example.com`n"

# Steam default library & extra library
$steamProgramFiles = "$Drive\Program Files (x86)\Steam"
Ensure-Directory "$steamProgramFiles\steamapps\common\HL3"
$steamLibraryVdf = @"
"libraryfolders"
{
	"0"
	{
		"path"		"$($steamProgramFiles.Replace('\', '\\'))"
	}
	"1"
	{
		"path"		"$($Drive.Replace('\', '\\'))\\Games\\SteamLibrary"
	}
}
"@
Write-TextFile "$steamProgramFiles\steamapps\libraryfolders.vdf" $steamLibraryVdf "ASCII"
Ensure-Directory "$Drive\Games\SteamLibrary\steamapps\common\Portal9"
Write-TextFile "$steamProgramFiles\steamapps\common\HL3\hl3.exe" "MOCK_STEAM_GAME_EXE" "ASCII"
Write-TextFile "$Drive\Games\SteamLibrary\steamapps\common\Portal9\portal9.exe" "MOCK_STEAM_GAME_EXE" "ASCII"

# ── 5. Windows Registry Entries (Installed Apps, Associations, Theme) ────────
if ($IncludeRegistry) {
    try {
        Write-Host "[seed-profile] Seeding Windows registry entries for installed apps and associations..."

        # Uninstall keys in HKCU
        $appsToRegister = @(
            @{ Key = "GoogleChrome"; Name = "Google Chrome"; Pub = "Google LLC"; Loc = "$Drive\Program Files\Google\Chrome\Application"; Ver = "124.0.6367.201" },
            @{ Key = "MozillaFirefox"; Name = "Mozilla Firefox"; Pub = "Mozilla"; Loc = "$Drive\Program Files\Mozilla Firefox"; Ver = "125.0.3" },
            @{ Key = "VSCode"; Name = "Microsoft Visual Studio Code"; Pub = "Microsoft Corporation"; Loc = "$appDataLocal\Programs\Microsoft VS Code"; Ver = "1.89.1" },
            @{ Key = "Discord"; Name = "Discord"; Pub = "Discord Inc."; Loc = "$appDataLocal\Discord\app-1.0.9038"; Ver = "1.0.9038" },
            @{ Key = "Spotify"; Name = "Spotify"; Pub = "Spotify Ltd"; Loc = "$appDataRoaming\Spotify"; Ver = "1.2.37.701" },
            @{ Key = "VLC"; Name = "VLC media player"; Pub = "VideoLAN"; Loc = "$Drive\Program Files\VideoLAN\VLC"; Ver = "3.0.20" },
            @{ Key = "MicrosoftOffice"; Name = "Microsoft Office 365 - en-us"; Pub = "Microsoft Corporation"; Loc = "$Drive\Program Files\Microsoft Office\root\Office16"; Ver = "16.0.17531.20120" },
            @{ Key = "Steam"; Name = "Steam"; Pub = "Valve Corporation"; Loc = $steamProgramFiles; Ver = "2.10.91.91" },
            @{ Key = "GIMP"; Name = "GIMP 2.10.36"; Pub = "The GIMP Team"; Loc = "$Drive\Program Files\GIMP 2"; Ver = "2.10.36" },
            @{ Key = "OBSStudio"; Name = "OBS Studio"; Pub = "OBS Project"; Loc = "$Drive\Program Files\obs-studio"; Ver = "30.1.2" },
            @{ Key = "7Zip"; Name = "7-Zip 23.01 (x64)"; Pub = "Igor Pavlov"; Loc = "$Drive\Program Files\7-Zip"; Ver = "23.01" },
            @{ Key = "TelegramDesktop"; Name = "Telegram Desktop"; Pub = "Telegram FZ-LLC"; Loc = "$appDataRoaming\Telegram Desktop"; Ver = "4.16.8" }
        )

        $hkcuUninstall = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
        Ensure-Directory $hkcuUninstall
        foreach ($app in $appsToRegister) {
            $regPath = "$hkcuUninstall\$($app.Key)"
            if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
            Set-ItemProperty -Path $regPath -Name "DisplayName" -Value $app.Name -Force
            Set-ItemProperty -Path $regPath -Name "Publisher" -Value $app.Pub -Force
            Set-ItemProperty -Path $regPath -Name "InstallLocation" -Value $app.Loc -Force
            Set-ItemProperty -Path $regPath -Name "DisplayVersion" -Value $app.Ver -Force
            Set-ItemProperty -Path $regPath -Name "UninstallString" -Value "$($app.Loc)\uninstall.exe" -Force
        }

        # URL Associations (Default browser = Chrome, default mail = Thunderbird)
        $assocHttp = "HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice"
        $assocHttps = "HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice"
        $assocMail = "HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\mailto\UserChoice"

        Ensure-Directory $assocHttp
        Ensure-Directory $assocHttps
        Ensure-Directory $assocMail
        Set-ItemProperty -Path $assocHttp -Name "ProgId" -Value "ChromeHTML" -Force
        Set-ItemProperty -Path $assocHttps -Name "ProgId" -Value "ChromeHTML" -Force
        Set-ItemProperty -Path $assocMail -Name "ProgId" -Value "ThunderbirdURL" -Force

        # Run keys
        $runKey = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
        Ensure-Directory $runKey
        Set-ItemProperty -Path $runKey -Name "Discord" -Value "$appDataLocal\Discord\Update.exe --processStart Discord.exe" -Force
        Set-ItemProperty -Path $runKey -Name "Spotify" -Value "$appDataRoaming\Spotify\Spotify.exe" -Force
        Set-ItemProperty -Path $runKey -Name "Steam" -Value "$steamProgramFiles\steam.exe -silent" -Force

        # Theme / Personalization
        $themeKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
        Ensure-Directory $themeKey
        Set-ItemProperty -Path $themeKey -Name "AppsUseLightTheme" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $themeKey -Name "SystemUsesLightTheme" -Value 0 -Type DWord -Force

        $dwmKey = "HKCU:\Software\Microsoft\Windows\DWM"
        Ensure-Directory $dwmKey
        Set-ItemProperty -Path $dwmKey -Name "AccentColor" -Value 0x422de6 -Type DWord -Force
    } catch {
        Write-Host "[seed-profile] Warning: Could not set some registry keys: $($_.Exception.Message)"
    }
}

Write-Host "[seed-profile] Profile seeding complete for '$Username'."
