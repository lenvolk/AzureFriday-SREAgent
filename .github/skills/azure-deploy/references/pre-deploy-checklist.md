# Pre-Deploy Checklist

Complete this checklist before running `azd up`, `azd deploy`, `terraform apply`, or `az deployment` from the `azure-deploy` skill.

## Required Gates

- Confirm `.azure/deployment-plan.md` exists.
- Confirm the plan status is `Validated`.
- Confirm the Validation Proof section contains actual commands, timestamps, and results from `azure-validate`.
- Confirm the active Azure subscription, tenant, resource group, and location match the plan.
- Confirm destructive actions have explicit user approval before execution.
- Confirm required secrets are already configured through approved secret stores or deployment tooling; do not ask the user to paste secrets into chat.

If any gate fails, stop and invoke the missing prerequisite skill or ask for the required approval.

## Tooling Checks

- `az account show` returns the intended subscription and tenant.
- `azd version` is available when the recipe uses Azure Developer CLI.
- Terraform, Bicep, or Azure CLI dependencies required by the selected recipe are installed.
- Required providers or extensions are present for the recipe.
- The working tree contains the infrastructure files named in the plan.

## RBAC Checks

- The signed-in principal can create or update the planned resource types.
- Managed identities named in the plan exist or will be created by the recipe.
- Role assignments required by the app are represented in infrastructure, not only in manual notes.
- For Container Apps pulling from ACR, run provisioning first when needed, then verify `AcrPull` has propagated before deploying the app revision.

## Data And Migration Checks

- Database connection settings are planned and do not expose secrets.
- EF migrations or SQL scripts are identified before deployment when the app requires schema changes.
- Rollback or restore expectations are clear for production data changes.

## Network And Endpoint Checks

- Public, private, or hybrid network exposure matches the plan.
- DNS, custom domains, certificates, and ingress settings are accounted for.
- Health endpoints or smoke-test URLs are known before deployment starts.

## Execute

After all checks pass, load the recipe from [recipes/README.md](recipes/README.md), execute its steps, handle errors from the recipe's `errors.md`, and verify success with [recipes/azd/verify.md](recipes/azd/verify.md) or the matching recipe verification file.

Always report deployed endpoints as fully-qualified `https://` URLs.
