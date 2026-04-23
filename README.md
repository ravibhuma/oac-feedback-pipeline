# OAC AI Feedback Tuning Pipeline

**Set up a real-user feedback tuning pipeline for Oracle Analytics Cloud (OAC) AI Assistants and AI Agents in under 15 minutes — then use it to tune them and close the pilot-to-production gap with evidence behind every release.**

📖 **Full walkthrough:** [ravibhuma.github.io/oac-feedback-pipeline](https://ravibhuma.github.io/oac-feedback-pipeline/)
🛠️ **Manual method:** [OAC AI Workshop · AI Feedback Guide](https://oac-ai.github.io/oac-ai-workshops/ai-feedback-guide.html)

---

## Why this exists

Without a feedback loop, AI pilots stall. Authors can't see which answers failed or why. Tuning becomes guesswork. Users stop trusting the Assistant and Agent. Analysts remain the bottleneck.

This pipeline captures every 👍 / 👎 on your OAC AI Assistants & Agents — together with the prompt and the generated Logical SQL — into an OAC workbook. Authors review, tune the right layer (synonyms, instructions, knowledge documents), and re-publish the **same day**.

## The 3 phases

| | Phase | What it does | Where | Time |
|---|---|---|---|---|
| **A** | **Capture** | Provision the OCI capture layer (bucket, log group, Service Connector, dynamic group, policies) via Terraform + Resource Manager. | OCI Console | ~5 min |
| **B** | **Land** | One-shot Cloud Shell installer creates the OACFB DB user, the SODA collection, the ingestion procedure, views, and the scheduler. | Cloud Shell + ADB | ~5 min |
| **C** | **Tune** | Connect OAC to ADB, create the dataset from the `OAC_FEEDBACK_WITH_LSQL` view, and build the tuning workbook. | OAC | ~5 min |

## Quick start

### Phase A — Capture layer (Terraform)

Download the bundle from the latest release and upload it as a new stack in OCI Resource Manager:

```
https://github.com/ravibhuma/oac-feedback-pipeline/releases/latest/download/oac-feedback-phase1.zip
```

See [phase-a/README.md](phase-a/README.md) for details.

### Phase B — Database pipeline (Cloud Shell)

Download and run the installer in Cloud Shell:

```bash
curl -L -o install_oac_feedback_pipeline.sh \
  https://github.com/ravibhuma/oac-feedback-pipeline/releases/latest/download/install_oac_feedback_pipeline.sh
curl -L -o oac_feedback_pipeline_admin_setup.sql \
  https://github.com/ravibhuma/oac-feedback-pipeline/releases/latest/download/oac_feedback_pipeline_admin_setup.sql
curl -L -o oac_feedback_pipeline_install.sql \
  https://github.com/ravibhuma/oac-feedback-pipeline/releases/latest/download/oac_feedback_pipeline_install.sql
chmod +x install_oac_feedback_pipeline.sh
./install_oac_feedback_pipeline.sh
```

The installer prompts for: ADB OCID · ADMIN password · OACFB password · `adb_location_uri` (output from Phase A).

See [phase-b/README.md](phase-b/README.md) for details.

### Phase C — Tuning workbook (OAC)

1. OAC Console → Connections → Create → Oracle Autonomous Data Warehouse (upload wallet, user = `OACFB`).
2. Data → Create → Dataset → select the `OAC_FEEDBACK_WITH_LSQL` view.
3. Create Workbook. Recommended starter visualizations: feedback sentiment trend, top negative LSQL patterns, feedback by data model, response time vs. satisfaction.

## Repository layout

```
├── index.html               ← The full walkthrough (served via GitHub Pages)
├── phase-a/                 ← Terraform source (main.tf, outputs.tf, variables.tf, schema.yaml, README.md, terraform.tfvars.example)
├── phase-b/                 ← Install script + 2 SQL files
├── phase-c/                 ← Notes on OAC workbook (no artifacts — work happens in the UI)
└── release/                 ← Assets bundled into each GitHub Release
```

## Releases

GitHub Releases ship the four ready-to-use artifacts:

- `oac-feedback-phase1.zip` — Terraform bundle for Resource Manager
- `install_oac_feedback_pipeline.sh` — Phase B one-shot installer
- `oac_feedback_pipeline_admin_setup.sql` — creates the OACFB DB user
- `oac_feedback_pipeline_install.sql` — creates the ingestion procedure, views, and scheduler

Each release bumps these artifacts together so the `/releases/latest/download/` URLs always point at compatible versions.

## License

MIT. See [LICENSE](LICENSE).
