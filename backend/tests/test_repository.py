import tempfile
import unittest
from datetime import datetime
from pathlib import Path

from app.domain import Item, ItemType
from app.repositories import SqliteChatRepository, SqliteItemRepository


class SqliteRepositoryTest(unittest.TestCase):
    def test_item_survives_repository_recreation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            database_path = Path(directory) / "items.db"
            item = Item(
                user_school_id="school-a",
                item_school_id="school-a",
                location="图书馆",
                item_type=ItemType.LOST,
                title="蓝色校园卡",
                occurred_at=datetime(2026, 9, 21, 14, 0),
            )

            writer = SqliteItemRepository(database_path)
            writer.add(item)
            writer.close()

            reader = SqliteItemRepository(database_path)
            restored = reader.get(item.id)
            reader.close()

            self.assertIsNotNone(restored)
            self.assertEqual(restored.title, item.title)
            self.assertEqual(restored.item_type, item.item_type)

    def test_chat_messages_survive_repository_recreation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            database_path = Path(directory) / "chat.db"
            item_id = Item(
                user_school_id="school-a",
                item_school_id="school-a",
                location="图书馆",
                item_type=ItemType.FOUND,
                title="蓝色校园卡",
                occurred_at=datetime(2026, 9, 21, 14, 0),
            ).id

            writer = SqliteChatRepository(database_path)
            thread = writer.get_or_create(item_id, "owner-001")
            visitor_thread = writer.get_or_create(item_id, "visitor-001")
            writer.add_message(thread.id, "owner-001", "你好，我想确认一下物品")
            self.assertEqual(
                {thread.id, visitor_thread.id},
                {entry.id for entry in writer.list_for_item(item_id)},
            )
            writer.close()

            reader = SqliteChatRepository(database_path)
            restored_thread = reader.get_or_create(item_id, "owner-001")
            messages = reader.list_messages(restored_thread.id)
            reader.close()

            self.assertEqual(restored_thread.id, thread.id)
            self.assertEqual(len(messages), 1)
            self.assertEqual(messages[0].body, "你好，我想确认一下物品")


if __name__ == "__main__":
    unittest.main()
