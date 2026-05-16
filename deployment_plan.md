# Deployment Plan: Azure Friday SRE Agent Demo

This is the repeatable deployment runbook for the Zava Azure Friday SRE Agent demo. It is intentionally generic: a future agent should ask the operator only for the Azure tenant ID and subscription ID, then derive names, choose a viable region, deploy, validate, and hand off SRE Agent configuration.

## Operator Input

Ask for exactly these values:

| Value | Purpose |
| --- | --- |
| Azure tenant ID | Ensures `az login` and deployment target the correct tenant. |
| Azure subscription ID | The subscription where the demo environment will be created. |

Do not ask for a resource group name, prefix, region, SQL password, or app names. Generate or discover those during the plan.

## Naming and Secret Rules

Use a unique suffix so globally named Azure resources do not collide:

```powershell
$TenantId = '<tenant-id-from-operator>'
$SubscriptionId = '<subscription-id-from-operator>'
$Suffix = -join ((48..57) + (97..102) | Get-Random -Count 6 | ForEach-Object {[char]$_})
$Prefix = "zava-$Suffix"
$ResourceGroup = "rg-$Prefix"
$Location = $null
```

Derived resource names:

```powershell
$SqlServer = "sql-$Prefix"
$SqlDatabase = "sqldb-$Prefix"
$AppServicePlan = "asp-$Prefix"
$MainApp = "app-$Prefix"
$ItPortal = "app-$Prefix-itportal"
$WarrantyApp = "app-$Prefix-warranty"
$LogAnalytics = "law-$Prefix"
$AppInsights = "ai-$Prefix"
$DtuAlertName = "alert-$Prefix-dtu-high"
```

Generate a SQL admin password locally and never print it:

```powershell
$PasswordChars = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!#$%*+-_=?'
$SqlPassword = -join (1..32 | ForEach-Object { $PasswordChars[(Get-Random -Maximum $PasswordChars.Length)] })
```

Security rules:

- Never run commands that print publishing profiles or full connection strings.
- Never write real SQL passwords, publishing credentials, tokens, or PATs to files.
- If a secret is accidentally printed, rotate it immediately and reset publish profiles.
- Disable SCM basic publishing after app deployment is complete.
- Treat `.tmp_venv`, zip packages, logs, and publish folders as local artifacts, not commit candidates.

## Prerequisites

Verify required tools:

```powershell
az --version
dotnet --version
node --version
npm --version
python --version
```

Install the PowerShell SQL module if `sqlcmd` is unavailable:

```powershell
Install-Module SqlServer -Scope CurrentUser -Force
```

## Step 1: Authenticate and Select Subscription

```powershell
az login --tenant $TenantId
az account set --subscription $SubscriptionId
az account show --query "{name:name,id:id,tenantId:tenantId,user:user.name}" -o table
```

Confirm the account output matches the requested tenant and subscription before deploying.

## Step 2: Choose a Viable Region

Prefer `centralus`, then try other broadly available regions if needed:

```powershell
$CandidateLocations = @('centralus', 'eastus2', 'westus3', 'northcentralus', 'southcentralus')
```

Validate by attempting the deployment in the first candidate. If SQL provisioning, App Service quota, or policy blocks the region, delete the partial resource group and retry with the next candidate. Once a region works, keep it in `$Location` for all remaining commands.

Known issue patterns from prior deployments:

- SQL provisioning may be disabled in some regions.
- App Service quota may be exhausted in some regions.
- A policy may require `SecurityControl=Ignore` on the resource group to allow SQL authentication.

## Step 3: Deploy Infrastructure, Seed SQL, and Deploy Apps

Run from the repo root. The deploy script accepts resource group tags; keep the `SecurityControl=Ignore` tag because some tenants require it for this SQL-auth demo.

```powershell
$Location = 'centralus' # or the first viable candidate region

.\infra\deploy.ps1 `
  -ResourceGroup $ResourceGroup `
  -Location $Location `
  -Prefix $Prefix `
  -SqlPassword $SqlPassword `
  -ResourceGroupTags SecurityControl=Ignore
```

If seeding fails because both `sqlcmd` and `Invoke-Sqlcmd` are unavailable, install the `SqlServer` PowerShell module and rerun only seed/apps as needed:

```powershell
.\infra\deploy.ps1 `
  -ResourceGroup $ResourceGroup `
  -Location $Location `
  -Prefix $Prefix `
  -SqlPassword $SqlPassword `
  -ResourceGroupTags SecurityControl=Ignore `
  -SkipInfra
```

## Step 4: Temporarily Enable SCM Publishing If Zip Deploy Fails

Some subscriptions disable SCM basic publishing by default. If app zip deployment fails because publishing credentials are blocked, enable SCM publishing temporarily:

```powershell
$Apps = @($MainApp, $ItPortal, $WarrantyApp)

foreach ($App in $Apps) {
  az resource update `
    --ids "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Web/sites/$App/basicPublishingCredentialsPolicies/scm" `
    --set properties.allow=true `
    --output none
}
```

Disable it again in Step 11.

## Step 5: Apply Runtime Fixes

The template deploys the shared Linux App Service plan as `S2`. If an older template revision or manual deployment used `B1`/`S1`, scale it to `S2`; three Linux apps plus Kudu warmup can be unreliable on smaller plans in constrained subscriptions.

```powershell
az appservice plan update `
  --resource-group $ResourceGroup `
  --name $AppServicePlan `
  --sku S2 `
  --output none
```

Set explicit startup commands and avoid unnecessary runtime build/discovery work:

```powershell
az webapp config set `
  --resource-group $ResourceGroup `
  --name $MainApp `
  --startup-file 'dotnet AzureFridayApp.dll' `
  --output none

az webapp config appsettings delete `
  --resource-group $ResourceGroup `
  --name $MainApp `
  --setting-names ApplicationInsightsAgent_EXTENSION_VERSION `
  --output none

az webapp config appsettings set `
  --resource-group $ResourceGroup `
  --name $MainApp `
  --settings SCM_DO_BUILD_DURING_DEPLOYMENT=false ENABLE_ORYX_BUILD=false `
  --output none

az webapp config set `
  --resource-group $ResourceGroup `
  --name $ItPortal `
  --startup-file 'node server.js' `
  --output none

az webapp config appsettings set `
  --resource-group $ResourceGroup `
  --name $ItPortal `
  --settings SCM_DO_BUILD_DURING_DEPLOYMENT=false ENABLE_ORYX_BUILD=false `
  --output none

az webapp config set `
  --resource-group $ResourceGroup `
  --name $WarrantyApp `
  --startup-file 'python app.py' `
  --output none

az webapp config appsettings set `
  --resource-group $ResourceGroup `
  --name $WarrantyApp `
  --settings SCM_DO_BUILD_DURING_DEPLOYMENT=false ENABLE_ORYX_BUILD=false `
  --output none
```

Restart all apps:

```powershell
foreach ($App in @($MainApp, $ItPortal, $WarrantyApp)) {
  az webapp restart --resource-group $ResourceGroup --name $App --output none
}
```

## Step 6: Redeploy Warranty API If Needed

The warranty service in this repo is dependency-free and starts with `python app.py`. If the warranty endpoint returns `503`, redeploy it explicitly:

```powershell
if (Test-Path .\publish-warranty.zip) { Remove-Item .\publish-warranty.zip -Force }
Compress-Archive -Path .\warranty-tool\* -DestinationPath .\publish-warranty.zip -Force

az webapp stop `
  --resource-group $ResourceGroup `
  --name $WarrantyApp `
  --output none

az webapp deployment source config-zip `
  --resource-group $ResourceGroup `
  --name $WarrantyApp `
  --src .\publish-warranty.zip `
  --timeout 300

az webapp start `
  --resource-group $ResourceGroup `
  --name $WarrantyApp `
  --output none
```

`az webapp deploy` may work in many environments. If it returns a Kudu `502`, `az webapp deployment source config-zip` has been the reliable fallback for this repo.

## Step 7: Validate Azure Resources

```powershell
az appservice plan show `
  --resource-group $ResourceGroup `
  --name $AppServicePlan `
  --query '{sku:sku.name,tier:sku.tier,capacity:sku.capacity}' `
  -o table

az webapp list `
  --resource-group $ResourceGroup `
  --query '[].{name:name,state:state}' `
  -o table
```

Expected:

```text
Plan: S2 / Standard
Main app: Running
IT portal: Running
Warranty app: Running
```

Check App Service plan metrics:

```powershell
$PlanResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Web/serverfarms/$AppServicePlan"

az monitor metrics list `
  --resource $PlanResourceId `
  --metric CpuPercentage,MemoryPercentage `
  --interval PT1M `
  --aggregation Average `
  --query 'value[].{metric:name.value,latest:timeseries[0].data[-1].average}' `
  -o table
```

## Step 8: Validate Endpoints

Run a warm validation pass after app startup settles:

```powershell
$MainAppUrl = "https://$MainApp.azurewebsites.net"
$ItPortalUrl = "https://$ItPortal.azurewebsites.net"
$WarrantyUrl = "https://$WarrantyApp.azurewebsites.net"

$Urls = @(
  "$MainAppUrl/health",
  "$MainAppUrl/api/products",
  "$ItPortalUrl/",
  "$WarrantyUrl/health",
  "$WarrantyUrl/devices"
)

foreach ($Url in $Urls) {
  Write-Host "URL: $Url"
  curl.exe --max-time 30 --silent --show-error --write-out "`nHTTP %{http_code} in %{time_total}s`n" $Url | Select-Object -First 10
  Write-Host ''
}
```

Expected results:

- Main `/health`: `HTTP 200`, `{"status":"healthy","database":"connected"}`
- Main `/api/products`: `HTTP 200`, 20 seeded products
- IT portal `/`: `HTTP 200`, HTML page
- Warranty `/health`: `HTTP 200`, `{"status": "healthy"}`
- Warranty `/devices`: `HTTP 200`, 5 mock devices

## Step 9: Validate SQL Seed Data

Use the SQL password variable already held in memory:

```powershell
Invoke-Sqlcmd `
  -ServerInstance "$SqlServer.database.windows.net" `
  -Database $SqlDatabase `
  -Username 'sqladmin' `
  -Password $SqlPassword `
  -Query 'SELECT COUNT(*) AS Products FROM Products; SELECT COUNT(*) AS Orders FROM Orders; SELECT COUNT(*) AS OrderItems FROM OrderItems;'
```

Expected seed counts:

```text
Products: 20
Orders: 10
OrderItems: 20
```

## Step 10: Set Up Simulator

Use a local virtual environment. Do not install simulator packages globally.

```powershell
if (Test-Path .\.tmp_venv) { Remove-Item .\.tmp_venv -Recurse -Force }
python -m venv .\.tmp_venv
.\.tmp_venv\Scripts\python.exe -m pip install --upgrade pip
.\.tmp_venv\Scripts\python.exe -m pip install -r .\simulator\requirements.txt
```

Set simulator environment variables from the derived values:

```powershell
$env:ZAVA_SUBSCRIPTION_ID = $SubscriptionId
$env:ZAVA_RESOURCE_GROUP = $ResourceGroup
$env:ZAVA_SQL_SERVER = "$SqlServer.database.windows.net"
$env:ZAVA_SQL_DATABASE = $SqlDatabase
$env:ZAVA_SQL_USER = 'sqladmin'
$env:ZAVA_SQL_PASSWORD = $SqlPassword
$env:ZAVA_APP_URL = "https://$MainApp.azurewebsites.net"
$env:ZAVA_DTU_ALERT_NAME = $DtuAlertName
```

Smoke test simulator connectivity:

```powershell
.\.tmp_venv\Scripts\python.exe -c "import os, requests, pymssql; print('Health:', requests.get(os.environ['ZAVA_APP_URL'] + '/health', timeout=20).status_code); conn=pymssql.connect(server=os.environ['ZAVA_SQL_SERVER'], user=os.environ['ZAVA_SQL_USER'], password=os.environ['ZAVA_SQL_PASSWORD'], database=os.environ['ZAVA_SQL_DATABASE'], login_timeout=20, timeout=30); cur=conn.cursor(); cur.execute('SELECT COUNT(*) FROM Products'); print('Products:', cur.fetchone()[0]); conn.close()"
```

Expected:

```text
Health: 200
Products: 20
```

Run the simulator only when ready to demo scenarios:

```powershell
.\.tmp_venv\Scripts\python.exe .\simulator\demo.py
```

Skip ServiceNow setup and simulator scenario 4 unless ServiceNow has been intentionally added.

## Step 11: Disable SCM Publishing and Reset Publish Profiles

After all zip deployments are complete:

```powershell
foreach ($App in @($MainApp, $ItPortal, $WarrantyApp)) {
  az rest `
    --method post `
    --url "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Web/sites/$App/newpassword?api-version=2022-03-01" `
    --output none

  az resource update `
    --ids "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Web/sites/$App/basicPublishingCredentialsPolicies/scm" `
    --set properties.allow=false `
    --output none
}
```

## Step 12: SRE Agent Setup Handoff

Scenarios 1-3 are not complete until Agent 1 exists in Azure SRE Agent and is connected to the deployed workload. The Bicep template creates the workload, alert rules, App Insights, and dashboard; it does not create the SRE Agent portal resource. Current discovery found no ARM/Bicep resource type for SRE Agent creation, so create/select Agent 1 in `https://sre.azure.com`, then use the repo script below to validate and apply config.

Scenario 1-3 requirements:

| Scenario | Required SRE Agent setup |
| --- | --- |
| 1. Slow Query | Agent 1, SQL MCP connector, DTU alert handler, SQL diagnosis/fix skills, change-risk and SQL write hooks. |
| 2. Blocking Chain | Agent 1, SQL MCP connector, blocking diagnosis/fix skills, change-risk and SQL write hooks. |
| 3. Bad Deployment | Agent 1, Azure Monitor incident response plan matching the health-check alert, and GitHub MCP if commit/PR/issue analysis is desired. |

Install or verify `srectl`:

```powershell
Get-Command srectl -ErrorAction SilentlyContinue
```

Create Agent 1 in `sre.azure.com`:

```text
Name: zava-sreagent-1 or zava-sreagent-<suffix>
Resource group: <derived resource group>
Purpose: SQL performance, blocking diagnosis, app health, deployment validation
```

Add the SQL MCP connector to Agent 1:

```text
Name / connection ID: zava-sql
Transport: stdio
Command: npx
Arguments: two rows: -y and mssql-mcp@latest
Environment variables:
  DB_SERVER=<sql-server>.database.windows.net
  DB_DATABASE=<sql-database>
  DB_USER=sqladmin
  DB_PASSWORD=<secure-password>
  DB_PORT=1433
  DB_ENCRYPT=true
  DB_TRUST_SERVER_CERTIFICATE=false
```

For Scenario 1, create an Azure Monitor incident response plan matching the deployed DTU alert rule:

```powershell
$DtuAlertName
```

For Scenario 3, create another Azure Monitor incident response plan matching the health-check alert rule:

```powershell
$HealthAlertName
```

If GitHub analysis is part of the Scenario 3 demo, add the GitHub MCP connector to Agent 1:

```text
Package: @github/github-mcp-server
Environment variable: GITHUB_PERSONAL_ACCESS_TOKEN
Value: <github-pat>
```

Apply and validate Agent 1 config for Scenarios 1-3:

```powershell
.\sre-config\setup-scenarios-1-3.ps1 `
  -ResourceGroup $ResourceGroup `
  -Prefix $Prefix `
  -SreAgent1Id '<agent-1-id>'
```

The helper validates the deployed resources, prints connector values with placeholders instead of secrets, and applies these Agent 1 assets when `srectl` is available:

```powershell
srectl config set-context <agent-1-id>
srectl apply -f sre-config/agent1/skills/
srectl apply -f sre-config/agent1/hooks/
srectl apply -f sre-config/agent1/agents/
srectl apply -f sre-config/agent1/tools/
srectl apply -f sre-config/agent1/scheduledtasks/
```

Set local simulator variables for Scenarios 1-3:

```powershell
$env:ZAVA_RESOURCE_GROUP = $ResourceGroup
$env:ZAVA_SQL_SERVER = "$SqlServer.database.windows.net"
$env:ZAVA_SQL_DATABASE = $SqlDatabase
$env:ZAVA_SQL_USER = 'sqladmin'
$env:ZAVA_SQL_PASSWORD = $SqlPassword
$env:ZAVA_APP_NAME = $MainApp
$env:ZAVA_APP_URL = "https://$MainApp.azurewebsites.net"
$env:ZAVA_DTU_ALERT_NAME = $DtuAlertName
```

Agent 2 is only needed for Scenario 4, which this runbook skips by default. If Scenario 4 is later enabled, create/select Agent 2 in the SRE Agent portal and apply its config:

```powershell
srectl config set-context <agent-2-id>
srectl apply -f sre-config/agent2/agents/
srectl apply -f sre-config/agent2/tools/
```

Before testing Agent 2, configure its Python tool runtime with the derived warranty API URL if the SRE Agent environment supports tool environment variables:

```text
ZAVA_WARRANTY_API_URL=https://<warranty-app-name>.azurewebsites.net
```

If tool environment variables are not supported, update the `WARRANTY_API_URL` value in the CheckWarranty tool during portal setup to the derived `$WarrantyUrl` for this deployment. Do not commit deployment-specific URLs back to the repo.

Skip ServiceNow connector/setup unless scenario 4 is intentionally reintroduced.

## Cleanup and Recreate

To remove the environment created by this run:

```powershell
az group delete --name $ResourceGroup --yes --no-wait
```

Do not delete any other resource group unless it was created by the same deployment run and verified as disposable.

## Final Commit Readiness Checklist

Before committing repo changes:

- Run `git status --short` and confirm no generated artifacts are staged (`.tmp_venv`, zip files, logs, `publish-*`, `bin`, `obj`, `node_modules`).
- Run a secret scan for the tenant/subscription used in testing and for common credential markers.
- Confirm `deployment_plan.md` contains placeholders or derived variables, not a specific operator tenant, subscription, resource group, or app URL.
- Confirm warranty endpoints still return the expected JSON shapes after the dependency-free Python service rewrite.
- Confirm ServiceNow scenario remains skipped unless ServiceNow setup is intentionally added.