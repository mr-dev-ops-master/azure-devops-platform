#!/usr/bin/env bash
# One-off bootstrap (Git Bash, after `az login`):
#   - Terraform state storage (versioning + soft delete for recovery)
#   - Pipeline identity for GitHub Actions with OIDC trust (no secrets)
#   - Role assignments
set -euo pipefail

# ---------- CHANGE THESE ----------
GH_REPO="YOUR-GITHUB-USERNAME/azure-devops-platform"
PREFIX="ifynlab"            # same as in terraform/environments/*.tfvars
LOCATION="uksouth"
# ----------------------------------

export MSYS_NO_PATHCONV=1    # stop Git Bash rewriting /subscriptions/... paths

RG_STATE="rg-tfstate-${PREFIX}"
SA_STATE="st${PREFIX}tf$RANDOM"
SA_STATE="${SA_STATE:0:24}"
APP_NAME="gh-${PREFIX}-platform-cicd"
SUB_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)

echo "[1/6] Terraform state storage: $RG_STATE / $SA_STATE"
az group create -n "$RG_STATE" -l "$LOCATION" -o none
az storage account create -n "$SA_STATE" -g "$RG_STATE" -l "$LOCATION" --sku Standard_ZRS \
  --min-tls-version TLS1_2 --allow-blob-public-access false -o none
az storage account blob-service-properties update -n "$SA_STATE" -g "$RG_STATE" \
  --enable-versioning true --enable-delete-retention true --delete-retention-days 14 -o none
KEY=$(az storage account keys list -g "$RG_STATE" -n "$SA_STATE" --query "[0].value" -o tsv)
az storage container create -n tfstate --account-name "$SA_STATE" --account-key "$KEY" -o none
unset KEY

echo "[2/6] Pipeline identity: $APP_NAME"
APP_ID=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)
az ad sp create --id "$APP_ID" -o none
echo "      waiting 30s for Entra ID..."; sleep 30

echo "[3/6] Contributor + RBAC Administrator on the subscription"
az role assignment create --assignee "$APP_ID" --role "Contributor" --scope "/subscriptions/$SUB_ID" -o none
# Needed because Terraform grants the web app AcrPull / Key Vault Secrets User.
# In production, add a condition limiting which roles it may assign.
az role assignment create --assignee "$APP_ID" --role "Role Based Access Control Administrator" \
  --scope "/subscriptions/$SUB_ID" -o none

echo "[4/6] Storage Blob Data Contributor on the state storage (no access keys in pipelines)"
SA_ID=$(az storage account show -n "$SA_STATE" -g "$RG_STATE" --query id -o tsv)
az role assignment create --assignee "$APP_ID" --role "Storage Blob Data Contributor" --scope "$SA_ID" -o none

echo "[5/6] OIDC trust: pull requests, main branch, dev and prod environments"
for SUBJECT in "pull_request" "ref:refs/heads/main" "environment:dev" "environment:prod"; do
  NAME="github-$(echo "$SUBJECT" | tr ':/' '--')"
  az ad app federated-credential create --id "$APP_ID" -o none --parameters "{
    \"name\": \"$NAME\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:$GH_REPO:$SUBJECT\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }"
done

echo "[6/6] Done. Configure GitHub (Settings > Secrets and variables > Actions):"
echo "  Secrets:   AZURE_CLIENT_ID=$APP_ID"
echo "             AZURE_TENANT_ID=$TENANT_ID"
echo "             AZURE_SUBSCRIPTION_ID=$SUB_ID"
echo "  Variables: TF_STATE_RG=$RG_STATE  TF_STATE_SA=$SA_STATE"
echo "             ALERT_EMAIL=<your email>  DEV_ACR_NAME=acr${PREFIX}dev"
echo "  Environment 'dev':  APP_NAME=app-${PREFIX}-dev   ACR_NAME=acr${PREFIX}dev"
echo "  Environment 'prod': APP_NAME=app-${PREFIX}-prod  ACR_NAME=acr${PREFIX}prod  RESOURCE_GROUP=rg-${PREFIX}-prod"
