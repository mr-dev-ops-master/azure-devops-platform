# Azure DevOps platform – infrastructure and containerised app, dev and prod

Terraform provisions secure Azure infrastructure for **dev** and **prod**; a containerised Python app is built once,
scanned, and promoted through both environments by **GitHub Actions** or **Azure DevOps**, with monitoring and alerting.

## Architecture (per environment)

| Component | Purpose | dev | prod |
|---|---|---|---|
| VNet + subnets | App Service VNet integration, data subnet with NSG | 10.10.0.0/16 | 10.20.0.0/16 |
| Azure Container Registry | Docker images (admin user disabled) | Basic | Basic |
| App Service (Linux container) | Runs the app, managed identity, HTTPS only, TLS 1.2 | B1 | P0v3 + staging slot |
| Key Vault (RBAC) | Secrets via Key Vault references | soft delete | + purge protection |
| Log Analytics + App Insights | Logs, metrics, traces (OpenTelemetry) | 30 days | 90 days |
| Alerts + action group | HTTP 5xx and availability test on /health | Sev 3 | Sev 0/1 |

## Pipelines

| | Pull request | Merge to main |
|---|---|---|
| Infra (Terraform) | fmt, validate, Checkov, plan dev + prod | apply dev → **approval** → apply prod |
| App (Docker) | flake8, pytest, docker build, Trivy scan | push to dev ACR → deploy dev → **approval** → import to prod ACR → staging slot → smoke test → swap |

GitHub Actions: `.github/workflows/` (reusable `_terraform.yml`). Azure DevOps: `pipelines/` (template `templates/terraform.yml`).

## Code scanning

| Layer | Tool | Where | Blocks the pipeline? |
|---|---|---|---|
| Terraform lint | TFLint (azurerm ruleset) | PR | Yes |
| IaC security | Checkov (SARIF → Security tab) | PR | Reported; blocking once triaged |
| Secrets | Gitleaks | Every PR/push | Yes |
| Python SAST | CodeQL + Bandit | PR, push, weekly | Bandit: medium+ yes |
| Dependencies (SCA) | pip-audit + Dependabot | PR / weekly PRs | Yes |
| Dockerfile | Hadolint | PR | Errors |
| Container image | Trivy (SARIF → Security tab) | PR + build | CRITICAL |

## Security
OIDC / workload identity federation (no stored secrets) · least-privilege managed identities (AcrPull, Key Vault Secrets
User) · ACR admin disabled · non-root container · Trivy and Checkov scans · branch protection and PR reviews ·
approval gates on prod.

## Layout
```
terraform/            providers, network, registry, keyvault, app, monitoring, outputs; environments/dev|prod.tfvars
app/                  Flask app, Dockerfile, tests
.github/workflows/    infra.yml, _terraform.yml, app.yml
pipelines/            azure-pipelines-infra.yml, azure-pipelines-app.yml, templates/terraform.yml
scripts/              setup-azure-oidc.sh (state storage + pipeline identity)
docs/RUNBOOK.md       incident response, KQL queries, rollback, disaster recovery
```
