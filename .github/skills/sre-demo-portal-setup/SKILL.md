---
name: sre-demo-portal-setup
description: 'Beginner-friendly, click-by-click guidance for the Azure SRE Agent PORTAL setup (Part 2) of the Zava Azure Friday demo. Use when guiding a new user through https://sre.azure.com for THIS repo: create the SRE Agent, attach the SQL MCP connector, connect Azure Monitor and build the Scenario 1 response plan, and deploy the governance hooks. Also use when a user asks how to set up the SRE Agent, add the SQL connector, create a response plan, wire alerts, or "the portal part". Pairs with the SREdemo agent. Field-level values live in README Part 2.'
---

# SRE Agent portal setup — click-by-click (Part 2)

## When to use

After Part 1 (infrastructure + apps are deployed and validated), use this to guide a **new** user
through the browser steps at <https://sre.azure.com>. The portal cannot be fully automated, so your
job is to give calm, numbered, one-at-a-time directions and confirm what they see at each step.

## How to guide (pacing)

- **One step per message.** Post a step, then wait. Ask "what do you see?" and let them answer.
- **Name the exact button/field** to click or type. Prefer bold labels: click **Create Agent**.
- **Confirm before moving on.** Only advance when the previous step shows the expected result.
- Full field-by-field values are in **README Part 2** — read it and quote the exact values for the
  user's `<prefix>` (for example `zava-7813f0`). This skill is the *pacing + gotchas*; README is the
  *reference table*.

## The four portal steps

### 1. Create Agent 1

1. Go to <https://sre.azure.com> and click **Create Agent**.
2. On **Basics** set: **Subscription** = the one from Part 1; **Resource group** = `rg-zava-<suffix>`;
   **Agent name** = `zava-sreagent-1`; **Region** = any SRE-Agent-supported region shown;
   **Model provider** = `Anthropic (3x)`; **Application Insights** = **Use existing** → `ai-<prefix>`.
3. **Next** → **Deploy**, and wait for provisioning to finish.
4. If a **"More context. Better investigations."** screen appears, add **Azure resources**
   (`rg-zava-<suffix>`) and **Logs**, then **Done and go to agent**.
5. Success looks like the agent home with a green connector bar. → `docs/images/sre-agent-home.png`

### 2. Attach the SQL MCP connector (`zava-sql`)

> **MCP** = Model Context Protocol: a standard way to give the agent a tool. Here it's a SQL tool so
> the agent can inspect the database.

1. **Builder → Connectors → + Add connector → MCP Server**.
2. If asked for transport, choose **Stdio** (local process).
3. **Name** = `zava-sql`; **Command** = `npx`; **Arguments** = **two separate rows**: `-y` and
   `mssql-mcp@latest`. *(Do not combine them into one row — `npx` will fail.)*
4. Add env vars: `DB_SERVER=sql-<prefix>.database.windows.net`, `DB_DATABASE=sqldb-<prefix>`,
   `DB_USER=sqladmin`, `DB_PASSWORD=<the SQL password from Part 1>`, `DB_PORT=1433`,
   `DB_ENCRYPT=true`, `DB_TRUST_SERVER_CERTIFICATE=false`.
5. Save and wait for status **Connected**, then pick the SQL tools (`mssql_run_sql_query`,
   `mssql_read_table_rows`, etc.). → `docs/images/sql-mcp-connector.png`

### 3. Connect Azure Monitor + build the Scenario 1 response plan

1. **Builder → Incident platform → Azure Monitor →** save.
2. **Builder → Incident response plans → create** `zava-response-plan`:
   - **Title contains** = `alert-<prefix>-dtu-high`
   - Check **I want a custom response plan** and paste the Scenario 1 plan text from README Part 2.
   - **Agent autonomy = Review** (so it asks before changing SQL — this is the demo's key moment).
   - **Alert reinvestigation cooldown = disabled** while rehearsing.
3. Save. → `docs/images/response-plan.png`

### 4. Deploy the governance hooks (terminal, not portal)

Run: `./sre-config/setup-scenarios-1-3.ps1 -ResourceGroup <rg> -Prefix <prefix>`

This publishes two safety hooks via REST and confirms the DTU alert is demo-tuned:
- **`change-risk-assessor`** — reviews SQL changes for risk (human-in-the-loop).
- **`sql-write-guard`** — blocks destructive SQL (`DROP`/`DELETE`/`TRUNCATE`).

A `srectl is not installed` warning is fine for Scenarios 1–3. To verify, open **Builder → Hooks**
and confirm both hooks are listed.

## Common confusion points (call these out proactively)

- **Stdio vs Streamable-HTTP** for the MCP connector: choose **Stdio**.
- **Arguments must be two rows** (`-y`, then `mssql-mcp@latest`).
- The response-plan **custom plan text box** appears only after you check *"I want a custom response
  plan"* — it may be on a later step of the wizard.
- **Managed identity** on the SQL connector: leave whatever the portal defaults to; auth actually
  comes from the `DB_*` variables.
- If **no incident appears** during Scenario 1, it's usually just timing — Azure Monitor fires ~5–8
  minutes after a sustained DTU breach, and the first simulator run spends minutes expanding data.

## Optional (Scenario 3 only)

- **GitHub MCP connector** (`zava-github`) for commit correlation — README Part 2 Step 3.
- **`zava-health-response-plan`** matching `alert-<prefix>-health-check` — README Part 2 Step 5.

## Reference

Exact field values and screenshots: [`README.md`](../../../README.md) Part 2. Live-delivery timings:
[`docs/townhall-run-of-show.md`](../../../docs/townhall-run-of-show.md).
