# Azure Townhall — SRE Agent Demo Run-of-Show

A tight, ~20-minute run-of-show for demoing **Azure SRE Agent** with the Zava lab to a customer audience (mixed IT leaders + engineers). Scenarios 1–3 are the core; Scenario 4 is optional for ITSM-focused rooms.

> Full setup lives in [`README.md`](../README.md). This doc is only the *live delivery* plan.

---

## Pre-flight checklist (do this 30 min before)

- [ ] Infra deployed and healthy: `curl https://app-<prefix>.azurewebsites.net/health` → `{"status":"healthy","database":"connected"}`.
- [ ] Agent 1 exists at <https://sre.azure.com>, attached to `rg-zava-<suffix>`, model provider selected.
- [ ] Connectors green: **SQL MCP** (`zava-sql`) shows **Connected**; GitHub MCP connected (for Scenario 3).
- [ ] Response plans exist: `zava-response-plan` (DTU) and `zava-health-response-plan` (health), both in **Review** mode.
- [ ] Hooks deployed: `change-risk-assessor` + `sql-write-guard` visible under **Builder → Hooks**.
- [ ] Simulator env vars set in your terminal (see README Part 3), `python simulator/demo.py` opens without errors.
- [ ] *(Optional)* Teams connector added and a channel open on a second screen for the "share thread" beat.
- [ ] **Fallback ready:** a short screen recording of a successful Scenario 1 run, in case live alert timing is slow.
- [ ] Reset state: run `python simulator/demo.py 5` (reset) so no leftover index/blocking from rehearsal.

---

## The narrative arc (say this)

> "It's 2:47 AM. An alert fires on your storefront. Today that means someone wakes up and opens five tabs — the alert, the metrics, the logs, the deployment history, and Slack. Tonight, watch what happens instead: one investigation, with the answer already in it — what changed, what's affected, and what to do next. And nothing changes production without a human saying yes."

Then run Scenario 1. Keep talking while the DTU alert builds.

---

## Timed run-of-show (~20 min)

| Time | Beat | You do | You say / audience sees |
|------|------|--------|--------------------------|
| 0:00 | **Cold open** | Show the Zava storefront + the SRE Agent activity feed side by side | The "5 tabs at 3 AM" framing above |
| 2:00 | **Scenario 1 — Slow query** | `python simulator/demo.py 1` | Latency climbs to ~800–2000 ms; DTU alert `alert-<prefix>-dtu-high` fires; agent opens an investigation |
| 5:00 | **Root cause** | Point at the agent's findings | "It connected to SQL, read the plan, found a missing index on `Products.Category` — no runbook, no tab-switching" |
| 6:30 | **Human-in-the-loop** | **Approve** the `CREATE INDEX` on stage | "It won't touch production without me. The risk hook flagged it; I approve." → latency drops to ~5 ms |
| 8:30 | **Memory beat (run twice)** | `python simulator/demo.py 1` again | "Watch — it remembers. 'I've seen this before, here's the fix.' That knowledge stays even when the expert is on vacation." |
| 11:00 | **Scenario 2 — Blocking chain** | `python simulator/demo.py 2` | Agent finds the head blocker via DMVs and **kills the SPID after approval** — "it can safely *take an action*, behind a guardrail" |
| 14:00 | **Scenario 3 — Bad deploy** | `python simulator/demo.py 3` → press `b` | Health → 503, alert fires, agent correlates the App Service config change (and GitHub commit), proposes restoring the connection string |
| 17:00 | **Share + value** | Copy thread link → paste in Teams; open **Monitor → Incident metrics** | "I can hand this thread to a teammate instantly. And here's the value: incidents mitigated, MTTR trend." |
| 19:00 | **Close** | Recap the three beats | "Diagnose, remediate with approval, and get smarter over time — across your whole Azure estate." |

Trim to ~12 min by dropping Scenario 2 and the memory beat.

---

## Four signature beats (the ones customers remember)

1. **Human-in-the-loop approval.** The `CREATE INDEX` (Scenario 1) and `KILL` (Scenario 2) both pause for your **Approve**. This is the trust story: *the agent proposes, a human disposes.* Emphasize `change-risk-assessor` (business-hours/blast-radius reasoning) and `sql-write-guard` (hard block on `DROP`/`DELETE`/`TRUNCATE`).
2. **Memory / "run it twice."** Persistent memory means the second Scenario 1 run is faster and references the prior fix. This is the "knowledge that never leaves" story — great for teams worried about tribal knowledge and on-call quality.
3. **Share the investigation thread.** Open the thread → **⋯** → **Copy link to thread** → paste into Teams. The audience follows the agent's reasoning live; it feels real, not staged.
4. **Value / graduated trust.** Show **Monitor → Incident metrics** (Track incident value) for MTTR/mitigation numbers. Mention run modes: **Review** for the risky SQL fix vs **Autonomous** for a routine scheduled health check (`sre-config/agent1/scheduledtasks/weekly-cost-report`).

---

## Talking points for the "so what" questions

- **"Does it work with our non-Azure tools?"** Yes — 40+ managed MCP connectors (Datadog, Grafana, Splunk, Dynatrace, New Relic, AWS CloudWatch, GCP Stackdriver), plus any custom MCP server. It meets you where your observability already lives.
- **"How do we keep it safe?"** Review mode gates every Azure write behind approval; hooks and tool-access policies gate everything else; audit telemetry routes to your own Application Insights.
- **"What does it cost?"** The agent bills separately from the workload (verify the current rate on the [pricing page](https://learn.microsoft.com/en-us/azure/sre-agent/pricing-billing) before quoting). The Zava workload itself is ~$78/mo.
- **"Which incidents can it take?"** Azure Monitor, PagerDuty, or ServiceNow — one active incident platform per agent.

---

## Fallback plan

- **DTU alert is slow to fire.** The lab tunes it to DTU > 20% over 1 min, but Azure Monitor can still take 2–5 min. Keep narrating; if it stalls past ~5 min, cut to the pre-recorded clip and continue.
- **Connector shows disconnected.** Re-open **Builder → Connectors**, confirm `zava-sql` is **Connected**; if not, the SQL password may have drifted (see README "Connection string drift").
- **Agent doesn't act on the alert.** Confirm the response plan title filter matches the alert name and the agent's managed identity has **Monitoring Contributor** on the resource group.

---

## Reset between takes

```powershell
python simulator/demo.py 5   # reset: drops demo index, clears blocking, restores good config
```

Re-check `/health` returns 200 before the next run.
