# Screenshots for the README

Portal screenshots for the README live here. **Five are already captured** from the walkthrough;
two more are optional or added after the live run.

| Filename | Status | What it shows | Used in |
|----------|--------|---------------|---------|
| `sre-agent-home.png` | ✅ captured | SRE Agent home for `zava-sreagent-1` with the green **Logs · Incidents · Azure resources** bar. | Part 2, Step 1 |
| `sql-mcp-connector.png` | ✅ captured | The `zava-sql` MCP connector setup (the Stdio vs Streamable-HTTP choice). | Part 2, Step 2 |
| `response-plan.png` | ✅ captured | `zava-response-plan` with *Title contains* the DTU alert, Status **On**, Autonomy **Review**. | Part 2, Step 3 |
| `incidents-empty.png` | ✅ captured | The **Incidents** list showing **No incidents found**. | Part 3, Scenario 1 |
| `incident-active.png` | ✅ captured | The **Incidents** list with the DTU alert **Acknowledged** and agent **In progress**. | Part 3, Scenario 1 |
| `incident-investigation.png` | ✅ captured | The agent's **Investigation Results** table + root-cause analysis inside the incident thread. | Part 3, Scenario 1 |
| `incident-approval.png` | ⬜ fresh-run only | The incident thread proposing `CREATE INDEX IX_Products_Category` with an **Approve** button (only appears when the index is missing). | Part 3, Scenario 1 |
| `create-agent-basics.png` | ⬜ optional | The **Create Agent → Basics** form filled in. | Part 2, Step 1 |

## Tips

- **PNG** is preferred. Keep each image under ~1 MB if you can.
- **Never include secrets.** Crop or blur any SQL password, connection string, token, or PAT before
  saving a screenshot here.
- If you rename a file, update the matching link in `README.md`.
