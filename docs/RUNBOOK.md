# Runbook – azure-devops-platform

| Item | dev | prod |
|---|---|---|
| Web app | app-<prefix>-dev | app-<prefix>-prod (+ staging slot) |
| Registry | acr<prefix>dev | acr<prefix>prod |
| Key Vault | kv-<prefix>-dev | kv-<prefix>-prod |
| Logs | log-<prefix>-dev | log-<prefix>-prod |
| Alerts | Sev 3 (email) | Sev 0/1 (email) |

## Alert: availability test failing / HTTP 5xx

1. **Confirm**: open the web app URL `/health`. Check App Insights > Availability and Failures.
2. **Recent change?** GitHub Actions / Azure DevOps run history: what was deployed and when.
3. **Logs** (Log Analytics > Logs):

```kusto
// HTTP errors in the last hour
AppServiceHTTPLogs
| where TimeGenerated > ago(1h) and ScStatus >= 500
| summarize count() by CsUriStem, ScStatus, bin(TimeGenerated, 5m)

// Container start-up / crash messages
AppServiceConsoleLogs
| where TimeGenerated > ago(1h)
| project TimeGenerated, ResultDescription
| order by TimeGenerated desc

// Failed requests seen by Application Insights
AppRequests
| where TimeGenerated > ago(1h) and Success == false
| summarize count() by Name, ResultCode
```

4. **Rollback (prod)** – the previous version is still in the staging slot after a swap:

```bash
az webapp deployment slot swap -g rg-<prefix>-prod -n app-<prefix>-prod --slot staging --target-slot production
```

   Or redeploy a known-good image tag:

```bash
az webapp config container set -g rg-<prefix>-prod -n app-<prefix>-prod \
  --container-image-name acr<prefix>prod.azurecr.io/demo-app:<good-sha>
```

5. **Record** the incident: timeline, root cause, fix, and a follow-up action to stop it recurring.

## Key Vault secret not loading
App setting shows the reference status in Portal > web app > Environment variables. Check the app's managed identity
has **Key Vault Secrets User** on the vault, then restart the app.

## Disaster recovery
- **Infrastructure**: everything is code. Re-run the Infra pipeline (or `terraform apply`) to rebuild an environment.
- **Terraform state**: the state storage has blob versioning and 14-day soft delete; restore a previous version
  from Portal > storage account > tfstate container > blob > Versions.
- **Images**: rebuild from Git (any commit SHA) through the App pipeline.
- **Secrets**: Key Vault soft delete (7 days); prod also has purge protection.
