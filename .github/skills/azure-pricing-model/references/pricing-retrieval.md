# Azure Pricing — Data Retrieval & Structuring

## Phase 2 — Gather Pricing Data

For each service in the manifest, retrieve pricing using a tiered strategy:

### Strategy A: Azure Pricing MCP (preferred — when available)

Call `pricing:pricing_get` per service/SKU. This returns structured retail pricing including PAYG, Reservation, Dev/Test, Spot, and Savings Plan rates.

**Per-service call pattern:**
```
pricing:pricing_get({
  service: "{service name}",       // e.g., "Virtual Machines", "Azure Cosmos DB"
  sku: "{ARM SKU name}",           // e.g., "Standard_D4s_v5" — from manifest or user
  region: "{target region}",       // e.g., "eastus"
  include-savings-plan: true        // includes nested savingsPlan array
})
```

**Response processing — extract and classify each price record:**

| Field | Maps to |
|---|---|
| `retailPrice` where `priceType: "Consumption"` and no Spot/Low Priority in `skuName` | PAYG unit price |
| `retailPrice` where `priceType: "Reservation"`, `reservationTerm: "1 Year"` | RI 1-year total (divide by 8760 for hourly, or by 12 for monthly) |
| `retailPrice` where `priceType: "Reservation"`, `reservationTerm: "3 Years"` | RI 3-year total (divide by 26280 for hourly, or by 36 for monthly) |
| `retailPrice` where `priceType: "DevTestConsumption"` | Dev/Test unit price |
| `skuName` containing "Spot" | Spot pricing |
| `skuName` containing "Low Priority" | Low Priority pricing |
| nested `savingsPlan` array (when `include-savings-plan: true`) | 1-year and 3-year Savings Plan rates |
| `productName` containing "Windows" vs not | OS licensing dimension |

**Batch strategy**: For solutions with multiple services, call `pricing:pricing_get` once per service+SKU combination. These calls are independent and can be parallelized.

**Monthly cost calculation**: `retailPrice (per hour) × 730 hours` for compute. For storage/transactions, use the `unitOfMeasure` field to determine the multiplication factor.

### Strategy B: Web Fallback (when Pricing MCP unavailable)

Use `fetch_webpage` against Azure pricing pages:
- Base URL pattern: `https://azure.microsoft.com/en-us/pricing/details/{service-slug}/`
- Parse the page for pricing tiers, SKU options, and metering dimensions.
- Flag `pricing_source: web_scrape` — data is less structured and may be incomplete.

### Supplementary Context (always, when available)

1. **Vault context** — `oil:get_customer_context({ customer })`:
   - Prior pricing discussions or approved budgets
   - Existing Azure spend baselines from customer notes
   - Discount/EA agreement context

2. **CRM context** (if opportunityId provided and not already gathered in Phase 1):
   - `msx-crm:crm_get_record` — opportunity value, solution play, estimated ACR
   - Cross-reference `estimatedvalue` against the pricing total as a sanity check

3. **Azure CLI** (if authenticated and user has existing deployments):
   - `az consumption usage list` for actual consumption baselines
   - Use only to validate estimates against real usage — not as the primary pricing source

## Phase 3 — Structure the Pricing Model

Organize pricing data into the normalized schema below. Every Azure service decomposes into these cost dimensions:

### Cost Dimension Taxonomy

| Dimension | Description | Examples |
|---|---|---|
| **Compute** | Processing capacity — vCPUs, memory, GPU hours | VM SKUs, AKS node pools, App Service plans |
| **Storage** | Data at rest — volume, tier, redundancy | Blob (Hot/Cool/Archive), Managed Disks, Cosmos DB RU storage |
| **Networking** | Data in motion — egress, peering, load balancing | Bandwidth egress, VNet peering, Application Gateway |
| **Transactions** | Per-operation charges — API calls, messages, executions | Cosmos DB RUs, Function executions, Event Grid events |
| **Licensing** | Software/IP costs bundled or separate | SQL Server license (AHUB vs included), Windows Server |
| **Support** | Support plan alignment | Standard, Professional Direct, Unified (EDE-linked) |
| **Discounts** | Pricing reductions | Reserved Instances (1yr/3yr), Savings Plans, EA/CSP rates, Dev/Test pricing |

### Per-Service Pricing Record

For each service, produce one record:

```
Service: {canonical name}
Region: {target region}
SKU/Tier: {specific SKU or tier}
Dimensions:
  - Compute: {unit} × {unit price} × {estimated quantity} = {monthly cost}
  - Storage: {unit} × {unit price} × {estimated quantity} = {monthly cost}
  - Networking: {unit} × {unit price} × {estimated quantity} = {monthly cost}
  - Transactions: {unit} × {unit price} × {estimated quantity} = {monthly cost}
  - Licensing: {model} = {monthly cost}
Subtotal (pay-as-you-go): {sum}
Subtotal (reserved 1yr): {sum with RI discount %}
Subtotal (reserved 3yr): {sum with RI discount %}
Notes: {scaling triggers, tier thresholds, free-tier limits}
```

## Phase 4 — Contextualize

1. **Consumption pattern analysis** — Classify each service as:
   - **Steady-state** (predictable load → RI candidate)
   - **Burst** (spiky demand → PAYG or autoscale)
   - **Growth** (ramp-up trajectory → Savings Plan candidate)

2. **Regional variance** — Flag pricing differences vs. primary regions. Note region pairs for DR cost modeling.

3. **Free tier / included allowances** — Document monthly free amounts per service.

4. **Scaling triggers** — Document at what thresholds costs step up.

5. **Unified/EDE alignment** — Note which services fall under support scope and which need additional coverage.

6. **Optimization recommendations** — For each service, one sentence on the best cost-optimization lever.
