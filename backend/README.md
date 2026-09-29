# FindBack backend

FastAPI MVP for the FindBack HarmonyOS campus lost-and-found app. Item records are stored in SQLite by default, and uploaded images are saved under the local `uploads/` directory.

## Start locally

```powershell
cd backend
py -3.13 -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
Copy-Item .env.example .env
uvicorn app.main:app --reload --port 8000
```

API docs: `http://127.0.0.1:8000/docs`.

To enable DeepSeek image analysis, set `DEEPSEEK_API_KEY` and `AI_ENABLED=true` in your local `.env`. The key must remain on the server and must not be committed.

## Windows auto-start

Run `register-backend-autostart.ps1` from an elevated or appropriately permissioned PowerShell session to register the current-user logon task. The task uses the local virtual environment and writes logs under `backend/logs/`.

## API overview

- `GET /api/v1/health`
- `GET /api/v1/schools`
- `POST /api/v1/items`
- `GET /api/v1/items/{item_id}`
- `GET /api/v1/items/{item_id}/matches`
- `POST /api/v1/items/{item_id}/analyze`
- `POST /api/v1/uploads`

This is a demonstration MVP. Before public deployment, configure HTTPS, authentication, rate limiting, and persistent storage. Do not use real identity documents or other sensitive personal data in the demo.
