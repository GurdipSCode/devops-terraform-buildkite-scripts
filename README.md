# devops-terraform-buildkite-scripts

![Terraform](https://img.shields.io/badge/Terraform-%235835CC.svg?style=flat&logo=terraform&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-5391FE?style=flat&logo=powershell&logoColor=white)
![Buildkite](https://img.shields.io/badge/Buildkite-14CC80?style=flat&logo=buildkite&logoColor=white)
![HashiCorp Vault](https://img.shields.io/badge/Vault-FFEC6E?style=flat&logo=vault&logoColor=black)
![Windows](https://img.shields.io/badge/Windows-0078D6?style=flat&logo=windows&logoColor=white)

![Checkov](https://img.shields.io/badge/Checkov-5C4EE5?style=flat&logo=paloaltonetworks&logoColor=white)
![Semgrep](https://img.shields.io/badge/Semgrep-4B11A8?style=flat&logo=semgrep&logoColor=white)
![Mondoo](https://img.shields.io/badge/Mondoo-5C2D91?style=flat&logo=mondoo&logoColor=white)

![License](https://img.shields.io/badge/License-Internal-red)
![Version](https://img.shields.io/badge/Version-1.0.0-blue)

Centralized CI/CD pipeline scripts and templates for Terraform deployments on Windows Buildkite agents.

## Overview

This repository provides a **template pipeline system** that works with standard Buildkite (no Advanced tier required). Individual Terraform repos use a minimal "bootstrap" pipeline that loads the full pipeline from this central repo.

### Features

- 🔐 **Vault Integration** - Per-environment secrets (Mondoo, Lynx, AWS/Azure/GCP)
- 🛡️ **5 Security Scanners** - Checkov, tfsec, KICS, Semgrep, Mondoo
- 🤖 **AI Analysis** - Fabric CLI for human-readable plan summaries
- 🔍 **Blast Radius** - Overmind for dependency and risk analysis
- 🔄 **Multi-Environment** - Dynamic pipeline for dev → tst → prd
- 📋 **Lynx Backend** - HTTP state management with locking

## Quick Start

### 1. In Your Terraform Repo

Create `.buildkite/pipeline.yml`:

```yaml
env:
  SCRIPTS_REPO: "git@github.com:yourorg/terraform-buildkite-scripts.git"
  SCRIPTS_VERSION: "v1.0.0"
  LYNX_TEAM: "platform"
  LYNX_PROJECT: "my-project"  # Change this
  ENVIRONMENTS: "dev tst prd"
  LYNX_SERVER_URL: "https://lynx.yourcompany.com"
  VAULT_ADDR: "https://vault.yourcompany.com"

steps:
  - label: ":rocket: Bootstrap"
    commands:
      - "git clone --branch $$SCRIPTS_VERSION --depth 1 $$SCRIPTS_REPO .buildkite-scripts"
      - "buildkite-agent pipeline upload .buildkite-scripts/pipelines/terraform-module.yml"
    agents:
      queue: "terraform"
```

### 2. That's It!

The bootstrap clones this repo and uploads the full pipeline. Your Terraform repo stays clean with just ~15 lines of YAML.

## Repository Structure

```
terraform-buildkite-scripts/
├── README.md
├── VERSION
├── CHANGELOG.md
│
├── pipelines/                        # Full pipeline definitions
│   ├── terraform-module.yml          # For Terraform modules
│   └── terraform-service.yml         # For services using modules
│
├── scripts/                          # PowerShell scripts
│   ├── fetch-vault-secrets.ps1       # Fetch secrets from Vault
│   ├── configure-lynx-backend.ps1    # Configure Terraform HTTP backend
│   ├── generate-env-steps.ps1        # Generate dynamic env steps
│   ├── terraform-validate.ps1        # Validate Terraform code
│   ├── run-security-scans.ps1        # Run 5 security scanners
│   ├── run-fabric-summary.ps1        # Generate AI summaries
│   ├── run-overmind-analysis.ps1     # Blast radius analysis
│   └── setup-vault.ps1               # One-time Vault setup
│
└── bootstrap/                        # Templates for Terraform repos
    ├── module-bootstrap.yml          # Bootstrap for modules
    └── service-bootstrap.yml         # Bootstrap for services
```

## How It Works

```
┌──────────────────────────────────────────────────────────────┐
│  Your Terraform Repo                                         │
│  .buildkite/pipeline.yml (15 lines)                          │
└─────────────────────────┬────────────────────────────────────┘
                          │
                          │ 1. git clone terraform-buildkite-scripts
                          │ 2. buildkite-agent pipeline upload
                          ▼
┌──────────────────────────────────────────────────────────────┐
│  This Central Repo                                           │
│  pipelines/terraform-module.yml                              │
│  scripts/*.ps1                                               │
└─────────────────────────┬────────────────────────────────────┘
                          │
                          │ 3. Full pipeline executes
                          ▼
┌──────────────────────────────────────────────────────────────┐
│  Pipeline Execution                                          │
│                                                              │
│  Phase 1 (Global):                                           │
│    Validate → Security Scans → Generate Env Steps            │
│                                                              │
│  Phase 2 (Per Environment):                                  │
│    Secrets → Plan → Fabric → Overmind → Approve → Apply      │
└──────────────────────────────────────────────────────────────┘
```

## Pipeline Types

### terraform-module.yml

For Terraform modules and general infrastructure.

### terraform-service.yml

For services that consume Terraform modules.

Both pipelines include:
- Terraform validation & format check
- Security scanning (5 tools)
- Multi-environment deployment
- AI-powered plan summaries
- Blast radius analysis
- Manual approval gates

## Scripts Reference

| Script | Purpose |
|--------|---------|
| `fetch-vault-secrets.ps1` | Fetches all secrets from Vault per environment |
| `configure-lynx-backend.ps1` | Configures Terraform HTTP backend for Lynx |
| `generate-env-steps.ps1` | Dynamically generates pipeline steps per environment |
| `terraform-validate.ps1` | Runs terraform fmt, init, and validate |
| `run-security-scans.ps1` | Runs Checkov, tfsec, KICS, Semgrep, and Mondoo |
| `run-fabric-summary.ps1` | Generates AI summaries using Fabric CLI |
| `run-overmind-analysis.ps1` | Analyzes blast radius using Overmind CLI |
| `setup-vault.ps1` | One-time setup to store secrets in Vault |

## Configuration

### Buildkite Environment Variables

Set these in Buildkite pipeline or organization settings:

**Non-Secret:**
```
LYNX_SERVER_URL=https://lynx.yourcompany.com
VAULT_ADDR=https://vault.yourcompany.com
```

**Secret (mark as secret):**
```
VAULT_ROLE_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
VAULT_SECRET_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
OVM_API_KEY=ovm_xxxxxxxxxxxxxxxxxx
```

### Per-Repo Configuration

Set in each Terraform repo's bootstrap pipeline:

```yaml
env:
  LYNX_TEAM: "your-team"
  LYNX_PROJECT: "your-project"
  ENVIRONMENTS: "dev tst prd"
```

## Vault Secret Structure

Store secrets in Vault per environment:

```
secret/
├── mondoo/
│   ├── dev/     → { "token": "...", "space_id": "..." }
│   ├── tst/
│   └── prd/
├── lynx/
│   ├── dev/     → { "username": "...", "password": "..." }
│   ├── tst/
│   └── prd/
├── aws/
│   ├── dev/     → { "access_key_id": "...", "secret_access_key": "...", "region": "..." }
│   ├── tst/
│   └── prd/
├── azure/       (optional)
│   └── ...
└── gcp/         (optional)
    └── ...
```

### Initial Vault Setup

Run once to set up secrets:

```powershell
.\scripts\setup-vault.ps1
```

## Security Scanners

The `run-security-scans.ps1` script runs 5 scanners:

| Scanner | Focus | Install |
|---------|-------|---------|
| **Checkov** | 1000+ security & compliance checks | `pip install checkov` |
| **tfsec** | Terraform-specific security | `choco install tfsec` |
| **KICS** | IaC security (Checkmarx) | `choco install kics` |
| **Semgrep** | Lightweight static analysis | `pip install semgrep` |
| **Mondoo** | Policy-as-code scanning | `choco install mondoo` |

Scans continue even if some scanners aren't installed.

## Agent Requirements

Windows Buildkite agents need:

**Required:**
- PowerShell 7+
- Terraform CLI
- Git
- Vault CLI

**For Security Scans:**
- Python 3.x (for Checkov, Semgrep)
- Checkov (`pip install checkov`)
- tfsec (`choco install tfsec`)
- KICS (`choco install kics`)
- Semgrep (`pip install semgrep`)
- Mondoo (`choco install mondoo`)

**For AI Analysis:**
- Fabric CLI (`go install github.com/danielmiessler/fabric@latest`)
- Overmind CLI (`winget install Overmind.OvermindCLI`)

## Version Management

### Using Versions

**Production (recommended):**
```yaml
SCRIPTS_VERSION: "v1.2.3"
```

**Development:**
```yaml
SCRIPTS_VERSION: "main"
```

### Creating Releases

```bash
# Update VERSION file
echo "1.2.4" > VERSION

# Update CHANGELOG.md

# Commit and tag
git add .
git commit -m "Release v1.2.4"
git tag -a v1.2.4 -m "Release v1.2.4 - description"
git push origin main --tags
```

## Terraform Repo Structure

Each Terraform repo needs only:

```
terraform-my-project/
├── .buildkite/
│   └── pipeline.yml      # Bootstrap (15 lines)
├── backend.tf            # HTTP backend config (no secrets)
├── main.tf               # Your infrastructure
├── variables.tf
├── outputs.tf
├── .gitignore
└── README.md
```

### backend.tf

```hcl
terraform {
  backend "http" {
    lock_method   = "POST"
    unlock_method = "POST"
    # All other values from environment variables
  }
}
```

## Local Development

### Testing Scripts

```powershell
# Clone this repo
git clone git@github.com:yourorg/terraform-buildkite-scripts.git

# Set required environment variables
$env:VAULT_ADDR = "https://vault.yourcompany.com"
$env:LYNX_SERVER_URL = "https://lynx.yourcompany.com"
$env:LYNX_TEAM = "platform"
$env:LYNX_PROJECT = "test"
$env:SCRIPTS_PATH = "./scripts"

# Test individual scripts
.\scripts\terraform-validate.ps1
.\scripts\run-security-scans.ps1
```

### Testing with a Terraform Repo

```powershell
cd my-terraform-project

# Clone scripts
git clone ../terraform-buildkite-scripts .buildkite-scripts

# Set scripts path
$env:SCRIPTS_PATH = ".buildkite-scripts/scripts"

# Run validation
pwsh -File .buildkite-scripts/scripts/terraform-validate.ps1
```

## Troubleshooting

### Pipeline not loading

- Verify Git can clone this repo from the agent
- Check `SCRIPTS_VERSION` tag exists
- Verify pipeline path is correct

### Secrets not loading

- Verify Vault is accessible from agent
- Check `VAULT_ROLE_ID` and `VAULT_SECRET_ID` are set
- Verify secrets exist at expected paths in Vault

### Security scans failing

- Check scanners are installed on agent
- Verify PATH includes scanner binaries
- Individual scanner failures don't stop other scans

### Backend authentication failing

- Verify Lynx credentials in Vault (`secret/lynx/{env}`)
- Check `LYNX_SERVER_URL` is correct
- Test Lynx connectivity from agent

## Contributing

1. Create a feature branch
2. Make changes
3. Test locally
4. Create pull request
5. Get approval from platform team
6. Merge and tag new version

## License

Internal use only.

## Support

- Create an issue in this repository
- Slack: #platform-support
- Email: platform-team@yourcompany.com
