# AzureFriday-SREAgent — Working Memory

## What this repo is
Azure Friday demo lab for **Azure SRE Agent**. Deploys "Zava" e-commerce workload (3 App Service apps: .NET 8 storefront `app-<prefix>`, Node IT portal `-itportal`, Python warranty `-warranty`), Azure SQL (Basic 5 DTU), App Insights + Log Analytics, Azure Monitor alerts, dashboard. SRE Agent itself is created in the portal (sre.azure.com) — no ARM/Bicep path exists.

Scenarios: 1) slow query/missing index (DTU alert), 2) SQL blocking chain (KILL), 3) bad deployment (health 503 + GitHub correlation), 4) ServiceNow (optional, agent2).

## Key files
- Deploy: `infra/deploy.ps1`, `infra/main.bicep`, `deployment_plan.md` (agent-driven runbook)
- SRE config: `sre-config/agent1/` (hooks, skills, agents, tools, scheduledtasks) + `setup-scenarios-1-3.ps1`
- Sim: `simulator/demo.py`

## Review findings (2026-07-06) — deep review vs current SRE Agent docs

### Correctness bugs (verified)
1. **Hook matcher mismatch (HIGH)**: `change-risk-assessor.yaml` matcher `.*create_index.*|.*update_data.*|.*delete_data.*|.*insert_data.*` does NOT match real `mssql-mcp` tool names (`mssql_run_sql_query`, etc.). Docs: matchers anchored `^(pattern)$`, case-sensitive. => the global risk-assessment/approval hook likely never fires. `sql-write-guard` matcher `.*sql.*` DOES match. Approval still works INSIDE `sql-performance-investigator` subagent (calls `AssessChangeRisk` tool + `.*AssessChangeRisk.*` prompt hook), but not via top-level global hook.
2. **Connector/tool name inconsistency**: README connector = `zava-sql`, tools `mssql_run_sql_query`/`mssql_list_schema_objects`/etc. Skills reference `zava-mssql_mssql_execute_query`/`mssql_get_schema`/`mssql_connect_database` (different prefix + tool names not in README). Reconcile in one place. NEEDS their live tool names — don't guess.
3. **AssessChangeRisk.yaml**: dead line `is_business_hours = 14 <= hour <= 6` (always False) then reassigned. Uses deprecated `datetime.utcnow()`. Second line ~correct (UTC 14:00–06:00 ≈ 6AM–10PM Pacific).
4. **demo.py PerfGraph.to_panel()**: ~60 lines unreachable dead code after first `return Panel(...)`. Duplicate `_status()` def (first returns None on non-fast branches).
5. **weekly-cost-report.yaml**: uses `azuresre.ai/v1` (rest are v2); has BOTH `cron_expression:''` and `cron: 0 9 * * 1`; hardcodes `rg-zava` not `rg-zava-<suffix>`.

### Repo hygiene: GOOD. .gitignore covers bin/obj/publish/venv/zip/.env; no build artifacts tracked (verified `git ls-files` count 0).

### Missing/underused NEW SRE Agent features (for demo/townhall)
- **Persistent memory** ("knowledge that never leaves") — run Scenario 1 twice to show "I've seen this."
- **Deep investigation** (response plans currently leave it unchecked).
- **Share investigation thread deep-link** into Teams — great live townhall beat.
- **Teams/Slack connector** notifications (currently portal-only).
- **40+ managed MCP connectors** (Datadog/Grafana/Splunk/Dynatrace/CloudWatch) — multicloud talking point.
- **Managed ServiceNow/PagerDuty incident platform + indexing** — modernize Scenario 4 (currently custom python tool).
- **Track incident value** — MTTR/toil value slide for CIO audience.
- **Graduated trust**: Review (SQL fix) vs Autonomous (scheduled health check).
- Built-in subagents now: architecture, logs/metrics, source code, root cause analysis, scanning.

### Pricing/model notes to RE-VERIFY before customer session
- README: agent "$0.40/hr" + AAU; model "Anthropic (3x)" vs "Azure OpenAI (1x)". Verify vs pricing-billing page (not fetched).

## Status (2026-07-06)
- Code fixes DONE: demo.py dead code removed (compiles clean), AssessChangeRisk business-hours line, change-risk-assessor matcher -> `.*mssql.*|.*sql.*` + read short-circuit (README hook doc updated too), weekly-cost-report cron/RG.
- DEPLOYMENT ON HOLD per user ("not yet - wait"). Target confirmed: sub `MSFT-Provisioning-01[Prod]` (0832b3b6-22b3-4c47-8d8b-572054b97257), region `centralus`. Follow deployment_plan.md runbook when green-lit.
- Prereqs verified installed: az 2.84, dotnet 10.0.109 (repo targets net8.0 - framework-dependent publish OK), node 24, python 3.13, bicep 0.36.
- IN PROGRESS: townhall run-of-show doc + memory beat, README Teams/share-thread steps, Scenario 4 managed ServiceNow connector.
- STILL DEFERRED (needs live deploy): reconcile connector/tool names in skills vs README (get real tool names from portal Tools list after agent+SQL MCP connected).

## Done this session (2026-07-06)
- Code fixes: demo.py dead code removed (py_compile OK); AssessChangeRisk business-hours; change-risk-assessor matcher `.*mssql.*|.*sql.*` + read short-circuit; weekly-cost-report cron/RG. README hook-doc matcher updated.
- NEW doc: `docs/townhall-run-of-show.md` (pre-flight, ~20-min timed run-of-show, 4 signature beats incl. memory/run-twice + share-thread, talking points, fallback, reset).
- README: added "Step 7 — (Optional) Teams notifications and thread sharing" (Teams connector steps + Copy link to thread) before Part 3.
- README: modernized Scenario 4 to managed ServiceNow incident platform + indexing; kept two-agent split (Agent 1=Azure Monitor, Agent 2=ServiceNow — only ONE incident platform per agent); flagged quickstart-plan double-processing; marked custom LookupServiceNowIncident (embedded creds) as legacy fallback.
- Validated: all 10 sre-config YAML parse OK; demo.py compiles.
- Key constraint learned: only ONE incident platform active per agent at a time (switching disconnects the previous). Teams connector: one per agent, needs managed identity + Contributor.

## NEXT when user green-lights deploy
1. Follow deployment_plan.md: gen suffix, `az group create` centralus, run infra/deploy.ps1 with SecurityControl=Ignore tag, transient SQL pw (never print), runtime hardening (S2, startup cmds, disable Oryx), validate endpoints, disable SCM publishing.
2. .NET: only SDK 10 installed, project is net8.0 — framework-dependent publish to .NET 8 App Service runtime should be fine; watch `dotnet publish` for missing net8.0 ref pack.
3. After agent+SQL MCP connected: read real tool names from portal Tools list, reconcile skills (`zava-mssql_mssql_*`) vs actual (`zava-sql_mssql_*`).
