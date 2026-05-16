<#
.SYNOPSIS
    Prepares Azure SRE Agent configuration for demo Scenarios 1-3.

.DESCRIPTION
    Validates the deployed Zava workload, derives the Agent 1 connector values,
    and applies repo SRE Agent config when an existing SRE Agent context is
    provided. Azure SRE Agent creation is currently done in sre.azure.com; this
    script automates the repo side after that portal resource exists.

.PARAMETER ResourceGroup
    Resource group containing the deployed demo workload.

.PARAMETER Prefix
    Naming prefix used for the deployed workload.

.PARAMETER SreAgent1Id
    Existing SRE Agent 1 context/id. If provided and srectl is installed, the
    script applies Scenario 1-3 skills, hooks, tools, and extended agents.

.PARAMETER HttpTriggerUrl
    Agent 1 HTTP trigger URL for Scenario 3. If provided, the script prints the
    simulator environment variable to use. It is not written to disk.
#>

[CmdletBinding()]
param(
    [string]$ResourceGroup = 'rg-zava',
    [string]$Prefix = 'zava',
    [string]$SreAgent1Id = '',
    [string]$HttpTriggerUrl = ''
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent

function Write-Step { param([string]$Message) Write-Host "`n> $Message" -ForegroundColor Cyan }
function Write-Ok { param([string]$Message) Write-Host "  OK  $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "  WARN $Message" -ForegroundColor Yellow }

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI (az) is required.'
}

$SqlServer = "sql-$Prefix"
$SqlDatabase = "sqldb-$Prefix"
$MainApp = "app-$Prefix"
$DtuAlertName = "alert-$Prefix-dtu-high"
$Http5xxAlertName = "alert-$Prefix-http-5xx"
$HealthAlertName = "alert-$Prefix-health-check"
$MainAppUrl = "https://$MainApp.azurewebsites.net"

Write-Step 'Validating deployed Scenario 1-3 Azure resources'
$requiredResources = @(
    @{ Name = $SqlServer; Type = 'Microsoft.Sql/servers' },
    @{ Name = "$SqlServer/$SqlDatabase"; Type = 'Microsoft.Sql/servers/databases' },
    @{ Name = $MainApp; Type = 'Microsoft.Web/sites' },
    @{ Name = $DtuAlertName; Type = 'Microsoft.Insights/metricAlerts' },
    @{ Name = $Http5xxAlertName; Type = 'Microsoft.Insights/metricAlerts' },
    @{ Name = $HealthAlertName; Type = 'Microsoft.Insights/metricAlerts' }
)

$resources = az resource list --resource-group $ResourceGroup --query '[].{name:name,type:type}' -o json | ConvertFrom-Json
foreach ($required in $requiredResources) {
    $match = $resources | Where-Object { $_.name -eq $required.Name -and $_.type -ieq $required.Type } | Select-Object -First 1
    if ($match) {
        Write-Ok "$($required.Name) [$($required.Type)]"
    } else {
        Write-Warn "Missing $($required.Name) [$($required.Type)]"
    }
}

Write-Step 'Scenario 1-3 SRE Agent 1 connector values'
Write-Host 'Create/select Agent 1 in https://sre.azure.com, attached to the demo resource group.' -ForegroundColor White
Write-Host 'Add SQL MCP connector:' -ForegroundColor White
Write-Host '  Package: mssql-mcp@latest' -ForegroundColor Gray
Write-Host '  Command: npx' -ForegroundColor Gray
Write-Host '  Arguments: -y mssql-mcp@latest' -ForegroundColor Gray
Write-Host '  Environment variables:' -ForegroundColor Gray
Write-Host "    DB_SERVER=$SqlServer.database.windows.net" -ForegroundColor DarkGray
Write-Host "    DB_DATABASE=$SqlDatabase" -ForegroundColor DarkGray
Write-Host '    DB_USER=sqladmin' -ForegroundColor DarkGray
Write-Host '    DB_PASSWORD=<sql-password>' -ForegroundColor DarkGray
Write-Host '    DB_PORT=1433' -ForegroundColor DarkGray
Write-Host '    DB_ENCRYPT=true' -ForegroundColor DarkGray
Write-Host '    DB_TRUST_SERVER_CERTIFICATE=false' -ForegroundColor DarkGray
Write-Host ''
Write-Host 'For Scenario 3, create an HTTP trigger on Agent 1 and set:' -ForegroundColor White
Write-Host '  ZAVA_SRE_HTTP_TRIGGER_URL=<agent-http-trigger-url>' -ForegroundColor Gray
Write-Host 'Optional GitHub MCP connector for deployment-validator:' -ForegroundColor White
Write-Host '  Package: @github/github-mcp-server' -ForegroundColor Gray
Write-Host '  Environment variable: GITHUB_PERSONAL_ACCESS_TOKEN=<github-pat>' -ForegroundColor Gray

Write-Step 'Applying Agent 1 repo configuration when possible'
$srectl = Get-Command srectl -ErrorAction SilentlyContinue
if (-not $srectl) {
    Write-Warn 'srectl is not installed. Install it, create Agent 1 in sre.azure.com, then rerun this script with -SreAgent1Id.'
} elseif ([string]::IsNullOrWhiteSpace($SreAgent1Id)) {
    Write-Warn 'srectl is installed, but -SreAgent1Id was not provided. Skipping apply.'
} else {
    srectl config set-context $SreAgent1Id
    srectl apply -f "$RepoRoot\sre-config\agent1\skills\"
    srectl apply -f "$RepoRoot\sre-config\agent1\hooks\"
    srectl apply -f "$RepoRoot\sre-config\agent1\agents\"
    srectl apply -f "$RepoRoot\sre-config\agent1\tools\"
    srectl apply -f "$RepoRoot\sre-config\agent1\scheduledtasks\"
    Write-Ok 'Agent 1 skills, hooks, tools, and extended agents applied.'
}

Write-Step 'Simulator environment for Scenarios 1-3'
Write-Host "`$env:ZAVA_RESOURCE_GROUP = '$ResourceGroup'"
Write-Host "`$env:ZAVA_SQL_SERVER = '$SqlServer.database.windows.net'"
Write-Host "`$env:ZAVA_SQL_DATABASE = '$SqlDatabase'"
Write-Host "`$env:ZAVA_SQL_USER = 'sqladmin'"
Write-Host "`$env:ZAVA_SQL_PASSWORD = '<sql-password>'"
Write-Host "`$env:ZAVA_APP_NAME = '$MainApp'"
Write-Host "`$env:ZAVA_APP_URL = '$MainAppUrl'"
Write-Host "`$env:ZAVA_DTU_ALERT_NAME = '$DtuAlertName'"
if ($HttpTriggerUrl) {
    Write-Host "`$env:ZAVA_SRE_HTTP_TRIGGER_URL = '$HttpTriggerUrl'"
} else {
    Write-Host "`$env:ZAVA_SRE_HTTP_TRIGGER_URL = '<agent-1-http-trigger-url>'"
}

Write-Host ''
Write-Host 'Scenario readiness:' -ForegroundColor White
Write-Host '  Scenario 1: needs Agent 1 + SQL MCP + DTU alert handler.' -ForegroundColor Gray
Write-Host '  Scenario 2: needs Agent 1 + SQL MCP.' -ForegroundColor Gray
Write-Host '  Scenario 3: needs Agent 1 HTTP trigger; GitHub MCP is optional for deeper commit analysis.' -ForegroundColor Gray