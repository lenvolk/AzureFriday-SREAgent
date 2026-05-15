# Azure Pricing — Excel Output Specification

## Phase 5 — Excel-Ready Output Structure

### Sheet 1: Cost Summary

| Column | Content |
|---|---|
| A: Service | Canonical Azure service name |
| B: SKU/Tier | Selected pricing tier |
| C: Region | Deployment region |
| D: Monthly PAYG | Pay-as-you-go monthly estimate |
| E: Monthly RI 1yr | 1-year reserved estimate |
| F: Monthly RI 3yr | 3-year reserved estimate |
| G: Annual PAYG | D × 12 |
| H: Annual RI 1yr | E × 12 |
| I: Annual RI 3yr | F × 12 |
| J: Optimization Note | One-line recommendation |

**Bottom row**: SUM formulas for columns D–I.

### Sheet 2: Detailed Breakdown

| Column | Content |
|---|---|
| A: Service | Canonical name |
| B: Dimension | Compute / Storage / Networking / Transactions / Licensing |
| C: Unit | Pricing unit (vCPU/hr, GB/mo, 10K transactions) |
| D: Unit Price | Per-unit price |
| E: Est. Quantity | Estimated monthly usage |
| F: Monthly Cost | D × E |
| G: Notes | Tier thresholds, free allowances, scaling triggers |

### Sheet 3: Assumptions & Context

| Column | Content |
|---|---|
| A: Parameter | Assumption label |
| B: Value | Assumed value |
| C: Source | Where the assumption comes from |
| D: Sensitivity | Low / Medium / High — impact if assumption changes |

Standard assumptions to include:
- Target region
- Utilization rate (for compute right-sizing)
- Data growth rate (for storage projections)
- Egress volume estimate
- Support tier
- License model (AHUB eligibility)
- Contract type (EA / CSP / PAYG)
- Currency

### Sheet 4: Comparison (optional, for migration/TCO scenarios)

| Column | Content |
|---|---|
| A: Component | Workload component |
| B: Current (On-Prem) | Current annual cost |
| C: Azure PAYG | Azure annual estimate |
| D: Azure RI 3yr | Azure reserved estimate |
| E: Savings | B − D |
| F: Savings % | E / B |

## Phase 6 — Produce the Spreadsheet

Invoke the `processing-spreadsheets` skill to generate the actual `.xlsx` file:

1. Write a Node.js script using `exceljs` following the sheet structure above.
2. Apply formatting:
   - Header row: bold, #003366 background, white text, frozen row.
   - Currency columns: `$#,##0.00` number format.
   - Percentage columns: `0.0%` format.
   - Conditional formatting: highlight cells where RI savings > 30% in green.
   - Auto-filter on all header rows.
3. Save to `.copilot/docs/` (see `shared-patterns.instructions.md` § Artifact Output Directory), or the user's specified path.

## Decision Logic

### Pricing Tier Selection Heuristic

When the user hasn't specified a tier, select based on context:

| Signal | Default tier |
|---|---|
| POC / proof-of-concept | Dev/Test or lowest production tier |
| Production workload, <100 users | Standard / General Purpose |
| Production workload, >100 users | Premium / Business Critical |
| ML / AI workload | GPU-optimized SKUs |
| No context | General Purpose, mid-range — flag as assumption |

### Reserved Instance Recommendation

| Consumption pattern | Recommendation |
|---|---|
| Steady-state, >8hr/day utilization | 1-year RI minimum, evaluate 3-year |
| Burst, <4hr/day | PAYG — no reservation |
| Growth ramp | Savings Plan (flexible across SKUs) |
| Unknown | Show both; flag for customer discussion |
