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
  -l LABELS           Runner labels (default: self-hosted,linux,x64)
  -v VERSION          actions/runner version (default: 2.319.1)
  -w WORK_DIR         Work folder name inside each runner dir (default: _work)
  --no-service        Only configure; do not install/start systemd service
  --force             Reconfigure even if already configured (removes existing config)
  -h                  Help

Examples:
  ./setup-github-runners-batch.sh -o myuser -r "repo-a,repo-b,repo-c"
  ./setup-github-runners-batch.sh -o myuser -r "repo-a repo-b" -l "self-hosted,linux,homelab"
  ./setup-github-runners-batch.sh -o myuser -r "repo-a" --force
EOF
}

OWNER=""
REPOS_RAW=""
BASE="$HOME/github-runners"
LABELS="self-hosted,linux,x64"
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

# Dependencies
for cmd in curl tar gh jq; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "ERROR: Missing dependency: $cmd"
    echo "Ubuntu/Debian: sudo apt update && sudo apt install -y gh jq curl tar"
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
RUNNER_TGZ="$CACHE_DIR/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"
mkdir -p "$CACHE_DIR"

if [[ ! -f "$RUNNER_TGZ" ]]; then
  echo "Downloading actions/runner v$RUNNER_VERSION into cache..."
  curl -fsSL -o "$RUNNER_TGZ" \
    "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"
fi

for REPO in "${REPOS[@]}"; do
  REPO="$(echo "$REPO" | xargs)" # trim
  [[ -z "$REPO" ]] && continue

  echo "=== Setting up runner for $OWNER/$REPO ==="

  DIR="$BASE/$REPO"
  mkdir -p "$DIR"
  cd "$DIR"

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
      sudo ./svc.sh stop || true
      sudo ./svc.sh uninstall || true
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

  # Unique name per repo (helps in GitHub UI)
  NAME="$(hostname)-$REPO"

  ./config.sh \
    --unattended \
    --url "https://github.com/$OWNER/$REPO" \
    --token "$TOKEN" \
    --name "$NAME" \
    --labels "$LABELS" \
    --work "$WORK_DIR" \
    --replace

  if [[ "$DO_SERVICE" -eq 1 ]]; then
    sudo ./svc.sh install
    sudo ./svc.sh start
  else
    echo "(--no-service) Not installing/starting systemd service."
  fi

  echo "Runner for $OWNER/$REPO done."
  echo
done

echo "All done."
echo "Tip: In workflow YAML, use: runs-on: [self-hosted] (and labels if set)."
