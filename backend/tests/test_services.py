import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from app.core.config import Settings
from app.domain import AIAnalysis, Item, ItemType
from app.repositories import InMemoryItemRepository
from app.services import DeepSeekVisionProvider, MatchingService


class DeepSeekVisionProviderTest(unittest.TestCase):
    def test_local_upload_becomes_data_url(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            uploads_dir = Path(directory)
            (uploads_dir / "card.png").write_bytes(b"fake-png")
            provider = DeepSeekVisionProvider(
                Settings(deepseek_api_key="test-key"),
                uploads_dir=uploads_dir,
            )
            source = provider._image_source("/uploads/card.png")
            self.assertTrue(source.startswith("data:image/png;base64,"))

    def test_remote_and_data_sources_are_preserved(self) -> None:
        provider = DeepSeekVisionProvider(Settings(deepseek_api_key="test-key"))
        self.assertEqual(provider._image_source("https://example.com/card.png"), "https://example.com/card.png")
        self.assertEqual(provider._image_source("data:image/png;base64,abc"), "data:image/png;base64,abc")


class MatchingServiceTest(unittest.TestCase):
    def test_time_score_accepts_legacy_naive_and_utc_timestamps(self) -> None:
        legacy = datetime(2026, 9, 24, 5, 23)
        current = datetime(2026, 9, 24, 5, 23, tzinfo=timezone.utc)
        self.assertEqual(MatchingService._time_score(legacy, current), 1.0)

    def test_ai_image_review_is_returned_for_plausible_matches(self) -> None:
        class FakeVision:
            enabled = True
            compare_calls = 0

            async def analyze(self, image_url: str, text: str = "") -> AIAnalysis:
                return AIAnalysis()

            async def compare(self, lost: Item, found: Item) -> tuple[float, list[str]]:
                self.compare_calls += 1
                return 0.9, ["图片形状和划痕位置相近"]

        now = datetime.now(timezone.utc)
        repository = InMemoryItemRepository()
        lost = Item(
            publisher_id="lost-owner",
            user_school_id="wust",
            item_school_id="wust",
            location="图书馆二楼",
            item_type=ItemType.LOST,
            title="我的蓝牙耳机",
            description="左边有划痕",
            category="耳机",
            color="黑色",
            image_url="/uploads/lost.jpg",
            occurred_at=now,
        )
        found = Item(
            publisher_id="finder",
            user_school_id="wust",
            item_school_id="wust",
            location="图书馆一楼",
            item_type=ItemType.FOUND,
            title="拾到蓝牙耳机",
            description="外壳有划痕",
            category="耳机",
            color="黑色",
            image_url="/uploads/found.jpg",
            occurred_at=now,
        )
        repository.add(lost)
        repository.add(found)

        import asyncio

        vision = FakeVision()
        service = MatchingService(repository, vision)
        matches = asyncio.run(service.matches_for(lost.id))
        asyncio.run(service.matches_for(lost.id))

        self.assertEqual(len(matches), 1)
        self.assertEqual(matches[0].ai_score, 0.9)
        self.assertIn("图片形状和划痕位置相近", matches[0].ai_reasons)
        self.assertIn("已完成 AI 图片复核", matches[0].explanation)
        self.assertEqual(vision.compare_calls, 1)


if __name__ == "__main__":
    unittest.main()
