# devops-terraform-buildkite-scripts

[![Buildkite](https://badge.buildkite.com/your-pipeline-id.svg)](https://buildkite.com/yourorg/your-pipeline)
[![Terraform](https://img.shields.io/badge/Terraform-1.6+-623CE4?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![OpenTofu](https://img.shields.io/badge/OpenTofu-1.6+-FFDA18?logo=opentofu&logoColor=black)](https://opentofu.org/)
[![Semgrep](https://img.shields.io/badge/Semgrep-Enabled-blueviolet?logo=semgrep&logoColor=white)](https://semgrep.dev/)
[![License](https://img.shields.io/badge/License-Proprietary-red.svg)](LICENSE)
[![Maintained](https://img.shields.io/badge/Maintained-Yes-green.svg)](https://github.com/yourorg/terraform-infrastructure)

[![Security Scan](https://img.shields.io/badge/Security-TFSec%20%7C%20Checkov%20%7C%20KICS-blue)](https://github.com/yourorg/terraform-infrastructure)
[![State Backend](https://img.shields.io/badge/State-Clivern%20Lynx-orange)](https://github.com/Clivern/Lynx)
[![Secrets](https://img.shields.io/badge/Secrets-HashiCorp%20Vault-yellow?logo=vault)](https://www.vaultproject.io/)
[![Compliance](https://img.shields.io/badge/Compliance-Mondoo-4B275F?logo=data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAA4AAAAOCAYAAAAfSC3RAAAACXBIWXMAAAsTAAALEwEAmpwYAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAACNSURBVHgBnZLBDYAgDEVbBnAER3AER3AER3AER3AER2AEHMHn0xgTYkK8+JKG0vYnhZTSN+ccY4w/McbknLdarfZ1Xeu6rjVNU13X1fd9ZVn2simKQkVRqCxLlWWpsiw/tm3TNE1N09Q0TdM0TU3T1DRN0zRN0zQ1TVM=)](https://mondoo.com/)

> **Modern Terraform infrastructure deployment pipeline using Buildkite, Clivern Lynx state backend, and comprehensive security scanning.**

---

## 📋 Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Project Structure](#project-structure)
- [Pipeline Stages](#pipeline-stages)
- [Configuration](#configuration)
- [Security](#security)
- [Deployment](#deployment)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

---

## 🎯 Overview

This repository contains Terraform infrastructure-as-code that deploys and manages cloud resources using a modern CI/CD pipeline with:

- **🏗️ Infrastructure as Code:** OpenTofu/Terraform for declarative infrastructure
- **🔄 CI/CD Automation:** Buildkite for pipeline orchestration
- **💾 State Management:** Clivern Lynx HTTP backend with distributed locking
- **🔐 Security:** Comprehensive scanning with TFSec, Checkov, Terrascan, KICS
- **🛡️ Compliance:** Mondoo security posture management
- **🔑 Secrets:** HashiCorp Vault for secure credential management
- **🤖 AI Analysis:** Fabric AI and Overmind for plan analysis

---

## ✨ Features

### 🚀 Deployment
- ✅ Multi-environment support (dev, staging, production)
- ✅ Progressive deployment with approval gates
- ✅ Automated state backups before changes
- ✅ Rollback capabilities
- ✅ Environment-specific configurations

### 🔒 Security
- ✅ **TFSec** - Terraform static analysis
- ✅ **Checkov** - Policy-as-code scanning
- ✅ **Terrascan** - Infrastructure security scanner
- ✅ **KICS** - Comprehensive IaC scanner
- ✅ **GitGuardian** - Secret detection
- ✅ **Mondoo** - Security posture management
- ✅ Compliance score enforcement (minimum 85%)

### 🤖 Intelligent Analysis
- ✅ **Fabric AI** - Natural language plan analysis
- ✅ **Overmind** - Blast radius calculation
- ✅ Change impact assessment
- ✅ Risk scoring and recommendations

### 🏗️ Infrastructure
- ✅ Module-based architecture
- ✅ Reusable Terraform modules
- ✅ Version-pinned dependencies
- ✅ Automated documentation generation
- ✅ Drift detection

---

## 🏛️ Architecture

## 🏛️ Architecture
```
┌─────────────────────────────────────────────────────────────────┐
│                        Buildkite CI/CD                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │
│  │ Validation   │→ │  Security    │→ │  Deployment  │        │
│  │ & Formatting │  │  Scanning    │  │  Pipeline    │        │
│  └──────────────┘  └──────────────┘  └──────────────┘        │
└────────────────────────────┬────────────────────────────────────┘
                             │
                 ┌───────────┴───────────┐
                 ▼                       ▼
        ┌─────────────────┐     ┌─────────────────┐
        │  HashiCorp      │     │  Clivern Lynx   │
        │  Vault          │     │  State Backend  │
        │  (Secrets)      │     │  (HTTP + Lock)  │
        └─────────────────┘     └─────────────────┘
                 │                       │
                 └───────────┬───────────┘
                             ▼
                    ┌─────────────────┐
                    │   Cloud         │
                    │   Infrastructure│
                    │   (AWS/Azure)   │
                    └─────────────────┘
```

---

## 📦 Prerequisites

### Required Tools

| Tool | Minimum Version | Purpose |
|------|----------------|---------|
| [OpenTofu](https://opentofu.org/) | 1.6.0+ | Infrastructure provisioning |
| [PowerShell](https://github.com/PowerShell/PowerShell) | 7.0+ | Script execution |
| [Buildkite Agent](https://buildkite.com/docs/agent/v3) | 3.x+ | CI/CD pipeline execution |
| [Vault CLI](https://www.vaultproject.io/downloads) | 1.15.0+ | Secret management |

### Optional Tools

| Tool | Purpose |
|------|---------|
| [Fabric AI](https://github.com/danielmiessler/fabric) | AI-powered plan analysis |
| [Overmind CLI](https://overmind.tech/) | Blast radius analysis |
| [terraform-docs](https://terraform-docs.io/) | Documentation generation |

### Access Requirements

- ✅ HashiCorp Vault access with JWT authentication
- ✅ Clivern Lynx HTTP backend endpoint
- ✅ Buildkite organization and pipeline
- ✅ Cloud provider credentials (AWS/Azure/GCP)
- ✅ Mondoo service account token

---

## 🚀 Quick Start

### 1. Clone Repository
```bash
git clone https://github.com/yourorg/terraform-infrastructure.git
cd terraform-infrastructure
```

### 2. Configure Pipeline

Edit `.buildkite/pipeline.yml`:
```yaml
env:
  PROJECT_NAME: "my-infrastructure"
  SERVICE_NAME: "my-service"
  TARGET_ENVIRONMENTS: "dev,stg,prd"
  VAULT_NAMESPACE: "DevOps/prd/my-project"
  LYNX_BASE_URL: "https://lynx.company.com"
```

### 3. Set Up Vault Secrets
```bash
# Lynx backend credentials
vault kv put secret/lynx/terraform \
  username="terraform-user" \
  password="secure-password"

# Mondoo token
vault kv put secret/mondoo \
  token="your-mondoo-token"
```

### 4. Create Environment Directories
```bash
mkdir -p dev stg prd
cd dev

cat > main.tf <<EOF
terraform {
  required_version = ">= 1.6.0"
  
  backend "http" {
    # Configured by Initialize-TofuBackend
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"
  
  name = "my-vpc"
  cidr = "10.0.0.0/16"
}
EOF
```

### 5. Commit and Push
```bash
git add .
git commit -m "feat: initial infrastructure setup"
git push origin main
```

### 6. Watch Pipeline Execute

Visit your Buildkite dashboard to see the pipeline run! 🎉

---

## 📁 Project Structure
