from __future__ import annotations

from pathlib import Path
from typing import Dict, List, Optional, Union
from uuid import UUID, uuid4

from fastapi import FastAPI, File, HTTPException, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from .core.config import get_settings
from .domain import (
    AIAnalysis,
    ChatMessage,
    ChatMessageCreate,
    ChatThread,
    ChatThreadCreate,
    Item,
    ItemCreate,
    MatchCandidate,
    School,
)
from .repositories import (
    InMemoryItemRepository,
    InMemorySchoolRepository,
    InMemoryChatRepository,
    SqliteChatRepository,
    SqliteItemRepository,
    sqlite_path_from_url,
)
from .services import (
    DeepSeekVisionProvider,
    DisabledVisionProvider,
    MatchingService,
)


settings = get_settings()
database_path = sqlite_path_from_url(settings.database_url)
item_repository = (
    InMemoryItemRepository()
    if settings.app_env == "test" or database_path == ":memory:"
    else SqliteItemRepository(database_path)
)
school_repository = InMemorySchoolRepository()
chat_repository = (
    InMemoryChatRepository()
    if settings.app_env == "test" or database_path == ":memory:"
    else SqliteChatRepository(database_path)
)
vision_provider = (
    DeepSeekVisionProvider(settings)
    if settings.ai_enabled and settings.deepseek_api_key
    else DisabledVisionProvider()
)
matching_service = MatchingService(item_repository, vision_provider)

app = FastAPI(
    title="拾光失物 API",
    version="0.1.0",
    description="面向高校学生的 AI 失物主动匹配服务。",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

UPLOADS_DIR = Path(__file__).resolve().parents[1] / "uploads"
UPLOADS_DIR.mkdir(parents=True, exist_ok=True)
app.mount("/uploads", StaticFiles(directory=str(UPLOADS_DIR)), name="uploads")

ALLOWED_IMAGE_TYPES = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
    "image/gif": ".gif",
}
MAX_UPLOAD_BYTES = 10 * 1024 * 1024


@app.get("/api/v1/health")
def health() -> Dict[str, Union[str, bool]]:
    return {"status": "ok", "ai_enabled": vision_provider.enabled}


@app.post("/api/v1/uploads")
async def upload_image(file: UploadFile = File(...)) -> Dict[str, str]:
    suffix = ALLOWED_IMAGE_TYPES.get(file.content_type or "")
    if not suffix:
        raise HTTPException(
            status_code=415,
            detail="only jpeg, png, webp, or gif images are supported",
        )

    filename = f"{uuid4().hex}{suffix}"
    destination = UPLOADS_DIR / filename
    total = 0
    try:
        with destination.open("wb") as output:
            while chunk := await file.read(1024 * 1024):
                total += len(chunk)
                if total > MAX_UPLOAD_BYTES:
                    raise HTTPException(status_code=413, detail="image is larger than 10 MB")
                output.write(chunk)
    except Exception:
        destination.unlink(missing_ok=True)
        raise
    finally:
        await file.close()

    return {
        "url": f"/uploads/{filename}",
        "filename": filename,
        "content_type": file.content_type or "",
    }


@app.post("/api/v1/uploads/raw")
async def upload_raw_image(request: Request) -> Dict[str, str]:
    """Accept a binary image body from native clients that do not build multipart forms."""
    content_type = (request.headers.get("content-type") or "").split(";", 1)[0].strip()
    suffix = ALLOWED_IMAGE_TYPES.get(content_type)
    if not suffix:
        raise HTTPException(
            status_code=415,
            detail="only jpeg, png, webp, or gif images are supported",
        )

    body = await request.body()
    if not body:
        raise HTTPException(status_code=400, detail="image body is empty")
    if len(body) > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="image is larger than 10 MB")

    filename = f"{uuid4().hex}{suffix}"
    destination = UPLOADS_DIR / filename
    destination.write_bytes(body)
    return {
        "url": f"/uploads/{filename}",
        "filename": filename,
        "content_type": content_type,
    }


@app.get("/api/v1/schools", response_model=list[School])
def list_schools() -> List[School]:
    return school_repository.list()


@app.post("/api/v1/items", response_model=Item)
def create_item(payload: ItemCreate) -> Item:
    item = Item(**payload.model_dump())
    return item_repository.add(item)


@app.get("/api/v1/items", response_model=list[Item])
def list_items(school_id: Optional[str] = None) -> List[Item]:
    items = item_repository.list()
    if school_id:
        items = [item for item in items if item.item_school_id == school_id]
    return items


@app.get("/api/v1/items/{item_id}", response_model=Item)
def get_item(item_id: UUID) -> Item:
    item = item_repository.get(item_id)
    if not item:
        raise HTTPException(status_code=404, detail="item not found")
    return item


@app.post("/api/v1/chats", response_model=ChatThread)
def create_chat(payload: ChatThreadCreate) -> ChatThread:
    if not item_repository.get(payload.item_id):
        raise HTTPException(status_code=404, detail="item not found")
    return chat_repository.get_or_create(payload.item_id, payload.participant_id)


@app.get("/api/v1/chats/inbox", response_model=list[ChatThread])
def list_chat_inbox(owner_id: str) -> List[ChatThread]:
    owned_items = [
        item for item in item_repository.list() if item.publisher_id == owner_id
    ]
    return sorted(
        (
            thread
            for item in owned_items
            for thread in chat_repository.list_for_item(item.id)
        ),
        key=lambda thread: thread.created_at,
        reverse=True,
    )


@app.get("/api/v1/chats/{chat_id}/messages", response_model=list[ChatMessage])
def list_chat_messages(chat_id: UUID) -> List[ChatMessage]:
    if not chat_repository.get(chat_id):
        raise HTTPException(status_code=404, detail="chat not found")
    return chat_repository.list_messages(chat_id)


@app.post("/api/v1/chats/{chat_id}/messages", response_model=ChatMessage)
def send_chat_message(chat_id: UUID, payload: ChatMessageCreate) -> ChatMessage:
    if not chat_repository.get(chat_id):
        raise HTTPException(status_code=404, detail="chat not found")
    try:
        return chat_repository.add_message(chat_id, payload.sender_id, payload.body)
    except KeyError as error:
        raise HTTPException(status_code=404, detail="chat not found") from error


@app.post("/api/v1/items/{item_id}/analyze", response_model=AIAnalysis)
async def analyze_item(item_id: UUID) -> AIAnalysis:
    item = item_repository.get(item_id)
    if not item:
        raise HTTPException(status_code=404, detail="item not found")
    if not item.image_url:
        raise HTTPException(status_code=400, detail="image_url is required")
    if item.ai_features:
        return AIAnalysis.model_validate(item.ai_features)

    analysis = await vision_provider.analyze(item.image_url, item.description)
    item.ai_features = analysis.model_dump()
    if analysis.category and (not item.category or item.category == "其他"):
        item.category = analysis.category
    if analysis.color and (not item.color or item.color == "未填写"):
        item.color = analysis.color
    item_repository.update(item)
    return analysis


@app.get("/api/v1/items/{item_id}/matches", response_model=list[MatchCandidate])
async def get_matches(item_id: UUID) -> List[MatchCandidate]:
    if not item_repository.get(item_id):
        raise HTTPException(status_code=404, detail="item not found")
    return await matching_service.matches_for(item_id)
