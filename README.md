# FindBack — AI-Powered Campus Lost & Found

**拾光失物** is a HarmonyOS campus lost-and-found app. It combines item photos, descriptions, campus locations, and time clues to help students find likely matches.

## Features

- Publish lost and found items with photos
- Analyze item descriptions and visual clues through an optional AI provider
- Match items using campus, time, location, category, and other features
- Browse match explanations, chat, and receive HarmonyOS notifications
- Keep item records in a FastAPI backend with SQLite persistence

## Project layout

- `harmonyos/` — ArkTS / ArkUI client
- `backend/` — FastAPI service and tests
- `docs/` — architecture notes

## Run the backend (Windows)

```powershell
cd backend
py -3.13 -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
Copy-Item .env.example .env
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

The API documentation is available at `http://127.0.0.1:8000/docs`.

To enable DeepSeek image analysis, add your own key to `backend/.env` and set `AI_ENABLED=true`. Never commit `.env` or put provider keys in the HarmonyOS client.

## Build the HarmonyOS app

Open `harmonyos/` in DevEco Studio, let it sync dependencies, then build the `entry` module. Configure a backend URL reachable from the target device in `harmonyos/entry/src/main/ets/data/ApiClient.ets` before testing on a simulator or phone. Localhost is only suitable when the backend is reachable from that device as localhost.

The signing profile and certificate are local development settings and are not included in this repository. Configure signing in DevEco Studio for your own test device or release process.

## Development notes

- Local database, uploads, virtual environments, signing files, HAPs, and generated packages are excluded by `.gitignore`.
- The demo backend is an MVP. Add HTTPS, authentication, and production-grade abuse protection before exposing it to general users.
