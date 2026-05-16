<#
.SYNOPSIS
    Prepares Azure SRE Agent configuration for demo Scenarios 1-3.

.DESCRIPTION
    Validates the deployed Zava workload, derives the Agent 1 connector values,
    and applies repo SRE Agent hooks. Azure SRE Agent creation is currently done
    in sre.azure.com; this script automates the repo side after that portal
    resource exists.

.PARAMETER ResourceGroup
    Resource group containing the deployed demo workload.

.PARAMETER Prefix
    Naming prefix used for the deployed workload.

.PARAMETER SreAgent1Id
    Existing SRE Agent 1 ARM resource ID. If omitted, the script auto-detects a
    single Microsoft.App/agents resource in the resource group. The script uses
    this ID to apply Scenario 1-3 hooks through the SRE Agent data-plane API. If
    srectl is installed, it also applies the rest of the repo YAML.

.PARAMETER HttpTriggerUrl
    Optional legacy Agent 1 HTTP trigger URL for Scenario 3. Current portal
    setup uses Azure Monitor health-check alerts instead.
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

function Get-YamlScalar {
    param(
        [string[]]$Lines,
        [string]$Name
    )

    $match = $Lines | Where-Object { $_ -match "^\s+$([regex]::Escape($Name)):\s*(.+)$" } | Select-Object -First 1
    if (-not $match) { return $null }
    return ([regex]::Match($match, "^\s+$([regex]::Escape($Name)):\s*(.+)$").Groups[1].Value).Trim('"')
}

function Get-YamlBlock {
    param(
        [string[]]$Lines,
        [string]$Name
    )

    $start = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match "^\s{4}$([regex]::Escape($Name)):\s*\|\s*$") {
            $start = $i + 1
            break
        }
    }
    if ($start -lt 0) { throw "Could not find YAML block '$Name'." }

    $block = [System.Collections.Generic.List[string]]::new()
    for ($i = $start; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        if ($line -match '^\s{0,4}\S') { break }
        if ($line.StartsWith('      ')) {
            $block.Add($line.Substring(6))
        } elseif ($line.Trim().Length -eq 0) {
            $block.Add('')
        } else {
            $block.Add($line.TrimStart())
        }
    }

    return ($block -join "`n").TrimEnd()
}

function Resolve-SreAgentId {
    param(
        [string]$ResourceGroup,
        [string]$ProvidedAgentId
    )

    if (-not [string]::IsNullOrWhiteSpace($ProvidedAgentId)) {
        return $ProvidedAgentId
    }

    $agents = @(az resource list --resource-group $ResourceGroup --resource-type 'Microsoft.App/agents' --query '[].id' -o tsv 2>$null)
    if ($agents.Count -eq 1) {
        Write-Ok "Auto-detected SRE Agent: $($agents[0])"
        return $agents[0]
    }

    if ($agents.Count -eq 0) {
        Write-Warn "No Microsoft.App/agents resource found in $ResourceGroup. Create/select Agent 1 in sre.azure.com, then rerun with -SreAgent1Id."
    } else {
        Write-Warn "Found multiple SRE Agents in $ResourceGroup. Rerun with -SreAgent1Id set to the target agent ARM resource ID."
    }
    return ''
}

function Publish-SreAgentHook {
    param(
        [string]$Endpoint,
        [hashtable]$Headers,
        [string]$Path
    )

    $lines = Get-Content -Path $Path
    $name = Get-YamlScalar -Lines $lines -Name 'name'
    $eventType = Get-YamlScalar -Lines $lines -Name 'eventType'
    $activationMode = Get-YamlScalar -Lines $lines -Name 'activationMode'
    $description = Get-YamlScalar -Lines $lines -Name 'description'
    $hookType = Get-YamlScalar -Lines $lines -Name 'type'
    $matcher = Get-YamlScalar -Lines $lines -Name 'matcher'
    $timeout = [int](Get-YamlScalar -Lines $lines -Name 'timeout')

    if (-not $name -or -not $eventType -or -not $activationMode -or -not $hookType -or -not $matcher) {
        throw "Hook YAML '$Path' is missing required metadata."
    }

    $hook = @{
        type = $hookType
        matcher = $matcher
        timeout = $timeout
    }

    $model = Get-YamlScalar -Lines $lines -Name 'model'
    if ($model) { $hook.model = $model }

    $failMode = Get-YamlScalar -Lines $lines -Name 'failMode'
    $hook.failMode = if ($failMode) { $failMode.ToLowerInvariant() } else { 'allow' }

    if ($hookType -eq 'prompt') {
        $hook.prompt = Get-YamlBlock -Lines $lines -Name 'prompt'
    } elseif ($hookType -eq 'command') {
        $hook.script = Get-YamlBlock -Lines $lines -Name 'script'
    } else {
        throw "Unsupported hook type '$hookType' in '$Path'."
    }

    $body = @{
        name = $name
        type = 'GlobalHook'
        properties = @{
            eventType = $eventType
            activationMode = $activationMode
            description = $description
            hook = $hook
        }
    } | ConvertTo-Json -Depth 20

    $response = Invoke-WebRequest -Method Put -Uri "$Endpoint/api/v2/extendedAgent/hooks/$name" -Headers $Headers -Body $body -UseBasicParsing
    if ($response.StatusCode -lt 200 -or $response.StatusCode -gt 299) {
        throw "Publishing hook '$name' returned HTTP $($response.StatusCode)."
    }
    Write-Ok "Published hook: $name"
}

function Publish-SreAgentHooks {
    param(
        [string]$AgentId
    )

    if ([string]::IsNullOrWhiteSpace($AgentId)) { return }

    $apiVersion = '2025-05-01-preview'
    $agentUrl = "https://management.azure.com$AgentId`?api-version=$apiVersion"
    $agent = az rest --method GET --url $agentUrl | ConvertFrom-Json
    $endpoint = $agent.properties.agentEndpoint
    if ([string]::IsNullOrWhiteSpace($endpoint)) {
        throw "Could not read properties.agentEndpoint from $AgentId."
    }

    $token = az account get-access-token --resource 'https://azuresre.dev' --query accessToken -o tsv
    $headers = @{
        Authorization = "Bearer $token"
        'Content-Type' = 'application/json'
    }

    $hookFiles = @(Get-ChildItem -Path "$RepoRoot\sre-config\agent1\hooks" -Filter '*.yaml' -File | Sort-Object Name)
    foreach ($hookFile in $hookFiles) {
        Publish-SreAgentHook -Endpoint $endpoint -Headers $headers -Path $hookFile.FullName
    }
}

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
Write-Host '  Arguments: two rows: -y and mssql-mcp@latest' -ForegroundColor Gray
Write-Host '  Environment variables:' -ForegroundColor Gray
Write-Host "    DB_SERVER=$SqlServer.database.windows.net" -ForegroundColor DarkGray
Write-Host "    DB_DATABASE=$SqlDatabase" -ForegroundColor DarkGray
Write-Host '    DB_USER=sqladmin' -ForegroundColor DarkGray
Write-Host '    DB_PASSWORD=<sql-password>' -ForegroundColor DarkGray
Write-Host '    DB_PORT=1433' -ForegroundColor DarkGray
Write-Host '    DB_ENCRYPT=true' -ForegroundColor DarkGray
Write-Host '    DB_TRUST_SERVER_CERTIFICATE=false' -ForegroundColor DarkGray
Write-Host ''
Write-Host 'For Scenario 3, create an Azure Monitor response plan matching:' -ForegroundColor White
Write-Host "  $HealthAlertName" -ForegroundColor Gray
Write-Host 'Optional GitHub MCP connector for deployment-validator:' -ForegroundColor White
Write-Host '  Package: @github/github-mcp-server' -ForegroundColor Gray
Write-Host '  Environment variable: GITHUB_PERSONAL_ACCESS_TOKEN=<github-pat>' -ForegroundColor Gray

Write-Step 'Applying Agent 1 repo hooks'
$resolvedSreAgent1Id = Resolve-SreAgentId -ResourceGroup $ResourceGroup -ProvidedAgentId $SreAgent1Id
Publish-SreAgentHooks -AgentId $resolvedSreAgent1Id

Write-Step 'Applying remaining Agent 1 repo YAML when srectl is available'
$srectl = Get-Command srectl -ErrorAction SilentlyContinue
if (-not $srectl) {
    Write-Warn 'srectl is not installed. Hooks were applied through REST when an agent was found; skipping skills, tools, agents, and scheduled tasks.'
} elseif ([string]::IsNullOrWhiteSpace($resolvedSreAgent1Id)) {
    Write-Warn 'srectl is installed, but no SRE Agent ARM resource ID was resolved. Skipping srectl apply.'
} else {
    srectl config set-context $resolvedSreAgent1Id
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
    Write-Host '# Optional legacy HTTP trigger path:'
    Write-Host "`$env:ZAVA_SRE_HTTP_TRIGGER_URL = '$HttpTriggerUrl'"
}

Write-Host ''
Write-Host 'Scenario readiness:' -ForegroundColor White
Write-Host '  Scenario 1: needs Agent 1 + SQL MCP + Azure Monitor response plan for DTU alert.' -ForegroundColor Gray
Write-Host '  Scenario 2: needs Agent 1 + SQL MCP.' -ForegroundColor Gray
Write-Host '  Scenario 3: needs Azure Monitor response plan for health-check alert; GitHub MCP is optional for deeper commit analysis.' -ForegroundColor Gray