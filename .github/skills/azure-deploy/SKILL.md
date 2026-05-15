---
name: azure-deploy
description: "Execute Azure deployments for already-prepared apps with .azure/deployment-plan.md and validated infrastructure. Triggers: run azd up, azd deploy, execute deployment, push to cloud, go live, ship it, bicep deploy, terraform apply, publish to Azure. Do not use for app creation or infrastructure setup; use azure-prepare first."
argument-hint: "Prepared Azure deployment command or target"
license: MIT
metadata:
  author: Microsoft
  version: "1.1.2"
---

# Azure Deploy

Executes deployments only after preparation and validation are complete.

Required sequence: `azure-prepare` -> `azure-validate` -> `azure-deploy`.

Before any deployment command, verify both prerequisites:

1. `.azure/deployment-plan.md` exists from `azure-prepare`.
2. Plan status is `Validated` and the Validation Proof section contains real validation results from `azure-validate`.

If either prerequisite is missing, stop and invoke the missing skill. Do not manually change the plan status to `Validated`; only `azure-validate` may do that after running validation checks.

## Triggers

Activate this skill when user wants to:
- Execute deployment of an already-prepared application (azure.yaml and infra/ exist)
- Push updates to an existing Azure deployment
- Run `azd up`, `azd deploy`, or `az deployment` on a prepared project
- Ship already-built code to production
- Deploy an application that already includes API Management (APIM) gateway infrastructure

Scope: This skill executes deployments. It does not create applications, generate infrastructure code, or scaffold projects. For those tasks, use `azure-prepare`.

APIM / AI Gateway: Use this skill only when APIM or AI gateway infrastructure was already created during `azure-prepare`. For AI governance policy changes, invoke `azure-aigateway`.

## Rules

1. Run only after `azure-prepare` and `azure-validate`.
2. Require `.azure/deployment-plan.md` with status `Validated` and populated Validation Proof.
3. Complete the [Pre-Deploy Checklist](references/pre-deploy-checklist.md).
4. Destructive actions require `ask_user`; see [global-rules](references/global-rules.md).
5. Deployment execution owns `azd up`, `azd deploy`, `terraform apply`, and `az deployment` commands plus error recovery and verification.

---

## Steps

| # | Action | Reference |
|---|--------|-----------|
| 1 | Check plan status and Validation Proof | `.azure/deployment-plan.md` |
| 2 | Complete all pre-deploy checks | [Pre-Deploy Checklist](references/pre-deploy-checklist.md) |
| 3 | Load the recipe for `recipe.type` | [recipes/README.md](references/recipes/README.md) |
| 4 | For Container Apps + ACR, verify RBAC propagation before proceeding | [Pre-Deploy Checklist](references/pre-deploy-checklist.md) |
| 5 | Execute deployment and recipe error recovery | Recipe README |
| 6 | Run post-deploy steps, verify endpoints, and confirm live RBAC roles | [Post-Deployment](references/recipes/azd/post-deployment.md), [Verification](references/recipes/azd/verify.md), [live-role-verification.md](references/live-role-verification.md) |
| 7 | Report deployed endpoint URLs as fully-qualified `https://` links | [Verification](references/recipes/azd/verify.md) |

Always present endpoint URLs with the `https://` scheme, even when Azure CLI returns bare hostnames.

## SDK Quick References

- **Azure Developer CLI**: [azd](references/sdk/azd-deployment.md)
- **Azure Identity**: [Python](references/sdk/azure-identity-py.md) | [.NET](references/sdk/azure-identity-dotnet.md) | [TypeScript](references/sdk/azure-identity-ts.md) | [Java](references/sdk/azure-identity-java.md)

## MCP Tools

| Tool | Purpose |
|------|---------|
| `mcp_azure_mcp_subscription_list` | List available subscriptions |
| `mcp_azure_mcp_group_list` | List resource groups in subscription |
| `mcp_azure_mcp_azd` | Execute AZD commands |
| `azure__role` | List role assignments for live RBAC verification (step 9) |

## References

- [Troubleshooting](references/troubleshooting.md) - Common issues and solutions
- [Post-Deployment Steps](references/recipes/azd/post-deployment.md) - SQL + EF Core setup
