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
- DEPLOYMENT ON HOLD per user ("not yet - wait"). Target CORRECTED 2026-07-06 (user caught wrong sub at Step 1): account `lv@volk.bike`, tenant `f1ab24dd-6f20-4b55-bc16-074d7aef4641`, subscription `LAB` = `64e4567b-012b-4966-9a91-b5c7c7b992de`, region `centralus`. (NOT the corp MSFT-Provisioning sub.) Follow deployment_plan.md runbook when green-lit.
- Prereqs verified installed: az 2.84, dotnet 10.0.109 (repo targets net8.0 - framework-dependent publish OK), node 24, python 3.13, bicep 0.36.
- IN PROGRESS: townhall run-of-show doc + memory beat, README Teams/share-thread steps, Scenario 4 managed ServiceNow connector.
- STILL DEFERRED (needs live deploy): reconcile connector/tool names in skills vs README (get real tool names from portal Tools list after agent+SQL MCP connected).
- CONFIRMED 2026-07-06 live: SQL MCP connector `zava-sql` test PASSED (no firewall fix needed), 14 tools auto-discovered, real prefix = `zava-sql_mssql_*` (connect_database, run_sql_query, etc.). Skills using `zava-mssql_mssql_*` should be reconciled to `zava-sql_mssql_*`. Hook matchers `.*sql.*` / `.*mssql.*|.*sql.*` both match these.
- PHASE 2 COMPLETE 2026-07-06: Agent zava-sreagent-1 (LAB sub 64e4567b, rg-zava-7813f0) fully wired: RG+logs context, zava-sql MCP connector Connected, zava-sre-logs Log Analytics connector, Azure Monitor incident platform connected, response plan `zava-response-plan` (matches alert-zava-7813f0-dtu-high, autonomy=Review, cooldown OFF, custom Scenario 1 plan), both hooks published via setup-scenarios-1-3.ps1. DTU alert demo-tuned 20%/PT1M. srectl NOT installed so skills/tools/subagents/scheduledtasks NOT applied (optional). NEXT = Phase 3 rehearse Scenario 1: set simulator env (ZAVA_* from $SqlPassword session var), run `python simulator/demo.py 1`.
- SIMULATOR LAUNCH LESSON 2026-07-06: async run_in_terminal spawns a FRESH terminal that does NOT inherit $env:ZAVA_* nor $SqlPassword set in the main sync session; VS Code also caches env so [Environment]::SetEnvironmentVariable(...,'User') does NOT reach newly-spawned terminals either. FIX: run the simulator in the MAIN sync terminal (mode=sync) where $env:ZAVA_* + $SqlPassword already live; it times out after ~20s and moves to background (get a terminal ID to monitor). Confirmed working: demo.py 1 dropped index, cleared plan cache, began expanding Products 20→~2,000,000 rows (one-time, few min) then hammers slow SELECTs → DTU spike → alert-zava-7813f0-dtu-high fires → incident. Simulator TUI (rich.Live) renders on alt screen so get_terminal_output shows blank/partial — monitor effect via az DTU metric + portal Incidents instead.

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

## GUIDED DEPLOY IN PROGRESS (2026-07-06)
- Step 1 DONE: authed to correct target lv@volk.bike / tenant f1ab24dd-6f20-4b55-bc16-074d7aef4641 / sub LAB 64e4567b-012b-4966-9a91-b5c7c7b992de. LAB is in an ALZ landing-zone tenant -> watch for Azure Policy at deploy; plan to pass SecurityControl=Ignore tag.
- Step 2 DONE: Suffix=7813f0, Prefix=zava-7813f0, RG=rg-zava-7813f0, region centralus. Vars set in run_in_terminal pwsh session. NOTE: multi-line pwsh here-strings get mangled in terminal -> use single-line ; separated commands. If session resets, re-run Step 2 as single line (suffix will differ) or reuse 7813f0 if RG exists.
- Step 3 NEXT = FIRST billable step: infra/deploy.ps1 -ResourceGroup $ResourceGroup -Location $Location -Prefix $Prefix -SqlPassword $SqlPassword -ResourceGroupTags SecurityControl=Ignore. Get explicit user go before running.
- Step 3 DONE + validated 2026-07-06: deploy.ps1 succeeded clean (no ALZ policy block, net8 build OK on SDK10). RG rg-zava-7813f0 centralus. Seed 20/10/20. All 3 apps deployed+started. Endpoints all 200: main /health {"status":"healthy","database":"connected"}, /api/products (20), itportal /, warranty /health. PHASE 1 COMPLETE.
- Skipped (apps healthy): plan Step 4 (SCM enable - zip worked), Step 5 (startup/Oryx hardening). PENDING optional: Step 11 (disable SCM publishing - security hygiene).
- SQL admin pw ONLY in $SqlPassword session var (never printed). Phase 2 SQL MCP connector DB_PASSWORD needs a known value -> reset pw securely at that step OR reuse $SqlPassword for simulator env (Phase 3).
- PHASE 2 NEXT (portal, README Part 2): create Agent 1 at sre.azure.com on rg-zava-7813f0; SQL MCP connector (zava-sql); Azure Monitor incident platform + response plans; deploy hooks via setup-scenarios-1-3.ps1.
- PHASE 2 PROGRESS: Agent 1 `zava-sreagent-1` CREATED 2026-07-06 (region East US 2, model Anthropic 3x, App Insights=Create new, LAB sub, rg-zava-7813f0). Deploy succeeded incl. managed identity + role assignments on RG + Log Analytics. User clicked "Set up your agent". NEXT: onboarding add-context (add rg-zava-7813f0 + logs), then reset SQL pw to known value for SQL MCP connector DB_PASSWORD, then add zava-sql MCP connector, Azure Monitor incident platform + response plans, hooks.
