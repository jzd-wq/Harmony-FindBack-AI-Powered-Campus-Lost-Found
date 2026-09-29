from __future__ import annotations

import json
import sqlite3
from datetime import datetime
from pathlib import Path
from threading import RLock
from typing import List, Optional, Protocol
from uuid import UUID

from .domain import ChatMessage, ChatThread, Item, School


class ItemRepository(Protocol):
    def add(self, item: Item) -> Item: ...

    def get(self, item_id: UUID) -> Optional[Item]: ...

    def list(self) -> List[Item]: ...

    def update(self, item: Item) -> Item: ...


class SchoolRepository(Protocol):
    def list(self) -> list[School]: ...


class ChatRepository(Protocol):
    def get_or_create(self, item_id: UUID, participant_id: str) -> ChatThread: ...

    def list_for_item(self, item_id: UUID) -> list[ChatThread]: ...

    def get(self, chat_id: UUID) -> Optional[ChatThread]: ...

    def list_messages(self, chat_id: UUID) -> list[ChatMessage]: ...

    def add_message(self, chat_id: UUID, sender_id: str, body: str) -> ChatMessage: ...


class InMemoryItemRepository:
    def __init__(self) -> None:
        self._items: dict[UUID, Item] = {}

    def add(self, item: Item) -> Item:
        self._items[item.id] = item
        return item

    def get(self, item_id: UUID) -> Optional[Item]:
        return self._items.get(item_id)

    def list(self) -> list[Item]:
        return list(self._items.values())

    def update(self, item: Item) -> Item:
        self._items[item.id] = item
        return item


class SqliteItemRepository:
    """Small SQLite-backed repository for the runnable MVP."""

    def __init__(self, database_path: str | Path) -> None:
        self._lock = RLock()
        self._connection = sqlite3.connect(
            str(database_path), check_same_thread=False
        )
        self._connection.execute(
            """
            CREATE TABLE IF NOT EXISTS items (
                id TEXT PRIMARY KEY,
                item_type TEXT NOT NULL,
                item_school_id TEXT NOT NULL,
                status TEXT NOT NULL,
                payload_json TEXT NOT NULL
            )
            """
        )
        self._connection.commit()

    def add(self, item: Item) -> Item:
        return self.update(item)

    def get(self, item_id: UUID) -> Optional[Item]:
        with self._lock:
            row = self._connection.execute(
                "SELECT payload_json FROM items WHERE id = ?",
                (str(item_id),),
            ).fetchone()
        return Item.model_validate(json.loads(row[0])) if row else None

    def list(self) -> list[Item]:
        with self._lock:
            rows = self._connection.execute(
                "SELECT payload_json FROM items ORDER BY rowid DESC"
            ).fetchall()
        return [Item.model_validate(json.loads(row[0])) for row in rows]

    def update(self, item: Item) -> Item:
        payload = item.model_dump(mode="json")
        with self._lock:
            self._connection.execute(
                """
                INSERT INTO items (id, item_type, item_school_id, status, payload_json)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    item_type = excluded.item_type,
                    item_school_id = excluded.item_school_id,
                    status = excluded.status,
                    payload_json = excluded.payload_json
                """,
                (
                    str(item.id),
                    getattr(item.item_type, "value", item.item_type),
                    item.item_school_id,
                    getattr(item.status, "value", item.status),
                    json.dumps(payload, ensure_ascii=False),
                ),
            )
            self._connection.commit()
        return item

    def close(self) -> None:
        with self._lock:
            self._connection.close()


class InMemoryChatRepository:
    def __init__(self) -> None:
        self._threads: dict[UUID, ChatThread] = {}
        self._thread_keys: dict[tuple[UUID, str], UUID] = {}
        self._messages: dict[UUID, list[ChatMessage]] = {}
        self._lock = RLock()

    def get_or_create(self, item_id: UUID, participant_id: str) -> ChatThread:
        key = (item_id, participant_id)
        with self._lock:
            existing_id = self._thread_keys.get(key)
            if existing_id:
                return self._threads[existing_id]
            thread = ChatThread(item_id=item_id, participant_id=participant_id)
            self._threads[thread.id] = thread
            self._thread_keys[key] = thread.id
            self._messages[thread.id] = []
            return thread

    def get(self, chat_id: UUID) -> Optional[ChatThread]:
        with self._lock:
            return self._threads.get(chat_id)

    def list_for_item(self, item_id: UUID) -> list[ChatThread]:
        with self._lock:
            return sorted(
                (thread for thread in self._threads.values() if thread.item_id == item_id),
                key=lambda thread: thread.created_at,
                reverse=True,
            )

    def list_messages(self, chat_id: UUID) -> list[ChatMessage]:
        with self._lock:
            return list(self._messages.get(chat_id, []))

    def add_message(self, chat_id: UUID, sender_id: str, body: str) -> ChatMessage:
        with self._lock:
            thread = self._threads.get(chat_id)
            if not thread:
                raise KeyError(chat_id)
            message = ChatMessage(
                chat_id=chat_id,
                item_id=thread.item_id,
                sender_id=sender_id,
                body=body,
            )
            self._messages[chat_id].append(message)
            return message


class SqliteChatRepository:
    """SQLite-backed chat threads and messages for the runnable MVP."""

    def __init__(self, database_path: str | Path) -> None:
        self._lock = RLock()
        self._connection = sqlite3.connect(
            str(database_path), check_same_thread=False
        )
        self._connection.executescript(
            """
            CREATE TABLE IF NOT EXISTS chat_threads (
                id TEXT PRIMARY KEY,
                item_id TEXT NOT NULL,
                participant_id TEXT NOT NULL,
                created_at TEXT NOT NULL,
                UNIQUE(item_id, participant_id)
            );
            CREATE TABLE IF NOT EXISTS chat_messages (
                id TEXT PRIMARY KEY,
                chat_id TEXT NOT NULL,
                item_id TEXT NOT NULL,
                sender_id TEXT NOT NULL,
                body TEXT NOT NULL,
                created_at TEXT NOT NULL
            );
            """
        )
        self._connection.commit()

    def get_or_create(self, item_id: UUID, participant_id: str) -> ChatThread:
        with self._lock:
            row = self._connection.execute(
                "SELECT id, item_id, participant_id, created_at FROM chat_threads "
                "WHERE item_id = ? AND participant_id = ?",
                (str(item_id), participant_id),
            ).fetchone()
            if row:
                return ChatThread(
                    id=UUID(row[0]),
                    item_id=UUID(row[1]),
                    participant_id=row[2],
                    created_at=datetime.fromisoformat(row[3]),
                )

            thread = ChatThread(item_id=item_id, participant_id=participant_id)
            self._connection.execute(
                "INSERT INTO chat_threads (id, item_id, participant_id, created_at) "
                "VALUES (?, ?, ?, ?)",
                (
                    str(thread.id),
                    str(thread.item_id),
                    thread.participant_id,
                    thread.created_at.isoformat(),
                ),
            )
            self._connection.commit()
            return thread

    def get(self, chat_id: UUID) -> Optional[ChatThread]:
        with self._lock:
            row = self._connection.execute(
                "SELECT id, item_id, participant_id, created_at FROM chat_threads WHERE id = ?",
                (str(chat_id),),
            ).fetchone()
        if not row:
            return None
        return ChatThread(
            id=UUID(row[0]),
            item_id=UUID(row[1]),
            participant_id=row[2],
            created_at=datetime.fromisoformat(row[3]),
        )

    def list_for_item(self, item_id: UUID) -> list[ChatThread]:
        with self._lock:
            rows = self._connection.execute(
                "SELECT id, item_id, participant_id, created_at FROM chat_threads "
                "WHERE item_id = ? ORDER BY created_at DESC",
                (str(item_id),),
            ).fetchall()
        return [
            ChatThread(
                id=UUID(row[0]),
                item_id=UUID(row[1]),
                participant_id=row[2],
                created_at=datetime.fromisoformat(row[3]),
            )
            for row in rows
        ]

    def list_messages(self, chat_id: UUID) -> list[ChatMessage]:
        with self._lock:
            rows = self._connection.execute(
                "SELECT id, chat_id, item_id, sender_id, body, created_at "
                "FROM chat_messages WHERE chat_id = ? ORDER BY rowid ASC",
                (str(chat_id),),
            ).fetchall()
        return [
            ChatMessage(
                id=UUID(row[0]),
                chat_id=UUID(row[1]),
                item_id=UUID(row[2]),
                sender_id=row[3],
                body=row[4],
                created_at=datetime.fromisoformat(row[5]),
            )
            for row in rows
        ]

    def add_message(self, chat_id: UUID, sender_id: str, body: str) -> ChatMessage:
        thread = self.get(chat_id)
        if not thread:
            raise KeyError(chat_id)
        message = ChatMessage(
            chat_id=chat_id,
            item_id=thread.item_id,
            sender_id=sender_id,
            body=body,
        )
        with self._lock:
            self._connection.execute(
                "INSERT INTO chat_messages "
                "(id, chat_id, item_id, sender_id, body, created_at) VALUES (?, ?, ?, ?, ?, ?)",
                (
                    str(message.id),
                    str(message.chat_id),
                    str(message.item_id),
                    message.sender_id,
                    message.body,
                    message.created_at.isoformat(),
                ),
            )
            self._connection.commit()
        return message

    def close(self) -> None:
        with self._lock:
            self._connection.close()


def sqlite_path_from_url(database_url: str) -> str:
    prefix = "sqlite:///"
    if not database_url.startswith(prefix):
        raise ValueError(f"Unsupported database URL: {database_url}")

    raw_path = database_url[len(prefix) :]
    if raw_path == ":memory:":
        return raw_path

    path = Path(raw_path)
    if not path.is_absolute():
        path = Path(__file__).resolve().parents[1] / path
    path.parent.mkdir(parents=True, exist_ok=True)
    return str(path)


class InMemorySchoolRepository:
    def __init__(self) -> None:
        self._schools = [
            School(id="school-a", name="高校A", city="武汉", campuses=["main"]),
            School(id="school-b", name="高校B", city="武汉", campuses=["main"]),
        ]

    def list(self) -> list[School]:
        return self._schools
