#!/bin/bash
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
export GIT_TERMINAL_PROMPT=0
R="$HOME/Documents/TEMP-Verified"
B="$HOME/Library/Application Support/TEMP-FreshSync"
L="com.kingkat.temp-fresh-sync-v8"
P="$HOME/Library/LaunchAgents/$L.plist"
W="$B/worker.sh"
mkdir -p "$B" "$HOME/Library/LaunchAgents"
echo "TEMP — repairing stale Xcode build and background sync"
echo "Stopping earlier TEMP sync agents..."
for label in com.k1ngkat.temp.gitsync com.kingkat.temp-two-way-sync-v4 com.kingkat.temp-two-way-sync-v5 com.kingkat.temp-two-way-sync-v6 com.kingkat.temp-sync-v7 com.kingkat.temp-two-way-fresh "$L"; do
  p="$HOME/Library/LaunchAgents/$label.plist"
  launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1 || true
  if [[ -f "$p" ]]; then
    launchctl bootout "gui/$(id -u)" "$p" >/dev/null 2>&1 || true
    mv "$p" "$B/$label.$(date +%s).disabled"
  fi
done
echo "Asking Xcode to close safely before the refresh..."
osascript -e 'tell application "Xcode" to quit' >/dev/null 2>&1 || true
for i in {1..20}; do
  pgrep -x Xcode >/dev/null 2>&1 || break
  sleep 1
done
if pgrep -x Xcode >/dev/null 2>&1; then
  echo "Xcode is still open, likely waiting to save edits. Complete that prompt, then rerun this command. No project files were changed."
  exit 1
fi
[[ ! -L "$R" ]] || { echo "TEMP-Verified is a symlink; refusing to replace it."; exit 1; }
stage="$(mktemp -d "$HOME/Documents/.TEMP-refresh.XXXXXX")"
trap '[[ ! -d "$stage" ]] || rm -rf "$stage"' EXIT
echo "Cloning current TEMP main from GitHub..."
git clone --quiet --branch main --single-branch https://github.com/K1ng-Kat/TEMP.git "$stage/project"
grep -q compactSidebarOpen "$stage/project/TEMP/ContentView.swift" || { echo "Fresh redesign marker missing; original project untouched."; exit 1; }
grep -q 'Stop tracking (keep folder)' "$stage/project/TEMP/ContentView.swift" || { echo "Folder controls missing; original project untouched."; exit 1; }
[[ -d "$stage/project/TEMP.xcodeproj" ]] || { echo "Project missing from GitHub clone."; exit 1; }
if [[ -e "$R" ]]; then
  saved="$HOME/Documents/TEMP-Verified-Preserved-$(date +%Y%m%d-%H%M%S)-$$"
  mv "$R" "$saved"
  echo "Existing project BACKED UP at: $saved"
else
  saved=""
fi
if ! mv "$stage/project" "$R"; then
  [[ -z "$saved" ]] || mv "$saved" "$R" || true
  echo "Could not install current checkout; old project restored where possible."
  exit 1
fi
echo "Fresh checkout: $(git -C "$R" log -1 --oneline)"
echo "Clearing Xcode's old TEMP build cache..."
for d in "$HOME/Library/Developer/Xcode/DerivedData"/TEMP-*; do
  [[ ! -d "$d" ]] || rm -rf "$d"
done
xcode="/Applications/Xcode.app"
if [[ ! -d "$xcode/Contents/Developer" ]]; then
  xcode="$(mdfind 'kMDItemCFBundleIdentifier == "com.apple.dt.Xcode"' | head -n 1 || true)"
fi
if [[ -d "$xcode/Contents/Developer" ]]; then
  export DEVELOPER_DIR="$xcode/Contents/Developer"
  if xcodebuild -project "$R/TEMP.xcodeproj" -scheme TEMP -configuration Debug -destination 'platform=macOS' -derivedDataPath "$B/DerivedData" CODE_SIGNING_ALLOWED=NO clean build > "$B/build.log" 2>&1; then
    echo "✅ Latest TEMP compiled successfully."
    app="$B/DerivedData/Build/Products/Debug/TEMP.app"
    if [[ -x "$app/Contents/MacOS/TEMP" ]]; then
      codesign --force --sign - --entitlements "$R/TEMP/TEMP.entitlements" "$app" > "$B/sign.log" 2>&1 || true
      pkill -x TEMP >/dev/null 2>&1 || true
      open -n "$app" || true
    fi
  else
    echo "⚠️ Local build error; showing compiler diagnostics:"
    grep -E 'error:|BUILD FAILED' "$B/build.log" | tail -n 12 || true
    echo "Full build log: $B/build.log"
  fi
else
  echo "Full Xcode app was not found. The latest source is installed."
fi
echo "Installing a worker that reports the REAL Git error, not a generic message..."
cat > "$W" <<'WORKER'
#!/bin/bash
set -u
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
export GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=never
R="$HOME/Documents/TEMP-Verified"
B="$HOME/Library/Application Support/TEMP-FreshSync"
mkdir -p "$B"
LOG="$B/sync.log"
STATE="$B/state.txt"
LOCK="$B/worker.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  pid="$(cat "$LOCK/pid" 2>/dev/null || true)"
  if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then exit 0; fi
  rm -f "$LOCK/pid"; rmdir "$LOCK" 2>/dev/null || exit 0
  mkdir "$LOCK" 2>/dev/null || exit 0
fi
echo "$$" > "$LOCK/pid"
trap 'rm -f "$LOCK/pid"; rmdir "$LOCK" 2>/dev/null || true' EXIT
trap 'exit 0' TERM INT HUP
note() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; }
state() { echo "$*" > "$STATE"; }
sync_once() {
  local root info origin f gitdir
  if ! info="$(git -C "$R" rev-parse --show-toplevel 2>&1)"; then
    state "ERROR: Git access failed: $info"
    note "$info"
    ls -ld "$R" "$R/.git" >> "$LOG" 2>&1 || true
    return 1
  fi
  root="$(cd "$info" && pwd -P)"
  [[ "$root" == "$(cd "$R" && pwd -P)" ]] || { state "PAUSED: unexpected Git root"; return 1; }
  [[ "$(git -C "$R" branch --show-current)" == main ]] || { state "PAUSED: branch is not main"; return 1; }
  origin="$(git -C "$R" remote get-url origin 2>/dev/null || true)"
  case "$origin" in
    https://github.com/K1ng-Kat/TEMP|https://github.com/K1ng-Kat/TEMP.git|git@github.com:K1ng-Kat/TEMP|git@github.com:K1ng-Kat/TEMP.git) ;;
    *) state "PAUSED: unexpected GitHub origin"; return 1 ;;
  esac
  gitdir="$(git -C "$R" rev-parse --absolute-git-dir)" || return 1
  [[ ! -e "$gitdir/index.lock" && ! -f "$gitdir/MERGE_HEAD" && ! -d "$gitdir/rebase-merge" ]] || { state "WAITING: Git operation in progress"; return 1; }
  mkdir -p "$gitdir/info"
  if ! grep -q '^# TEMP auto-sync privacy guard$' "$gitdir/info/exclude" 2>/dev/null; then
    cat >> "$gitdir/info/exclude" <<'EXCLUDE'

# TEMP auto-sync privacy guard
.env
.env.*
*.p8
*.p12
*.pem
*.key
*.mobileprovision
*.private.xcconfig
credentials.json
secrets.json
DerivedData/
build/
xcuserdata/
.DS_Store
EXCLUDE
  fi
  git -C "$R" add -A >> "$LOG" 2>&1 || { state "WAITING: Git staging failed"; return 1; }
  while IFS= read -r -d '' f; do
    case "$(basename "$f")" in
      .env|.env.*|*.p8|*.p12|*.pem|*.key|*.mobileprovision|*.private.xcconfig|credentials.json|secrets.json)
        state "PAUSED: private file staged: $f"; return 1 ;;
    esac
  done < <(git -C "$R" diff --cached --name-only -z)
  if ! git -C "$R" diff --cached --quiet; then
    git -C "$R" -c user.name="TEMP Sync" -c user.email="temp-sync@users.noreply.github.com" commit -qm "TEMP auto-sync $(date '+%F %T')" >> "$LOG" 2>&1 || { state "WAITING: commit failed"; return 1; }
    note "Saved local Xcode edits"
  fi
  git -C "$R" fetch -q origin main >> "$LOG" 2>&1 || { state "WAITING: GitHub fetch/auth failed"; return 1; }
  if git -C "$R" merge-base --is-ancestor HEAD origin/main; then
    git -C "$R" merge --ff-only origin/main >> "$LOG" 2>&1 || { state "PAUSED: fast-forward failed"; return 1; }
  elif ! git -C "$R" merge-base --is-ancestor origin/main HEAD; then
    if ! git -C "$R" -c user.name="TEMP Sync" -c user.email="temp-sync@users.noreply.github.com" merge --no-edit origin/main >> "$LOG" 2>&1; then
      git -C "$R" merge --abort >> "$LOG" 2>&1 || true
      state "CONFLICT: both versions preserved; resolve in Git"
      return 1
    fi
  fi
  if [[ "$(git -C "$R" rev-parse HEAD)" != "$(git -C "$R" rev-parse origin/main)" ]]; then
    git -C "$R" push -q origin HEAD:main >> "$LOG" 2>&1 || { state "WAITING: push failed; local commit saved"; return 1; }
    note "Pushed local commits"
  fi
  state "SYNCED $(date '+%F %T') | $(git -C "$R" rev-parse --short HEAD)"
}
last=0
failed=0
while :; do
  now="$(date +%s)"
  dirty="$(git -C "$R" status --porcelain 2>/dev/null || true)"
  if (( now-last>=12 )) || [[ -n "$dirty" ]]; then
    if (( failed==0 || now-failed>=25 )); then
      if sync_once; then failed=0; else failed=$now; fi
      last=$now
    fi
  fi
  sleep 3
done
WORKER
chmod 700 "$W"
cat > "$P" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$L</string>
<key>ProgramArguments</key><array><string>/bin/bash</string><string>$W</string></array>
<key>RunAtLoad</key><true/>
<key>KeepAlive</key><true/>
<key>StandardOutPath</key><string>$B/stdout.log</string>
<key>StandardErrorPath</key><string>$B/stderr.log</string>
</dict></plist>
PLIST
plutil -lint "$P" >/dev/null
launchctl bootstrap "gui/$(id -u)" "$P" || echo "Watcher couldn't start; see $B/stderr.log"
sleep 3
open -a Xcode "$R/TEMP.xcodeproj"
echo "══════════ TEMP STATUS ══════════"
echo "Project: $R"
echo "GitHub: $(git -C "$R" log -1 --oneline)"
echo "Watcher: $(cat "$B/state.txt" 2>/dev/null || echo 'Starting...')"
echo "Logs: $B"
echo "Fresh Xcode project opened. Use Run (⌘R) to launch the updated app."
