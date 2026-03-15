# Structured production monitoring with Cloud Logging

Send VM and Docker container logs to **Cloud Logging** for centralized querying, log-based metrics, and optional alerting. The backend and worker already emit **structured JSON** logs (with `severity`, `message`, `service`, `request_id`) so Cloud Logging can index and filter by severity and service.

## 1. Prerequisites

- GCP VM (e.g. `docsgpt-prod`) running the DocsGPT stack with Docker.
- VM’s default service account (or the one used by the agent) must have **Logs Writer** in the project:  
  `roles/logging.logWriter` (or a custom role with `logging.logEntries.create`).

## 2. Install the Ops Agent on the VM

On the VM (or from your machine with `gcloud compute ssh`):

```bash
# One-line install (Linux); see https://cloud.google.com/logging/docs/agent/ops-agent/installation
curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
sudo bash add-google-cloud-ops-agent-repo.sh --also-install
```

Or install manually: add the Ops Agent repo, then `apt install google-cloud-ops-agent` (Debian/Ubuntu). For other distros, see [Ops Agent installation](https://cloud.google.com/logging/docs/agent/ops-agent/installation).

Ensure the agent runs after boot:

```bash
sudo systemctl enable google-cloud-ops-agent
sudo systemctl status google-cloud-ops-agent
```

## 3. Grant the VM access to write logs

From your Mac or Cloud Shell:

```bash
PROJECT_ID="manny-roy-consulting"
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --role="roles/logging.logWriter"
```

(If the VM uses a custom service account, use that account instead of the default compute SA.)

## 4. Configure the Ops Agent to collect Docker logs

Copy the repo’s Ops Agent override config to the VM and restart the agent.

**Option A: Copy from repo (after deploy)**

From your machine (replace with your VM host/user as needed):

```bash
VM_HOST="your-vm-ip-or-hostname"
VM_USER="your-ssh-user"

scp deployment/ops-agent/config.yaml ${VM_USER}@${VM_HOST}:/tmp/ops-agent-config.yaml
ssh ${VM_USER}@${VM_HOST} "sudo mkdir -p /etc/google-cloud-ops-agent && sudo cp /tmp/ops-agent-config.yaml /etc/google-cloud-ops-agent/config.yaml && sudo systemctl restart google-cloud-ops-agent"
```

**Option B: Paste config on the VM**

SSH to the VM, then:

```bash
sudo mkdir -p /etc/google-cloud-ops-agent
sudo nano /etc/google-cloud-ops-agent/config.yaml
```

Paste the contents of `deployment/ops-agent/config.yaml` (see repo). Save and restart:

```bash
sudo systemctl restart google-cloud-ops-agent
```

The config adds a **files** receiver for `/var/lib/docker/containers/*/*-json.log` and a **parse_json** processor so each line (Docker’s JSON wrapper) is parsed. Logs are sent to Cloud Logging with resource type `gce_instance`; the agent adds metadata (e.g. log file path, which includes the container ID). The backend and worker already emit JSON with a `severity` field so that when the payload is parsed or queried, severity is available.

## 5. View logs in Cloud Logging

1. In GCP Console go to **Logging → Logs Explorer**.
2. Use the project and (optionally) resource type **GCE VM instance**.
3. Filter by:
   - **Resource**: `gce_instance` and your instance name.
   - **Log name** or **Payload**: e.g. `jsonPayload.log` or `textPayload` to search container output.
   - For structured app logs (after parsing), you can query on `jsonPayload.service`, `jsonPayload.severity`, `jsonPayload.message`.

Example query (if your app JSON is in `jsonPayload.log` as a string, search inside it):

```text
resource.type="gce_instance"
resource.labels.instance_id="YOUR_INSTANCE_ID"
jsonPayload.log=~"ERROR"
```

Or by log file path (container):

```text
resource.type="gce_instance"
labels."agent.googleapis.com/log_file_path"=~"docker/containers"
```

## 6. Log-based metrics and alerting (optional)

Use **Logs Explorer** to build a filter for “errors” (e.g. `jsonPayload.log=~"\"severity\":\"ERROR\""` or by `severity` if you parse the inner JSON). Then create a **log-based metric**:

1. **Logging → Logs-based metrics → Create metric**.
2. **Counter** type; filter = your error filter; name e.g. `docsgpt_error_count`.
3. Create an **alerting policy** that triggers when `docsgpt_error_count` exceeds a threshold (e.g. > 0 in 5 minutes).

You can also add **uptime checks** in Cloud Monitoring for `https://assistant-api.mannyroy.com/health` and alert on failure.

## 7. Summary

| Step | Action |
|------|--------|
| 1 | VM has Ops Agent installed and running. |
| 2 | VM service account has `roles/logging.logWriter`. |
| 3 | `/etc/google-cloud-ops-agent/config.yaml` includes the Docker files receiver and parse_json pipeline (from `deployment/ops-agent/config.yaml`). |
| 4 | Restart Ops Agent after config changes. |
| 5 | View and query logs in Logs Explorer; optionally add log-based metrics and alerts. |

Backend and worker logs are already **structured** (JSON with `severity`, `message`, `service`, `request_id`). Keeping Docker’s json-file driver and adding the Ops Agent gives you centralized, queryable production monitoring without changing application code beyond the existing formatter.
