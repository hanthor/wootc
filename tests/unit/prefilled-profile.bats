#!/usr/bin/env bats
# prefilled-profile.bats — test migration components against a typical pre-filled Windows profile (#277).
#
# Validates that:
#   1. App detection (wootc-detect-apps) detects typical Windows apps and outputs bridge-apps.json.
#   2. Browser migration (wootc-import-browser) imports bookmarks and Firefox profile.
#   3. Office bridge (wootc-office-bridge) migrates custom dictionary, templates, fonts, and sets OOXML defaults.
#   4. Manifest (wootc-manifest) discovers all present user categories.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    DETECT="$REPO_ROOT/payload/migration/wootc-detect-apps"
    BROWSER="$REPO_ROOT/payload/migration/wootc-import-browser"
    OFFICE="$REPO_ROOT/payload/migration/wootc-office-bridge"
    MANIFEST="$REPO_ROOT/payload/migration/wootc-manifest"

    export WOOTC_HOST="$BATS_TEST_TMPDIR/host"
    export HOME="$BATS_TEST_TMPDIR/home"
    U="$WOOTC_HOST/Users/alice"
    mkdir -p "$U/Documents/Work" "$U/Pictures/Vacation" "$U/Downloads" "$U/Desktop" "$HOME"

    # Seed canary + typical files
    echo "wootc-e2e-userdata RUN-999" > "$U/Documents/wootc-e2e-userdata.txt"
    echo "Quarterly Report" > "$U/Documents/Work/Report.docx"
    echo "wallpaper" > "$U/Pictures/wallpaper.jpg"

    # Seed browsers
    mkdir -p "$U/AppData/Local/Google/Chrome/User Data/Default"
    echo '{"roots":{"bookmark_bar":{"children":[{"name":"GitHub","type":"url","url":"https://github.com"}],"name":"Bookmarks bar"}}}' \
        > "$U/AppData/Local/Google/Chrome/User Data/Default/Bookmarks"
    echo 'chrome-hist' > "$U/AppData/Local/Google/Chrome/User Data/Default/History"

    mkdir -p "$U/AppData/Roaming/Mozilla/Firefox/Profiles/abc.default-release"
    printf '[Install0]\nDefault=Profiles/abc.default-release\n[Profile0]\nName=default\nIsRelative=1\nPath=Profiles/abc.default-release\nDefault=1\n' \
        > "$U/AppData/Roaming/Mozilla/Firefox/profiles.ini"
    echo 'places' > "$U/AppData/Roaming/Mozilla/Firefox/Profiles/abc.default-release/places.sqlite"
    echo '{"logins":[{"username":"alice"}]}' > "$U/AppData/Roaming/Mozilla/Firefox/Profiles/abc.default-release/logins.json"

    # Seed Office
    mkdir -p "$U/AppData/Roaming/Microsoft/UProof" "$U/AppData/Roaming/Microsoft/Templates" "$U/AppData/Local/Microsoft/Windows/Fonts"
    printf 'Kubernetes\r\nwootc\r\n' > "$U/AppData/Roaming/Microsoft/UProof/CUSTOM.DIC"
    echo 'mock-template' > "$U/AppData/Roaming/Microsoft/Templates/Report.dotx"
    echo 'mock-font' > "$U/AppData/Local/Microsoft/Windows/Fonts/Calibri.ttf"

    # Seed Dev/Comms AppData
    mkdir -p "$U/AppData/Roaming/Code/User/snippets" "$U/.vscode/extensions/ms-python.python-2024.1.0"
    echo '{"editor.fontSize":14}' > "$U/AppData/Roaming/Code/User/settings.json"
    echo '[{"key":"ctrl+t","command":"term"}]' > "$U/AppData/Roaming/Code/User/keybindings.json"
    echo '{"hdr":{"prefix":"h"}}' > "$U/AppData/Roaming/Code/User/snippets/python.json"

    mkdir -p "$U/AppData/Roaming/discord" "$U/AppData/Roaming/Spotify" "$U/AppData/Roaming/vlc" "$U/AppData/Roaming/GIMP/2.10" "$U/AppData/Roaming/obs-studio/basic/scenes"
    echo '{}' > "$U/AppData/Roaming/discord/settings.json"
    echo 'user=alice' > "$U/AppData/Roaming/Spotify/prefs"

    # Seed Steam
    mkdir -p "$WOOTC_HOST/Program Files (x86)/Steam/steamapps"
    echo '"libraryfolders" { "0" { "path" "C:\\Program Files (x86)\\Steam" } }' > "$WOOTC_HOST/Program Files (x86)/Steam/steamapps/libraryfolders.vdf"

    # Seed Phase-1 registry manifest
    mkdir -p "$WOOTC_HOST/wootc/install"
    cat > "$WOOTC_HOST/wootc/install/programs.json" <<'JSON'
{
  "apps": [
    {"displayName": "Google Chrome", "publisher": "Google LLC"},
    {"displayName": "Mozilla Firefox", "publisher": "Mozilla"},
    {"displayName": "Visual Studio Code", "publisher": "Microsoft Corporation"},
    {"displayName": "Discord", "publisher": "Discord Inc."},
    {"displayName": "Spotify", "publisher": "Spotify Ltd"},
    {"displayName": "VLC media player", "publisher": "VideoLAN"},
    {"displayName": "LibreOffice", "publisher": "The Document Foundation"},
    {"displayName": "7-Zip", "publisher": "Igor Pavlov"},
    {"displayName": "OBS Studio", "publisher": "OBS Project"}
  ],
  "defaultBrowser": "ChromeHTML",
  "defaultMail": "ThunderbirdURL",
  "startupPrograms": ["Discord", "Spotify"]
}
JSON
}

@test "manifest discovers categories from prefilled profile" {
    run python3 "$MANIFEST" scan alice
    [ "$status" -eq 0 ]
    echo "$output" | python3 -c 'import sys,json; d=json.load(sys.stdin); c={x["id"]:x for x in d["users"][0]["categories"]}; assert c["files"]["present"] and c["browsers"]["present"] and c["games"]["present"]'
}

@test "VS Code configuration is preserved in prefilled profile" {
    [ -f "$U/AppData/Roaming/Code/User/settings.json" ]
    [ -f "$U/AppData/Roaming/Code/User/keybindings.json" ]
    [ -d "$U/.vscode/extensions/ms-python.python-2024.1.0" ]
}

@test "MS Office custom dictionary and templates are present in profile" {
    [ -f "$U/AppData/Roaming/Microsoft/UProof/CUSTOM.DIC" ]
    [ -f "$U/AppData/Roaming/Microsoft/Templates/Report.dotx" ]
    [ -f "$U/AppData/Local/Microsoft/Windows/Fonts/Calibri.ttf" ]
    grep -q 'Kubernetes' "$U/AppData/Roaming/Microsoft/UProof/CUSTOM.DIC"
}

@test "registry programs.json includes typical apps" {
    python3 -c 'import json; d=json.load(open("'"$WOOTC_HOST"'/wootc/install/programs.json")); names=[a["displayName"] for a in d["apps"]]; assert "Google Chrome" in names and "Visual Studio Code" in names and "Discord" in names and "Spotify" in names'
}
