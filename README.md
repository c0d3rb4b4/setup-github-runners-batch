# Batch GitHub Self-Hosted Runner Setup (Personal Accounts)

This script lets you **batch-create GitHub self-hosted runners** for **multiple repositories** under a **personal GitHub account**, using **one runner per repository**, each in its own folder and service.

GitHub does **not** support account-wide runners for personal accounts, so this approach is the recommended and scalable workaround.

---

## What this script does

For each repository you specify, the script will:

- Create a dedicated directory for the runner
- Auto-detect the host OS and CPU architecture
- Download and cache the matching official GitHub Actions runner
- Generate a short-lived registration token using the GitHub API
- Register the runner **at repo level**
- (Optionally) install and start a runner service
- Apply consistent labels so workflows can target the runner

Each runner is fully isolated and can be managed independently.

---

## Prerequisites

### 1. Supported OS
- Linux (`x64` or `arm64`)
  - Tested on Ubuntu 20.04 / 22.04 / 24.04
  - Uses `systemd` when `svc.sh` is available
  - Works in VMs, bare metal, and containers (LXC with systemd)
- macOS (`x64` or `arm64`)
  - Uses `launchd` when `svc.sh` is available

The script auto-detects both the OS and architecture, then downloads the matching runner archive:

- Linux: `actions-runner-linux-x64` or `actions-runner-linux-arm64`
- macOS: `actions-runner-osx-x64` or `actions-runner-osx-arm64`

### 2. Required tools

Linux:

```bash
sudo apt update
sudo apt install -y curl tar jq gh
```

macOS:

```bash
brew install gh jq
```

### 3. GitHub CLI authentication

Authenticate using the GitHub CLI **as a user with admin access to the repos**:

```bash
gh auth login
```

Verify authentication:

```bash
gh auth status
```

### 4. Service setup permissions

If you want the runner installed as a background service:

Linux uses `systemd` and the script will run:

```bash
sudo ./svc.sh install
sudo ./svc.sh start
```

macOS uses `launchd` and the script will run:

```bash
./svc.sh install
./svc.sh start
```

If you do not want a service, pass `--no-service`.

---

## Installation

1. Copy the script to your machine:
```bash
setup-github-runners-batch.sh
```

2. Make it executable:
```bash
chmod +x setup-github-runners-batch.sh
```

---

## Usage

The script auto-detects Linux or macOS, and `x64` or `arm64`, before downloading the correct runner build.

### Basic usage

```bash
./setup-github-runners-batch.sh \
  -o <GITHUB_USERNAME> \
  -r "repo1,repo2,repo3"
```

You can also use space-separated repo names:

```bash
./setup-github-runners-batch.sh \
  -o <GITHUB_USERNAME> \
  -r "repo1 repo2 repo3"
```

### macOS quick start

```bash
brew install gh jq
gh auth login
chmod +x setup-github-runners-batch.sh

./setup-github-runners-batch.sh \
  -o <GITHUB_USERNAME> \
  -r "repo1,repo2,repo3"
```

---

## Options

| Option | Description | Default |
|------|------------|---------|
| `-o OWNER` | GitHub username (repo owner) | Required |
| `-r REPOS` | Repo list (comma or space separated) | Required |
| `-b BASE_DIR` | Base directory for all runners | `$HOME/github-runners` |
| `-l LABELS` | Runner labels | `self-hosted,<auto-os>,<auto-arch>` |
| `-v VERSION` | GitHub Actions runner version | `2.319.1` |
| `-w WORK_DIR` | Runner work directory name | `_work` |
| `--no-service` | Do not install/start a runner service | off |
| `--force` | Reconfigure even if runner already exists | off |
| `-h` | Show help | |

---

## Using the runner in GitHub Actions

```yaml
runs-on: self-hosted
```

Or with labels:

```yaml
runs-on: [self-hosted, linux, x64]
```

For macOS Apple Silicon runners, GitHub's default labels are typically:

```yaml
runs-on: [self-hosted, macOS, ARM64]
```

If you omit `-l`, this script also adds matching custom labels based on the detected platform.

---

## Notes & Limitations

- GitHub **personal accounts do not support global runners**
- Each repo requires its own runner registration
- Registration tokens **expire after ~1 hour**
- For parallel jobs in the same repo, run **multiple runner instances**
- On macOS, service management uses `launchd` instead of `systemd`
- For Docker builds, ensure:
  - Docker is installed
  - Runner user is in the `docker` group

---

## License

MIT / Public domain — use, modify, and share freely.
