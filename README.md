# devops-terraform-buildkite-scripts

[![Buildkite](https://badge.buildkite.com/your-pipeline-id.svg)](https://buildkite.com/yourorg/your-pipeline)
[![Terraform](https://img.shields.io/badge/Terraform-1.6+-623CE4?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![OpenTofu](https://img.shields.io/badge/OpenTofu-1.6+-FFDA18?logo=opentofu&logoColor=black)](https://opentofu.org/)
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
