# Batch GitHub Self-Hosted Runner Setup (Personal Accounts)

This script lets you **batch-create GitHub self-hosted runners** for **multiple repositories** under a **personal GitHub account**, using **one runner per repository**, each in its own folder and systemd service.

GitHub does **not** support account-wide runners for personal accounts, so this approach is the recommended and scalable workaround.

---

## What this script does

For each repository you specify, the script will:

- Create a dedicated directory for the runner
- Download and cache the official GitHub Actions runner
- Generate a short-lived registration token using the GitHub API
- Register the runner **at repo level**
- (Optionally) install and start a **systemd service**
- Apply consistent labels so workflows can target the runner

Each runner is fully isolated and can be managed independently.

---

## Prerequisites

### 1. Supported OS
- Linux with **systemd**
  - Tested on Ubuntu 20.04 / 22.04 / 24.04
  - Works in VMs, bare metal, and containers (LXC with systemd)

### 2. Required tools

Install the following packages:

```bash
sudo apt update
sudo apt install -y curl tar jq gh git
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

### 4. Sudo access

The user running the script must be able to run:

```bash
sudo ./svc.sh install
sudo ./svc.sh start
```

This is required to register systemd services.

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

---

## Options

| Option | Description | Default |
|------|------------|---------|
| `-o OWNER` | GitHub username (repo owner) | Required |
| `-r REPOS` | Repo list (comma or space separated) | Required |
| `-b BASE_DIR` | Base directory for all runners | `$HOME/github-runners` |
| `-l LABELS` | Runner labels | `self-hosted,linux,x64` |
| `-v VERSION` | GitHub Actions runner version | `2.319.1` |
| `-w WORK_DIR` | Runner work directory name | `_work` |
| `--no-service` | Do not install/start systemd services | off |
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

---

## Notes & Limitations

- GitHub **personal accounts do not support global runners**
- Each repo requires its own runner registration
- Registration tokens **expire after ~1 hour**
- For parallel jobs in the same repo, run **multiple runner instances**
- For Docker builds, ensure:
  - Docker is installed
  - Runner user is in the `docker` group

---

## License

MIT / Public domain — use, modify, and share freely.
