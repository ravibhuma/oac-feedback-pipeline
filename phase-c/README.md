# Phase C — Tuning workbook

Phase C has no downloadable artifacts — the work happens in the OAC UI. See the [index.html walkthrough](https://ravibhuma.github.io/oac-feedback-pipeline/#c1) for the click-by-click.

## Three steps

1. **C-1 · Database Connection** — OAC Console → Connections → Create → Oracle Autonomous Data Warehouse. Upload the Autonomous wallet. User: `OACFB`. Test and save.
2. **C-2 · Dataset** — Data → Create → Dataset → select the `OAC_FEEDBACK_WITH_LSQL` view.
3. **C-3 · Workbook** — Recommended starter visualizations: feedback sentiment trend, top negative LSQL patterns, feedback by data model, response-time vs. satisfaction.

## The tuning loop

From a thumbs-down row in the workbook, note the `event_time` and `parent_ecid`, look for that `parent_ecid` in the `ecid` column, sort by `event_time` ascending — the next row contains the LSQL the AI Assistant generated for that utterance. That's the evidence you use to tune the synonym (Assistant) or supplemental instruction (Agent), then re-publish.
