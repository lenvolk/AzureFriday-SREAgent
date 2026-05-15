---
name: azure-pricing-model
description: 'Azure pricing model assembler: retrieves Azure service pricing data, structures cost components into a logical pricing model, and outputs an Excel-ready breakdown covering compute, storage, networking, licensing, and support tiers. Captures wider context — consumption patterns, reserved vs pay-as-you-go tradeoffs, regional variance, and Unified/EDE coverage alignment. Chains with value-realization-pack and proof-plan-orchestration for cost-justified delivery planning. Triggers: Azure pricing, cost model, pricing spreadsheet, Azure cost breakdown, service pricing, pricing document, cost estimate, Azure estimate, TCO, total cost of ownership, pricing export, cost comparison, Azure spend, consumption cost, reserved instance pricing, Azure pricing Excel.'
argument-hint: 'Provide a list of Azure services, a solution architecture description, or an opportunityId to derive services from the proof plan'
---

## Purpose

Retrieves and structures Azure service pricing into a normalized, Excel-exportable cost model. Captures compute, storage, networking, licensing, support, and discount dimensions so account teams can present transparent pricing to customers.

For pricing data retrieval strategies (Pricing MCP vs web fallback), response field mapping, cost dimension taxonomy, and contextualization rules, read [references/pricing-retrieval.md](references/pricing-retrieval.md).

For Excel sheet structure, formatting specs, column definitions, and spreadsheet generation workflow, read [references/excel-output.md](references/excel-output.md).

## When to Use

- Customer asks "how much will this cost?" for an Azure-based solution
- Specialist or SE needs a cost model for a proof plan or milestone
- Comparing reserved instance vs pay-as-you-go for a customer proposal
- Building a TCO comparison (on-premises vs Azure migration)

## Freedom Level

**Medium** — Service identification and pricing structure are rule-based; cost optimization recommendations require judgment.

## Runtime Contract

| Tool | Server | Purpose | Required |
|---|---|---|---|
| `pricing_get` | `pricing` (Azure MCP) | Structured retail pricing — PAYG, RI, Spot, Dev/Test, Savings Plan | **Primary** |
| `fetch_webpage` | built-in | Web fallback for Azure pricing pages | **Fallback** |
| `crm_get_record` | `msx-crm` | Opportunity details, solution play, estimated ACR | Optional |
| `get_milestones` | `msx-crm` | Milestone/task data for SKU and quantity extraction | Optional |
| `get_customer_context` | `oil` | Vault context — prior budgets, architecture decisions | Optional |

## Medium Availability Probe

| Medium | Probe | If unavailable |
|---|---|---|
| **Azure Pricing MCP** | `pricing:pricing_get` with test SKU | Fall back to `fetch_webpage`; flag `pricing_source: web_scrape` |
| **CRM** | `msx-crm:crm_auth_status` | Skip opportunity sizing; require explicit service list |
| **Vault** | `oil:get_vault_context()` | Skip vault-prefetch; operate CRM-only or explicit list |

## Flow

### Phase 1 — Scope the Services

Determine which Azure services need pricing:

| Entry point | How | When |
|---|---|---|
| **Explicit list** | User provides service names directly | User says "price out AKS, Cosmos DB" |
| **Architecture description** | Parse solution → extract service names | User describes a solution |
| **From opportunity** | `msx-crm:crm_get_record` + `msx-crm:get_milestones` → extract service/SKU signals | User provides opportunityId |
| **From proof plan** | Chain from `proof-plan-orchestration` output | Post-proof cost modeling |

For each service, normalize to the canonical Azure name (e.g., "Kubernetes" → "Azure Kubernetes Service").

#### Opportunity-Grounded Sizing (when opportunityId provided)

1. `msx-crm:crm_get_record` — read `estimatedvalue`, solution play, description.
2. `msx-crm:get_milestones({ opportunityId, includeTasks: true })` — parse `msp_monthlyuse`, milestone comments, task descriptions for SKU mentions and sizing.
3. `oil:get_customer_context({ customer })` — pull prior architecture decisions, approved SKUs, spend baselines.
4. Build a **service manifest**: service name, candidate SKU, estimated quantity, source (milestone | task | vault | assumption).

### Phases 2–6

Read [references/pricing-retrieval.md](references/pricing-retrieval.md) for Phases 2–4 (data retrieval, structuring, contextualization) and [references/excel-output.md](references/excel-output.md) for Phases 5–6 (Excel output and generation).

## Output Schema

```markdown
# Azure Pricing Model — {solution/customer name}

**Date**: {date}
**Region**: {target region}
**Currency**: USD (or as specified)
**Contract**: {EA / CSP / PAYG}
```

| Service | SKU | Monthly PAYG | Monthly RI 1yr | Monthly RI 3yr |
|---------|-----|-------------|----------------|----------------|
| {service} | {sku} | ${amount} | ${amount} | ${amount} |
| **Total** | | **${sum}** | **${sum}** | **${sum}** |

## Key Assumptions
- {assumption}: {value} (sensitivity: {low/med/high})

## Optimization Recommendations
1. {service}: {one-line recommendation}

## Risks & Caveats
- Pricing retrieved {date} — verify before customer-facing use
- Estimates exclude tax, EA-specific discounts, and negotiated rates
- Egress costs are estimates — actual depends on architecture patterns

## Spreadsheet
Generated: `{filename}.xlsx` with sheets: Cost Summary, Detailed Breakdown, Assumptions, {Comparison if TCO}.
```

- `services_priced`: count of services in the model
- `total_monthly_payg`: headline monthly figure
- `total_annual_ri_3yr`: best-case annual figure
- `optimization_levers`: list of per-service recommendations
- `assumptions_flagged`: count of high-sensitivity assumptions
- `next_action`: "Review assumptions with the customer. Chain with `proof-plan-orchestration` to attach cost model to proof milestones, or `value-realization-pack` to track actual vs estimated spend post-deployment."
- `connect_hook_hint`: Impact Area: Customer Value — "Structured Azure pricing model for {solution} covering {n} services — {savings_pct}% potential savings via reserved commitments identified"

## Chaining

| Chain | Direction | When |
|---|---|---|
| `proof-plan-orchestration` → **this skill** | Inbound | Proof plan scoped → cost model needed for budget approval |
| **this skill** → `processing-spreadsheets` | Outbound | Always — produces the .xlsx artifact |
| **this skill** → `value-realization-pack` | Outbound | Post-deployment — compare estimated vs actual spend |
| `account-landscape-awareness` → **this skill** | Inbound | Account review surfaces cost optimization opportunities |
| `customer-outcome-scoping` → **this skill** | Inbound | KPI definition includes cost targets → need pricing baseline |

## Gotchas

- **Pricing MCP vs web scrape**: When the Azure Pricing MCP is available, always prefer it — the data is structured, current, and includes all price types in one call. Web scrape is a fallback only.
- **SKU name precision**: `pricing:pricing_get` requires exact ARM SKU names (e.g., `Standard_D4s_v5`, not `D4s v5`). Normalize before calling.
- **Multi-record responses**: A single `pricing_get` call may return multiple records for the same SKU — different OS (Windows/Linux), different price types (Consumption/Reservation/DevTest), Spot, and Low Priority variants. Filter and classify using `productName`, `priceType`, `skuName`, and `reservationTerm` fields.
- **RI pricing units**: Reservation prices are returned as total cost for the term (1-year or 3-year), not per-hour. Divide by months in term for monthly effective cost.
- **Savings Plan availability**: The `include-savings-plan` flag uses a preview API version. Savings Plan data is primarily available for Linux VMs — if the array is empty, note "Savings Plan not available for this SKU."
- Always include a "last retrieved" date on pricing data — Azure pricing updates monthly.
- Do not present pricing as guaranteed — always caveat with contract type and negotiation disclaimer.
- Free tier limits vary by subscription type (Free, PAYG, EA) — confirm subscription context.
- Some services have no RI option — skip RI columns for those (e.g., Azure Functions consumption plan).
- When opportunity-grounded sizing is used, flag which estimates came from milestone/task evidence vs assumptions — this transparency builds customer trust.
