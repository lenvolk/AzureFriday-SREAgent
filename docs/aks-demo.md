# AKS auto-triage/repair demo (network-heavy customers)

A tight, **AKS-focused** track for the SRE Agent demo, built for an **AKS-heavy audience** and a
**~1-hour session** (PowerPoint + live demo + Q&A). It shows the agent **auto-triaging and repairing**
two of the most common real incidents — a **network partition** and a **bad deployment** — on a
**private AKS cluster**, plus a zero-risk **"interrogate the firewall"** chat beat.

> **We reuse the companion `zava-aks-postgres` lab — we do not rebuild it.** That lab is a complete
> `azd up` deployment (private AKS + PostgreSQL Flexible Server + hub-and-spoke with an Azure Firewall +
> a **VNet-injected** SRE Agent, all declared in Bicep). This page curates its scenarios for a short,
> network-centric session. For depth, see the lab's own `README.md`.
>
> **Where the lab lives:** the `sre-agent` repo under `labs/zava-aks-postgres/`
> (on this machine: `C:\Temp\GHDemo\sre-agent-main\labs\zava-aks-postgres`).

---

## Why this resonates with a network-heavy customer

- The agent is **VNet-injected** and its egress is **forced through an Azure Firewall** — it operates
  *inside* the customer's network boundary, exactly like a real landing zone (hub-and-spoke).
- It reaches the **private** AKS API server with **native `kubectl`** (its own managed identity) and
  talks to **private** PostgreSQL through an in-cluster pod — no public endpoints.
- The firewall doubles as a **"network device" the agent can interrogate** (read its policy over ARM +
  query `AZFW*` logs via KQL) — a great talking point for network teams.

---

## Prerequisites

| Need | Notes |
|------|-------|
| Azure subscription | With **AKS + Azure Firewall + PostgreSQL Flex** quota in one region |
| Azure Developer CLI (`azd`) | `winget install Microsoft.Azd` |
| Azure CLI + PowerShell 7 | Already required for the App Service track |
| The `zava-aks-postgres` lab | Clone the `sre-agent` repo; the lab is under `labs/zava-aks-postgres/` |

> **Deploy the day before.** `azd up` takes **~25 minutes** (AKS + firewall + Postgres + agent). Do
> **not** deploy live. Pre-warm the storefront and confirm the agent is green before the session.

---

## One-time setup (do this ahead of time)

```powershell
cd C:\Temp\GHDemo\sre-agent-main\labs\zava-aks-postgres
azd up            # ~25 min — deploys everything and configures the SRE Agent from Bicep
```

When it finishes, `azd` prints the storefront URL. Open it and confirm **`ALL SYSTEMS OPERATIONAL`**,
~50 products, and a healthy DB response. In the SRE portal, confirm the agent
(`sre-agent-zava-<suffix>`) shows its connectors and response plans.

> The lab's SRE Agent runs in **autonomous mode with High access** by design — it **auto-repairs**
> without waiting for approval. That's the point of *this* track: **"watch it fix itself."** (The
> App Service track is where we show the human-in-the-loop *Review* gate; here we show hands-off
> auto-remediation. Two complementary stories.)

---

## The 1-hour run of show

| Time | Segment | What happens |
|------|---------|--------------|
| 0:00–0:15 | **PowerPoint** | SRE Agent value; architecture (private AKS, VNet-injected agent, hub-spoke firewall) |
| 0:15–0:20 | **Firewall interrogation** (chat, no break) | Agent reads the firewall policy + `AZFW*` denies — "it lives inside your network" |
| 0:20–0:40 | **Scenario 2 — Network Partition** 🏆 | Break → agent triages past the NSG red herring → removes the `NetworkPolicy` → storefront recovers |
| 0:40–0:50 | **Scenario 4 — Bad Deploy** *(optional)* | Break → agent correlates 5xx with the rollout → `kubectl rollout undo` |
| 0:50–1:00 | **Q&A** | |

If the room is deep on networking, spend the extra time on Scenario 2 + firewall Q&A and skip
Scenario 4.

---

## Segment 1 — Interrogate the firewall (zero-risk opener)

No break needed. In the SRE Agent chat, ask:

```text
Inspect the hub Azure Firewall — show its egress allow-list and anything it denied for my subnet in the last hour.
```

The agent reads the policy over ARM (`az network firewall policy ...`) and queries the `AZFWNetworkRule` /
`AZFWApplicationRule` tables. **Talking point:** the agent operates its own locked-down egress and can
diagnose the very device that governs it — read-only, least-privilege, inside your VNet.

---

## Segment 2 — Scenario 2: Network Partition 🏆 (the headline)

**Break it** (run from the lab root):

```powershell
cd C:\Temp\GHDemo\sre-agent-main\labs\zava-aks-postgres
.\.github\skills\running-demo\scripts\break-network.ps1
```

**What it does:** applies a K8s `NetworkPolicy` (`database-tier-isolation`) that blocks `zava-api`
pod egress to the PostgreSQL subnet, **and** adds an NSG deny rule as a deliberate **red herring**.
The storefront flips to **`SERVICE DISRUPTION` / `database unreachable`**.

**What the agent does (autonomously):**
1. `postgres-unreachable` alert fires → agent opens an incident.
2. It sees **`ETIMEDOUT`** (a silent drop), *not* `ECONNREFUSED` — so the DB is up but traffic is
   being **blocked**.
3. It reasons **past the NSG red herring** (its knowledge base explains that PG Flex on a *delegated*
   subnet doesn't honor that NSG) and inspects in-cluster policy via native `kubectl`.
4. It finds and **removes the offending `NetworkPolicy`**, then verifies the storefront recovers.

**What to say:** "Notice it didn't stop at the first suspicious config (the NSG). It distinguished a
*timeout* from a *refusal*, correlated that with the delegated-subnet behavior, and found the real
in-cluster block — that's triage, not pattern-matching."

**Fallback** if the agent stalls (or to reset):

```powershell
.\.github\skills\running-demo\scripts\fix-network.ps1
```

---

## Segment 3 — Scenario 4: Bad Deploy / Rollback (optional)

**Break it:**

```powershell
.\.github\skills\running-demo\scripts\break-bad-deploy.ps1
```

**What it does:** `kubectl set env deployment/zava-api FAULT_INJECT=500` → a **new rollout revision** →
`GET /api/products` returns **500**, while `/livez` and `/api/health` stay green (pods look healthy).

**What the agent does:** the `Zava-http-5xx-errors` alert fires; the agent correlates the 5xx spike
with the **recent rollout** (`kubectl rollout history` / KubeEvents) and rolls back with
`kubectl rollout undo` to the last good revision.

**What to say:** "The platform looked healthy — probes green, pods Running. The signal that mattered
was the *deployment*. The agent tied the symptom to the change and rolled it back."

**Fallback:**

```powershell
.\.github\skills\running-demo\scripts\fix-bad-deploy.ps1
```

---

## Reset between rehearsals

Each scenario has a `fix-*.ps1` fallback that restores the healthy state. If you break, always confirm
the storefront is back to **`ALL SYSTEMS OPERATIONAL`** before the next run. The lab's DB scenarios
share one alert rule, so give a minute between back-to-back breaks (the lab's runbook closes the alert
on recovery so the next break dispatches fresh).

---

## Cleanup

```powershell
cd C:\Temp\GHDemo\sre-agent-main\labs\zava-aks-postgres
azd down --force --purge
```

This tears down the entire resource group (AKS, firewall, Postgres, agent). Do it when the demo is
done — the firewall and AKS cluster are the main cost drivers.

---

## Pairing the two tracks (optional, if you have both deployed)

- **App Service + SQL track** (this repo): shows **human-in-the-loop** (Review autonomy + governance
  hooks) on a slow-query incident. Best for a governance/change-control story.
- **AKS track** (this lab): shows **hands-off auto-repair** on network + deployment incidents. Best
  for a platform/network reliability story.

For a network-heavy customer, lead with the **AKS track**; keep the App Service track as an optional
"and here's how you gate it for production change control" follow-up.

## Reference

- Lab README (full architecture, all 4 scenarios, private-cluster/kubectl details):
  `labs/zava-aks-postgres/README.md`
- Lab author gotchas: `labs/zava-aks-postgres/AGENTS.md`
- App Service track run of show: [`docs/townhall-run-of-show.md`](townhall-run-of-show.md)
