# Deploying the code execution backend

The Flask API runs as a Vercel Python Function. Every submitted program runs in
a disposable Vercel Sandbox microVM using a custom image with Python, Node.js,
C/C++, Java, and Dart. Sandboxes have no network access, one vCPU, 2 GB memory,
bounded output, and a strict execution deadline. Firebase ID tokens are required
before the API creates a Sandbox.

## Configure GitHub Actions

The `Build sandbox and deploy backend to Vercel` workflow builds and pushes the
custom Sandbox image to Vercel Container Registry, waits for it to become ready,
then deploys the backend project. Add these repository secrets in GitHub:

- `VERCEL_TOKEN`
- `VERCEL_ORG_ID`
- `VERCEL_BACKEND_PROJECT_ID` — the ID of the `stela-exec-backend` project

The frontend deployment workflow uses the same token and org ID, plus
`VERCEL_PROJECT_ID` for the `stela_ai` project.

The backend defaults to the Firebase project `stela23-f9a52`. Set
`FIREBASE_PROJECT_ID` in Vercel only if the app uses a different Firebase
project. The default CORS allowlist includes the configured app domain,
localhost, and Vercel deployment domains. Set `ALLOWED_ORIGINS` to a
comma-separated list if your frontend uses another domain.

## Connect the frontend

After the first backend deployment, copy its production domain and set the
frontend Vercel project's production environment variable to:

```text
CODE_EXEC_ENDPOINT=https://YOUR_BACKEND_DOMAIN/execute
```

From the linked `frontend/` directory, use Vercel CLI to add the variable:

```bash
vercel env add CODE_EXEC_ENDPOINT production
```

Enter the backend URL when prompted.

Redeploy the frontend after changing the variable; Flutter embeds it at build
time. Frontend execution requests automatically include the signed-in user's
Firebase ID token.

## Local development

From the linked `backend/` directory, pull its Vercel development environment
and start the API with:

```bash
vercel pull --yes --environment=development
vercel dev
```

This provides the credentials the Sandbox SDK needs. The local Python API does
not execute submitted code on the host. Running it without Vercel Sandbox
credentials returns an explicit service error.

Run backend tests with:

```bash
python -m unittest discover -s backend -p "test_*.py"
```

## Cost and abuse controls

Vercel Sandbox usage is billable and subject to the account's plan and quotas.
The API applies a per-user request limit, and the backend Vercel project has a
published Firewall rule limiting `/execute` to 120 requests per minute per IP.
The in-process per-user limiter is still best-effort because Vercel Functions
are stateless. Review Sandbox spend limits before sharing the app publicly.
