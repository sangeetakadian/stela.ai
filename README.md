# STELA Monorepo

This repository is split into separate frontend and backend apps:

- `frontend/` -> Flutter Web/mobile app
- `backend/` -> Flask code execution API (`/execute`)

## Local Development

### Frontend (Flutter)

```bash
cd frontend
flutter pub get
flutter run -d chrome \
	--dart-define=CODE_EXEC_ENDPOINT=http://localhost:8080/execute
```

### Backend (Flask)

The API uses Vercel Sandbox credentials, so run it through the linked Vercel
project rather than starting Flask directly:

```bash
cd backend
vercel pull --yes --environment=development
vercel dev
```

## Deploy the Flutter web app to Vercel

The GitHub Actions workflow builds with Flutter 3.35.7 and deploys to Vercel
when frontend changes are pushed to `main` (or when the workflow is run
manually).

1. Create a Vercel project linked to this repository and set its **Root
   Directory** to `frontend`. The repository's `frontend/vercel.json` provides
   the Flutter install/build commands and web output directory.
2. Deploy the backend first as described in
   [backend/DEPLOY.md](backend/DEPLOY.md), then set the frontend project's
   production `CODE_EXEC_ENDPOINT` to the backend's HTTPS `/execute` URL.
3. Add these GitHub Actions repository secrets for the frontend:
   - `VERCEL_TOKEN`
   - `VERCEL_ORG_ID`
   - `VERCEL_PROJECT_ID`
4. Ensure `frontend/pubspec.lock` is committed, then push frontend changes to
   `main` or run
   **Build and deploy Flutter web to Vercel** from the Actions tab.

The app embeds `CODE_EXEC_ENDPOINT` into the web build, so changing the Vercel
environment variable requires a new deployment. Configure the app's domain in
Vercel after the first deployment.

## Deploy the backend

The backend uses a separate Vercel project rooted at `backend/`. Its GitHub
Actions workflow builds a multi-language Vercel Sandbox image, pushes it to
Vercel Container Registry, waits for image preparation, and deploys the Flask
API. It needs the shared `VERCEL_TOKEN` and `VERCEL_ORG_ID` secrets plus
`VERCEL_BACKEND_PROJECT_ID` for the backend project.

The API requires Firebase authentication and runs submitted programs in
network-disabled, disposable Vercel Sandbox microVMs. Sandbox use is billable;
the backend Vercel project has a Firewall limit of 120 `/execute` requests per
minute per IP. Review account spend limits before making execution available
publicly. See [backend/DEPLOY.md](backend/DEPLOY.md) for setup details.
