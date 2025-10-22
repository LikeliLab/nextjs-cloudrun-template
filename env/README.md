# env/ directory

This folder is intended to hold runtime environment files for local development, staging and production.

Guidelines
- Keep real secrets out of the repo. Only commit example files (`*.example`) and a placeholder (`.gitkeep`).
- To create a real runtime file, copy the example and edit values. For example:

```bash
cp env/.env.development.example env/.env.development
# then edit env/.env.development
```

- For production secrets, use a secret manager (Google Secret Manager, GitHub Actions secrets, etc.) instead of committing values.

Files in this folder
- `.env.development` - local development runtime env (ignored by git)
- `.env.staging` - staging runtime env (ignored by git)
- `.env.production` - production runtime env (ignored by git)
- `*.example` - safe example files that are committed and used as templates
