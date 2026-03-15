# App secrets via GCP Secret Manager

Instead of keeping a long-lived `.env` file on the VM with API keys and other secrets, you can store them in **GCP Secret Manager** and have the VM (or the deploy workflow) fetch them at deploy time. The VM's service account needs read access; no secrets are stored in GitHub.

## 1. Enable Secret Manager and create the secret

From your Mac or Cloud Shell:

```bash
# Enable the API
gcloud services enable secretmanager.googleapis.com --project=manny-roy-consulting

# Create a secret with the contents of your current .env (run from repo root; remove IMAGE_TAG if you set it at deploy time)
# Option A: from a file (ensure no trailing newline with secrets in it that you don't want)
gcloud secrets create docsgpt-env \
  --project=manny-roy-consulting \
  --replication-policy=automatic \
  --data-file=- < .env

# Option B: from stdin (paste or pipe)
# gcloud secrets create docsgpt-env --project=manny-roy-consulting --replication-policy=automatic --data-file=-
```

If the secret already exists and you want to add a new version (e.g. after rotating keys):

```bash
gcloud secrets versions add docsgpt-env --project=manny-roy-consulting --data-file=- < .env
```

**Important:** The secret value should be the **full .env content** (key=value lines). Do **not** include `IMAGE_TAG` in the secret; the deploy workflow sets it. Include everything the app needs: `OPENAI_API_KEY`, `API_KEY`, `JWT_SECRET_KEY`, `VECTOR_STORE`, `QDRANT_URL`, etc.

## 2. Grant the VM's service account access to the secret

The VM runs as the **default Compute Engine service account**. Grant it permission to read the secret:

```bash
PROJECT_ID="manny-roy-consulting"
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')

# Grant read access to the secret
gcloud secrets add-iam-policy-binding docsgpt-env \
  --project=$PROJECT_ID \
  --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

## 3. Test before deploying

Verify Secret Manager and VM access **before** setting `USE_SECRET_MANAGER=true` in GitHub.

### 3.1 From your Mac (or Cloud Shell)

Confirms the secret exists and your user can read it:

```bash
# Should print the secret payload (key=value lines). Inspect only in a safe place.
gcloud secrets versions access latest --secret=docsgpt-env --project=manny-roy-consulting

# Optional: check that expected keys exist (prints only key names, not values)
gcloud secrets versions access latest --secret=docsgpt-env --project=manny-roy-consulting \
  | sed 's/=.*/=***/' | grep -E '^(OPENAI_API_KEY|API_KEY|JWT_SECRET_KEY|VECTOR_STORE|QDRANT)'
```

### 3.2 From the VM (what the deploy will use)

This uses the **VM's service account**. If it works here, the deploy workflow will work.

1. SSH to the VM (same user/host you use for deploy, e.g. from your repo):

   ```bash
   ssh -i /path/to/your/deploy_key $VM_USER@$VM_IP
   ```

2. Run the same fetch the workflow runs (use a **temp file** so you don't overwrite a real `.env` yet):

   ```bash
   cd /opt/docsgpt
   gcloud secrets versions access latest --secret=docsgpt-env --project=manny-roy-consulting > /tmp/docsgpt-env-test
   chmod 600 /tmp/docsgpt-env-test
   ```

3. Check that the file has content and expected variable names (no secrets printed):

   ```bash
   wc -l /tmp/docsgpt-env-test
   grep -E '^[A-Za-z_][A-Za-z0-9_]*=' /tmp/docsgpt-env-test | sed 's/=.*/=***/' | head -20
   ```

4. If that looks good, you can replace the real `.env` with a backup and test full startup:

   ```bash
   cp .env .env.backup
   cp /tmp/docsgpt-env-test .env
   sudo docker compose -f docker-compose.gcp.yaml --env-file .env up -d
   # Check logs; if OK, leave USE_SECRET_MANAGER unset until you're ready, then set it and use .env.backup only for recovery
   ```

If step 2 fails with permission denied, re-check the IAM binding in section 2 (correct project number and `secretAccessor` on `docsgpt-env`). If the VM doesn't have `gcloud`, install the [Google Cloud SDK](https://cloud.google.com/sdk/docs/install); the VM must use the default compute service account (no `gcloud auth login` as a user).

## 4. Use Secret Manager in deploys

### Option A: GitHub Actions (recommended)

1. In **GitHub → Settings → Secrets and variables → Actions**, add a secret:
   - **USE_SECRET_MANAGER** = `true`

2. On each deploy, the workflow will SSH to the VM and run (before updating `IMAGE_TAG` and starting containers):
   - `gcloud secrets versions access latest --secret=docsgpt-env --project=... > .env`
   - So `.env` is refreshed from Secret Manager on every deploy; then `IMAGE_TAG` is set and `docker compose up -d` runs.

3. Ensure the VM has **gcloud** installed and that it uses the default service account (no `gcloud auth login` with a user account, or the metadata token won't be for the VM SA). Most GCP-provided images include gcloud; if not, install the [Google Cloud SDK](https://cloud.google.com/sdk/docs/install).
4. The GitHub Actions SSH user must have **write access** to `DEPLOY_PATH` (e.g. `/opt/docsgpt`) so the workflow can write the fetched `.env` there.

### Option B: Manual fetch on the VM

If you don't set `USE_SECRET_MANAGER` in GitHub, keep using a static `.env` on the VM. To switch to Secret Manager manually:

1. Copy the fetch script to the VM (or run the gcloud command below).
2. Run once (or from cron before compose):

```bash
cd /opt/docsgpt
PROJECT_ID=manny-roy-consulting SECRET_NAME=docsgpt-env ./fetch-secrets-to-env.sh
# Then run compose as usual
sudo docker compose -f docker-compose.gcp.yaml --env-file .env up -d
```

Or inline (no script):

```bash
cd /opt/docsgpt
gcloud secrets versions access latest --secret=docsgpt-env --project=manny-roy-consulting > .env
chmod 600 .env
```

## 5. Security notes

- **Rotate keys:** Update the secret in Secret Manager (add a new version); the next deploy or manual fetch will use it. No need to SSH and edit `.env`.
- **Audit:** Secret Manager logs access. Use Cloud Audit Logs to see who/what read the secret.
- **Least privilege:** Only the VM's SA (and any admins) need `secretAccessor` on this secret; don't grant broader project roles than needed.
- **First-time setup:** Until you add the secret and IAM, leave `USE_SECRET_MANAGER` unset so the workflow continues to use the existing `.env` on the VM.

## 6. Multiple secrets (optional)

If you prefer one secret per key (e.g. `OPENAI_API_KEY`, `JWT_SECRET_KEY`), you can create multiple secrets and have a script on the VM assemble `.env` from them. For most setups, a single secret containing the whole `.env` is simpler and is what the workflow expects when `USE_SECRET_MANAGER=true`.
