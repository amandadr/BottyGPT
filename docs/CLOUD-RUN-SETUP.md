# Frontend on Cloud Run (one-time setup)

The DocsGPT **frontend** is deployed to **Cloud Run**; the **backend** (API, worker, Redis, Mongo, Qdrant) stays on the **VM**. This keeps the VM lean and lets the UI scale independently.

## 1. Enable Cloud Run API

```bash
gcloud services enable run.googleapis.com --project=manny-roy-consulting
```

## 2. Grant the GitHub Actions service account permission to deploy

Your `gh-actions-sa` (or whatever SA key you use in `GCP_SA_KEY`) needs to create/update Cloud Run services and pull images from Artifact Registry.

**Option A – Recommended roles**

```bash
# Replace with your SA email (e.g. gh-actions-sa@manny-roy-consulting.iam.gserviceaccount.com)
SA_EMAIL="github-actions-sa@manny-roy-consulting.iam.gserviceaccount.com"
PROJECT_ID="manny-roy-consulting"

# Deploy to Cloud Run and pull from Artifact Registry
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA_EMAIL" \
  --role="roles/run.admin"

```

**Step 2 – Only if the workflow fails with "Permission to act as service account"**

Grant the GitHub Actions SA permission to act as the **default Compute Engine** service account (Cloud Run uses it at runtime). Run this after Step 1 (so `SA_EMAIL` and `PROJECT_ID` are set):

```bash
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
RUNTIME_SA_EMAIL="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
gcloud iam service-accounts add-iam-policy-binding "$RUNTIME_SA_EMAIL" \
  --member="serviceAccount:$SA_EMAIL" \
  --role="roles/iam.serviceAccountUser" \
  --project=$PROJECT_ID
```

**Option B – Single role that includes both**

- **Cloud Run Admin** (`roles/run.admin`) is enough to deploy. The SA also needs **Artifact Registry Reader** (or **Writer**, which you already have for push) so Cloud Run can pull the image. If the image is in the same project, Cloud Run often can pull when the deployer has `run.admin`.

If deploy fails with “Permission denied” on the image, add:

```bash
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA_EMAIL" \
  --role="roles/artifactregistry.reader"
```

## 3. First deployment

The first time the workflow runs (or you run the deploy step), Cloud Run will **create** the service `docsgpt-frontend` in the region you use (e.g. `northamerica-northeast1`). No need to create the service manually.

After a successful run you’ll get a URL like:

`https://docsgpt-frontend-XXXXXXXX-uc.a.run.app`

## 4. Custom domain (optional)

To serve the frontend at e.g. **[https://assistant.mannyroy.com](https://assistant.mannyroy.com)**:

1. In **Cloud Run** → select the service **docsgpt-frontend** → **Manage custom domains**.
2. Add `assistant.mannyroy.com` and follow the prompts (map to the Cloud Run service, then add the DNS records shown).
3. Ensure **VITE_BASE_URL** (and any redirect/cookie config) uses `https://assistant.mannyroy.com` so the app knows its public URL. Set the secret **VITE_BASE_URL** in GitHub to match.

## 5. Architecture summary


| Component                                     | Where it runs | URL / access                                                                                       |
| --------------------------------------------- | ------------- | -------------------------------------------------------------------------------------------------- |
| Frontend                                      | Cloud Run     | `https://docsgpt-frontend-xxx.run.app` or custom domain                                            |
| Backend API + worker + Redis + Mongo + Qdrant | VM (Compose)  | API at VM IP:7091 or e.g. [https://assistant-api.mannyroy.com](https://assistant-api.mannyroy.com) |


The frontend is built with **VITE_API_HOST** pointing at your backend (e.g. `https://assistant-api.mannyroy.com`). CORS is allowed on the backend, so the browser can call the API from the Cloud Run origin.