#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Batch-setup GitHub self-hosted runners (one runner per repo, separate folders/services).

Usage:
  setup-github-runners-batch.sh -o OWNER -r "repo1,repo2,repo3" [options]
  setup-github-runners-batch.sh -o OWNER -r "repo1 repo2 repo3" [options]

Required:
  -o OWNER            GitHub username (repo owner)
  -r REPOS            Repo list (comma or space separated)

Options:
  -b BASE_DIR         Base directory to place runner folders
                      (default: $HOME/github-runners)
  -l LABELS           Runner labels
                      (default: self-hosted,<auto-os>,<auto-arch>)
  -v VERSION          actions/runner version (default: 2.319.1)
  -w WORK_DIR         Work folder name inside each runner dir (default: _work)
  --no-service        Only configure; do not install/start runner service
  --force             Reconfigure even if already configured (removes existing config)
  -h                  Help

Examples:
  ./setup-github-runners-batch.sh -o myuser -r "repo-a,repo-b,repo-c"
  ./setup-github-runners-batch.sh -o myuser -r "repo-a repo-b" -l "self-hosted,linux,homelab"
  ./setup-github-runners-batch.sh -o myuser -r "repo-a" --force
EOF
}

detect_platform() {
  local uname_s uname_m

  uname_s="$(uname -s)"
  uname_m="$(uname -m)"

  case "$uname_s" in
    Linux)
      RUNNER_OS="linux"
      LABEL_OS="linux"
      ;;
    Darwin)
      RUNNER_OS="osx"
      LABEL_OS="macos"
      ;;
    *)
      echo "ERROR: Unsupported OS: $uname_s"
      echo "Supported OSes: Linux, macOS"
      exit 1
      ;;
  esac

  case "$uname_m" in
    x86_64|amd64)
      RUNNER_ARCH="x64"
      ;;
    arm64|aarch64)
      RUNNER_ARCH="arm64"
      ;;
    *)
      echo "ERROR: Unsupported architecture: $uname_m"
      echo "Supported architectures: x86_64/amd64, arm64/aarch64"
      exit 1
      ;;
  esac

  RUNNER_ASSET_BASENAME="actions-runner-${RUNNER_OS}-${RUNNER_ARCH}-${RUNNER_VERSION}"
}

OWNER=""
REPOS_RAW=""
BASE="$HOME/github-runners"
LABELS=""
RUNNER_VERSION="2.319.1"
WORK_DIR="_work"
DO_SERVICE=1
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) OWNER="${2:-}"; shift 2 ;;
    -r) REPOS_RAW="${2:-}"; shift 2 ;;
    -b) BASE="${2:-}"; shift 2 ;;
    -l) LABELS="${2:-}"; shift 2 ;;
    -v) RUNNER_VERSION="${2:-}"; shift 2 ;;
    -w) WORK_DIR="${2:-}"; shift 2 ;;
    --no-service) DO_SERVICE=0; shift ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

if [[ -z "$OWNER" || -z "$REPOS_RAW" ]]; then
  echo "ERROR: -o OWNER and -r REPOS are required."
  usage
  exit 1
fi

detect_platform

if [[ -z "$LABELS" ]]; then
  LABELS="self-hosted,${LABEL_OS},${RUNNER_ARCH}"
fi

run_service() {
  if [[ "$RUNNER_OS" == "linux" ]]; then
    sudo ./svc.sh "$@"
  else
    ./svc.sh "$@"
  fi
}

macos_service_plist_path() {
  printf '%s/Library/LaunchAgents/actions.runner.%s-%s.%s.plist' \
    "$HOME" "$OWNER" "$1" "$2"
}

cleanup_macos_service_artifacts() {
  local repo_name runner_name plist_path user_domain

  if [[ "$RUNNER_OS" != "osx" ]]; then
    return
  fi

  repo_name="$1"
  runner_name="$2"
  plist_path=""
  user_domain="gui/$(id -u)"

  if [[ -f ".service" ]]; then
    plist_path="$(< .service)"
  else
    plist_path="$(macos_service_plist_path "$repo_name" "$runner_name")"
  fi

  if [[ -n "$plist_path" && -f "$plist_path" ]]; then
    launchctl bootout "$user_domain" "$plist_path" >/dev/null 2>&1 || true
    rm -f "$plist_path"
  fi

  rm -f .service
}

verify_and_fix_macos_service() {
  local plist_path user_domain

  if [[ "$RUNNER_OS" != "osx" ]]; then
    return 0
  fi

  user_domain="gui/$(id -u)"
  
  if [[ -f ".service" ]]; then
    plist_path="$(< .service)"
  else
    return 0
  fi

  if [[ ! -f "$plist_path" ]]; then
    echo "ERROR: plist file not found at $plist_path"
    return 1
  fi

  # Fix permissions on plist
  chmod 644 "$plist_path"

  # Verify runsvc.sh exists and is executable
  if [[ ! -x "./runsvc.sh" ]]; then
    if [[ -f "./runsvc.sh" ]]; then
      chmod +x ./runsvc.sh
    else
      echo "ERROR: runsvc.sh not found in $(pwd)"
      return 1
    fi
  fi

  return 0
}

# Dependencies
for cmd in curl tar gh jq; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "ERROR: Missing dependency: $cmd"
    echo "Ubuntu/Debian: sudo apt update && sudo apt install -y gh jq curl tar"
    echo "macOS (Homebrew): brew install gh jq"
    exit 1
  }
done

# Make sure gh is authenticated
if ! gh auth status >/dev/null 2>&1; then
  echo "ERROR: GitHub CLI not authenticated."
  echo "Run: gh auth login"
  exit 1
fi

mkdir -p "$BASE"

# Normalize repos: commas -> spaces, split on whitespace
REPOS_RAW="${REPOS_RAW//,/ }"
read -r -a REPOS <<< "$REPOS_RAW"
if [[ ${#REPOS[@]} -eq 0 ]]; then
  echo "ERROR: No repos parsed from -r."
  exit 1
fi

# Cache runner tarball once
CACHE_DIR="$BASE/_runner_cache/$RUNNER_VERSION"
RUNNER_TGZ="$CACHE_DIR/${RUNNER_ASSET_BASENAME}.tar.gz"
mkdir -p "$CACHE_DIR"

if [[ ! -f "$RUNNER_TGZ" ]]; then
  echo "Downloading actions/runner v$RUNNER_VERSION for ${RUNNER_OS}/${RUNNER_ARCH} into cache..."
  curl -fsSL -o "$RUNNER_TGZ" \
    "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${RUNNER_ASSET_BASENAME}.tar.gz"
fi

for REPO in "${REPOS[@]}"; do
  REPO="$(echo "$REPO" | xargs)" # trim
  [[ -z "$REPO" ]] && continue

  echo "=== Setting up runner for $OWNER/$REPO ==="

  DIR="$BASE/$REPO"
  mkdir -p "$DIR"
  cd "$DIR"

  # Unique name per repo (helps in GitHub UI)
  NAME="$(hostname)-$REPO"

  # If already configured
  if [[ -f ".runner" && "$FORCE" -eq 0 ]]; then
    echo "Already configured in $DIR (found .runner). Skipping."
    echo
    continue
  fi

  # If forcing, remove old config cleanly if possible
  if [[ -f ".runner" && "$FORCE" -eq 1 ]]; then
    echo "--force: attempting to remove existing runner configuration..."

    if [[ "$DO_SERVICE" -eq 1 && -f "./svc.sh" ]]; then
      run_service stop || true
      run_service uninstall || true
      cleanup_macos_service_artifacts "$REPO" "$NAME"
    fi

    # Use remove-token endpoint for clean removal
    # (requires admin access on repo)
    REMOVE_TOKEN="$(gh api -X POST "repos/$OWNER/$REPO/actions/runners/remove-token" --jq .token)"
    ./config.sh remove --token "$REMOVE_TOKEN" || true

    # Keep files, but ensure config is gone
    rm -f .runner .credentials .credentials_rsaparams || true
  fi

  # Extract runner files if missing
  if [[ ! -f "./config.sh" ]]; then
    echo "Extracting runner binaries into $DIR..."
    tar xzf "$RUNNER_TGZ"
  fi

  # Create a short-lived registration token
  TOKEN="$(gh api -X POST "repos/$OWNER/$REPO/actions/runners/registration-token" --jq .token)"

  ./config.sh \
    --unattended \
    --url "https://github.com/$OWNER/$REPO" \
    --token "$TOKEN" \
    --name "$NAME" \
    --labels "$LABELS" \
    --work "$WORK_DIR" \
    --replace

  if [[ "$DO_SERVICE" -eq 1 ]]; then
    if [[ -f "./svc.sh" ]]; then
      if [[ "$RUNNER_OS" == "osx" ]]; then
        # Pre-cleanup: force remove any stale launchctl entries
        cleanup_macos_service_artifacts "$REPO" "$NAME"
        sleep 1

        # Install
        if ! run_service install; then
          echo "First install attempt failed, retrying with cleanup..."
          cleanup_macos_service_artifacts "$REPO" "$NAME"
          sleep 2
          run_service install || {
            echo "ERROR: Failed to install service after cleanup"
            exit 1
          }
        fi

        # Verify and fix permissions
        if ! verify_and_fix_macos_service; then
          echo "ERROR: Service verification failed"
          exit 1
        fi

        # svc.sh start uses deprecated `launchctl load`; use bootstrap for modern macOS.
        # When running over SSH (Background session), plain launchctl bootstrap into
        # gui/UID requires sudo; try both.
        plist_path="$(< .service)"
        user_domain="gui/$(id -u)"
        if launchctl bootstrap "$user_domain" "$plist_path" 2>/dev/null; then
          echo "Service started via launchctl bootstrap."
        elif sudo launchctl bootstrap "$user_domain" "$plist_path" 2>/dev/null; then
          echo "Service started via sudo launchctl bootstrap."
        else
          echo "WARNING: launchctl bootstrap failed (possibly already loaded); checking service status..."
          if launchctl list 2>/dev/null | grep -qF "$(basename "$plist_path" .plist)"; then
            echo "Service is already running — OK."
          else
            echo "ERROR: Failed to start service. If running over SSH, try logging in"
            echo "  directly on the Mac and re-running with --force, or run:"
            echo "  sudo launchctl bootstrap $user_domain $plist_path"
            exit 1
          fi
        fi
      else
        run_service install
        run_service start
      fi
    else
      echo "Service script not found; runner configured but not installed as a service."
    fi
  else
    echo "(--no-service) Not installing/starting runner service."
  fi

  echo "Runner for $OWNER/$REPO done."
  echo
done

echo "All done."
echo "Tip: In workflow YAML, use: runs-on: [self-hosted] (and labels if set)."
