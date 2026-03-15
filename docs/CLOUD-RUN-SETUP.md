# Frontend on Cloud Run (optional)

**Default deployment:** The repo deploys **frontend and backend together on the VM** (see [GH-ACTIONS-DEPLOY.md](GH-ACTIONS-DEPLOY.md) and [DEPLOYMENT-CHECKLIST.md](DEPLOYMENT-CHECKLIST.md)). This page is for **optional** one-time setup if you choose to run the frontend on **Cloud Run** instead (VM would run backend + worker + infra only).

**Tearing down Cloud Run (moving frontend to VM):** To remove the Cloud Run frontend and IAP hosted UI, run (replace region/project as needed):  
`gcloud run services delete docsgpt-frontend --region=northamerica-northeast1 --project=manny-roy-consulting --quiet`  
`gcloud run services delete iap-gcip-hosted-ui-docsgpt-frontend --region=northamerica-northeast1 --project=manny-roy-consulting --quiet`  
Then update the VM with the new `docker-compose.gcp.yaml` (includes frontend), set `IMAGE_TAG`, and run `docker compose up -d`.

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

## 6. "You don't have access" when opening the frontend URL

**Why it happens:** Opening the Cloud Run URL in a browser sends an **unauthenticated** request. Cloud Run does not see your Google account; it only checks IAM. Granting `user:you@domain.com` as invoker does **not** make the browser request "signed in" — that only applies when the request includes an identity token (e.g. via Identity-Aware Proxy or `curl` with a token).

**Fix for public access:** Allow unauthenticated invoker so anyone can open the URL:

```bash
REGION="northamerica-northeast1"   # or your region
PROJECT_ID="manny-roy-consulting"

gcloud run services add-iam-policy-binding docsgpt-frontend \
  --region=$REGION \
  --project=$PROJECT_ID \
  --member="allUsers" \
  --role="roles/run.invoker"
```

If you get an error like *"users do not belong to a permitted customer"*, an **organization policy** is blocking public principals. Check constraints (e.g. `iam.allowedPolicyMemberDomains` may show ALLOW; another constraint may still block `allUsers`). To list policies that might apply:

```bash
gcloud resource-manager org-policies list --project=$PROJECT_ID
```

**If you use IAP (Identity-Aware Proxy):** IAP must be allowed to invoke the service. Grant **Cloud Run Invoker** to the IAP service agent (if you enabled IAP from the console this may have been done automatically; if you still see "You don't have access", add it manually):

```bash
REGION="northamerica-northeast1"
PROJECT_ID="manny-roy-consulting"
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")

gcloud run services add-iam-policy-binding docsgpt-frontend \
  --region=$REGION \
  --project=$PROJECT_ID \
  --member="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-iap.iam.gserviceaccount.com" \
  --role="roles/run.invoker"
```

Also ensure your user (e.g. `manny@mannyroy.com`) has **IAP access** to the app: in the console go to **Security → Identity-Aware Proxy**, select the Cloud Run app, and add the user under **Access**. Use the **same** frontend URL (run.app or your domain); IAP applies to all ingress when enabled on the service.

### IAP hosted sign-in page shows "Service unavailable" (black screen)

When IAP redirects you to the hosted login URL (`iap-gcip-hosted-ui-...run.app`) and you see **"Service unavailable"**, the hosted sign-in page cannot load its configuration. That config lives in a **Cloud Storage bucket** named `gcip-iap-bucket-<SERVICE>-<PROJECT_NUMBER>`.

**You cannot create that bucket yourself.** The `gcip-iap-bucket-*` name is restricted; only Google can create it when you complete the official IAP hosted sign-in setup.

**Fix – use the Console so Google provisions the bucket:**

1. **Security → Identity-Aware Proxy**  
   [Open IAP](https://console.cloud.google.com/security/iap?project=manny-roy-consulting)

2. Under **Applications**, find **docsgpt-frontend** (or the Cloud Run service that has IAP enabled). Select it.

3. In the side panel, look for **Create a sign-in page** or **Customize sign-in page** / **Login URL** (or similar). Use the option that says IAP will create the sign-in page for you. That flow provisions the `gcip-iap-bucket-*` bucket and a default `config.json`.

4. **OAuth consent screen**  
   If you have not already, configure **APIs & Services → OAuth consent screen** (Internal or External). IAP needs this for the sign-in flow.

**If the bucket already exists** (e.g. from an earlier setup) but the page still fails, ensure the bucket contains `config.json`. You can upload or replace it via the Console “Customize” flow, or with `gsutil cp` if you have access to the bucket. The format is described in the [IAP hosted UI config reference](https://cloud.google.com/iap/docs/reference/ui-config); see `docs/iap-hosted-ui-config.example.json` for a minimal example keyed by your API key.

**Still “service unavailable” with Login URL and Customize page set?**

1. **Add at least one user** – IAP will block everyone if **Permissions** shows **0 users**. In the IAP Applications panel, with **docsgpt-frontend** selected, click **+ Add principal**, add your Google account (e.g. `manny@mannyroy.com`), and assign role **Cloud IAP → IAP-secured Web App User**. Save. This is required for access after sign-in.

2. **Check if the config bucket exists** – Run `gsutil ls | grep gcip-iap-bucket`. If a bucket appears (Google may have created it when you set the Login URL), ensure it contains `config.json` (e.g. `gsutil ls gs://BUCKET_NAME/`). If the bucket exists but has no `config.json`, upload one (see `docs/iap-hosted-ui-config.example.json` and the [UI config reference](https://cloud.google.com/iap/docs/reference/ui-config)).

3. **Try the Customize URL** – Open `https://iap-gcip-hosted-ui-docsgpt-frontend-qx2omzvylq-nn.a.run.app/admin` in your browser. If this also shows “service unavailable”, the hosted UI cannot load its config (missing bucket or `config.json`). If the admin page loads, the config is loading and the issue may be the main login path or permissions.

4. **Identity Platform / OAuth** – If you use external identities, ensure **Identity Platform** has at least one provider (e.g. Google) and the OAuth consent screen is configured. For Google-only sign-in, the consent screen must be set in **APIs & Services → OAuth consent screen**.

5. **Hosted UI cannot read config** – The hosted sign-in page runs as a Cloud Run service and reads `config.json` from the bucket. If the bucket and `config.json` exist but you still see “service unavailable”, the service account may lack read access. Grant the **default Compute Engine service account** (used by the hosted UI) the **Storage Object Viewer** role on the bucket:

   ```bash
   PROJECT_ID="manny-roy-consulting"
   PROJECT_NUMBER="782077674267"
   BUCKET="gcip-iap-bucket-iap-gcip-hosted-ui-docsgpt-fro-782077674267"

   gcloud storage buckets add-iam-policy-binding gs://$BUCKET \
     --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
     --role="roles/storage.objectViewer" \
     --project=$PROJECT_ID
   ```

   Re-upload `config.json` if you changed it (e.g. added `signInFlow: "popup"` when using `authDomain: "PROJECT_ID.firebaseapp.com"`). Then retry the login and, if it still fails, check **Cloud Run → iap-gcip-hosted-ui-docsgpt-frontend → Logs** for the actual error (e.g. 403, parse error).

### "Cannot read properties of undefined (reading 'message')" on the sign-in page

This usually means the hosted UI is loading but an **Identity Platform** call is failing or returning an unexpected shape (e.g. no error object), so the UI tries to read `.message` on `undefined`.

**Fix:**

1. **Enable Identity Platform and add Google**  
   IAP’s hosted sign-in with external identities uses Identity Platform. In the console: **Customer Identity (Identity Platform)** (or **Build → Identity Platform**). Enable Identity Platform for the project, then add **Google** as a sign-in provider and save. Use the same OAuth client (or create one) and set **Authorized redirect URIs** to include your hosted UI auth handler, e.g.  
   `https://iap-gcip-hosted-ui-docsgpt-frontend-qx2omzvylq-nn.a.run.app/__/auth/handler`

2. **Use external identities in IAP**  
   On **Security → Identity-Aware Proxy**, select **docsgpt-frontend**. In the side panel, ensure **Use external identities for authorization** is on and that **project providers** (or the tenant you use in `config.json`) are selected. Use **Configure providers** if you need to add or fix the Google provider.

3. **Tenant in config**  
   Your `config.json` uses tenant `_782077674267`. If you use **project-level** providers only (no multi-tenancy), try a config that uses project-level sign-in (see Identity Platform / IAP docs for a single-provider config without a tenant). If you use multi-tenancy, create a tenant in Identity Platform with that ID (or the ID you use in config) and enable the Google provider for that tenant.

4. **OAuth consent and client**  
   In **APIs & Services → Credentials**, confirm the OAuth 2.0 client used by Identity Platform has the correct **Authorized redirect URIs** (including the `.../__/auth/handler` URL above). **OAuth consent screen** must be configured (Internal or External).