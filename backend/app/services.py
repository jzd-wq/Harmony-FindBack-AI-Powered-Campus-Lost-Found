from __future__ import annotations

import json
import base64
import mimetypes
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Protocol
from uuid import UUID
from urllib.parse import urlparse

import httpx

from .core.config import Settings
from .domain import AIAnalysis, Item, ItemType, MatchCandidate, ScopeMode
from .repositories import ItemRepository


class VisionAnalysisProvider(Protocol):
    enabled: bool

    async def analyze(self, image_url: str, text: str = "") -> AIAnalysis: ...

    async def compare(self, lost: Item, found: Item) -> tuple[float, list[str]]: ...


class DeepSeekVisionProvider:
    enabled = True

    def __init__(self, settings: Settings, uploads_dir: Path | None = None) -> None:
        self.settings = settings
        self.uploads_dir = (uploads_dir or Path(__file__).resolve().parents[1] / "uploads").resolve()

    def _image_source(self, image_url: str) -> str:
        if image_url.startswith(("http://", "https://", "data:")):
            return image_url
        path = urlparse(image_url).path
        if not path.startswith("/uploads/"):
            return image_url
        relative_path = path.removeprefix("/uploads/")
        local_path = (self.uploads_dir / relative_path).resolve()
        if not local_path.is_file() or not local_path.is_relative_to(self.uploads_dir):
            return image_url
        mime_type = mimetypes.guess_type(local_path.name)[0] or "application/octet-stream"
        encoded = base64.b64encode(local_path.read_bytes()).decode("ascii")
        return f"data:{mime_type};base64,{encoded}"

    async def _request(self, prompt: str, image_urls: list[str]) -> dict:
        if not self.settings.deepseek_api_key:
            raise RuntimeError("DEEPSEEK_API_KEY is not configured")

        content: list[dict] = [{"type": "text", "text": prompt}]
        for image_url in image_urls:
            content.append(
                {
                    "type": "image_url",
                    "image_url": {"url": self._image_source(image_url), "detail": "auto"},
                }
            )

        async with httpx.AsyncClient(timeout=60) as client:
            response = await client.post(
                f"{self.settings.deepseek_base_url.rstrip('/')}/chat/completions",
                headers={
                    "Authorization": f"Bearer {self.settings.deepseek_api_key}",
                    "Content-Type": "application/json",
                },
                json={
                    "model": self.settings.deepseek_model,
                    "messages": [{"role": "user", "content": content}],
                    "temperature": 0.1,
                },
            )
            response.raise_for_status()
            payload = response.json()
            text = payload["choices"][0]["message"]["content"]
            return self._parse_json(text)

    @staticmethod
    def _parse_json(text: str) -> dict:
        fenced = re.search(r"```(?:json)?\s*(.*?)\s*```", text, re.S)
        candidate = fenced.group(1) if fenced else text
        start = candidate.find("{")
        end = candidate.rfind("}")
        if start < 0 or end < start:
            raise ValueError("AI response does not contain a JSON object")
        return json.loads(candidate[start : end + 1])

    async def analyze(self, image_url: str, text: str = "") -> AIAnalysis:
        prompt = f"""
你是校园失物分析器。请分析图片和补充描述，只返回 JSON，不要输出解释。
补充描述：{text}
JSON 字段必须包括：category, color, brand, model, visible_text,
sensitive_text, features, confidence。
visible_text 只记录图片中看得清的文字；无法确认时返回空数组。
sensitive_text 记录姓名、学号、手机号、证件号等敏感信息，但不要编造。
confidence 为 0 到 1 的数字。
"""
        return AIAnalysis.model_validate(await self._request(prompt, [image_url]))

    async def compare(self, lost: Item, found: Item) -> tuple[float, list[str]]:
        if not lost.image_url or not found.image_url:
            return 0.0, ["缺少双方图片，无法进行视觉复核"]

        prompt = f"""
判断下面两条校园失物信息是否可能是同一件物品，只返回 JSON。
失主描述：{lost.description}
拾获描述：{found.description}
失主类别：{lost.category}
拾获类别：{found.category}
请返回 {{"score": 0到1之间的小数, "reasons": ["原因"]}}。
不要因为类别相同就直接判定为同一件物品。
"""
        payload = await self._request(prompt, [lost.image_url, found.image_url])
        score = float(payload.get("score", 0))
        reasons = [str(item) for item in payload.get("reasons", [])]
        return max(0.0, min(1.0, score)), reasons


class DisabledVisionProvider:
    enabled = False

    async def analyze(self, image_url: str, text: str = "") -> AIAnalysis:
        return AIAnalysis()

    async def compare(self, lost: Item, found: Item) -> tuple[float, list[str]]:
        return 0.0, ["AI 未启用，已使用结构化信息匹配"]


class MatchingService:
    def __init__(self, repository: ItemRepository, vision: VisionAnalysisProvider) -> None:
        self.repository = repository
        self.vision = vision
        self._ai_comparison_cache: dict[tuple[UUID, UUID], tuple[float, list[str]]] = {}

    def _scope_allowed(self, lost: Item, found: Item) -> bool:
        if lost.item_school_id == found.item_school_id:
            return True
        return lost.scope_mode == ScopeMode.CROSS_SCHOOL

    @staticmethod
    def _text_tokens(item: Item) -> set[str]:
        content = " ".join(
            [item.title, item.description, item.category or "", item.color or ""]
        )
        return {token for token in re.split(r"\W+", content.lower()) if token}

    @staticmethod
    def _time_score(lost: datetime, found: datetime) -> float:
        # SQLite can return legacy timestamps without timezone info, while newer
        # API submissions include an explicit UTC offset. Treat naive values as
        # UTC (the app's persisted timestamp convention) before comparing them.
        lost_utc = lost.replace(tzinfo=timezone.utc) if lost.tzinfo is None else lost.astimezone(timezone.utc)
        found_utc = found.replace(tzinfo=timezone.utc) if found.tzinfo is None else found.astimezone(timezone.utc)
        hours = abs((lost_utc - found_utc).total_seconds()) / 3600
        return max(0.0, 1.0 - min(hours, 168) / 168)

    def _score(self, lost: Item, found: Item) -> MatchCandidate:
        category_score = float(bool(lost.category and lost.category == found.category))
        color_score = float(bool(lost.color and lost.color == found.color))
        text_lost = self._text_tokens(lost)
        text_found = self._text_tokens(found)
        text_score = len(text_lost & text_found) / max(1, len(text_lost | text_found))
        location_score = float(
            lost.location.strip().lower() == found.location.strip().lower()
        )
        time_score = self._time_score(lost.occurred_at, found.occurred_at)
        school_score = float(lost.item_school_id == found.item_school_id)

        final_score = (
            category_score * 0.20
            + color_score * 0.10
            + text_score * 0.25
            + location_score * 0.20
            + time_score * 0.15
            + school_score * 0.10
        )
        explanation: list[str] = []
        if school_score:
            explanation.append("高校范围一致")
        if category_score:
            explanation.append("物品类别一致")
        if color_score:
            explanation.append("颜色一致")
        if location_score:
            explanation.append("地点一致")
        if time_score >= 0.8:
            explanation.append("丢失与拾取时间接近")

        return MatchCandidate(
            lost_item_id=lost.id,
            found_item_id=found.id,
            final_score=round(final_score, 4),
            score_breakdown={
                "category": category_score,
                "color": color_score,
                "text": round(text_score, 4),
                "location": location_score,
                "time": round(time_score, 4),
                "school": school_score,
            },
            explanation=explanation,
            needs_ai_review=0.55 <= final_score < 0.9,
        )

    async def matches_for(self, item_id: UUID) -> list[MatchCandidate]:
        source = self.repository.get(item_id)
        if not source:
            return []

        if source.item_type == ItemType.LOST:
            lost = source
            candidates = [
                item
                for item in self.repository.list()
                if item.item_type == ItemType.FOUND
                and item.status == "active"
                and self._scope_allowed(lost, item)
            ]
        else:
            found = source
            candidates = [
                item
                for item in self.repository.list()
                if item.item_type == ItemType.LOST
                and item.status == "active"
                and self._scope_allowed(item, found)
            ]
            lost = None

        results: list[MatchCandidate] = []
        for candidate in candidates:
            current = self._score(lost, candidate) if lost else self._score(candidate, source)
            if current.final_score >= 0.45:
                results.append(current)

        results.sort(key=lambda item: item.final_score, reverse=True)
        # Use vision only to review a few plausible pairs, avoiding a paid model
        # call for every item in the campus feed. Rule scores remain available
        # when images or the provider are unavailable.
        if self.vision.enabled:
            by_id = {item.id: item for item in self.repository.list()}
            reviewed = 0
            for result in results:
                if reviewed >= 3:
                    break
                if result.final_score < 0.55:
                    continue
                lost_item = by_id.get(result.lost_item_id)
                found_item = by_id.get(result.found_item_id)
                if not lost_item or not found_item or not lost_item.image_url or not found_item.image_url:
                    continue
                reviewed += 1
                try:
                    pair_key = (lost_item.id, found_item.id)
                    cached = self._ai_comparison_cache.get(pair_key)
                    if cached:
                        ai_score, ai_reasons = cached
                    else:
                        ai_score, ai_reasons = await self.vision.compare(lost_item, found_item)
                        self._ai_comparison_cache[pair_key] = (ai_score, ai_reasons[:5])
                    result.ai_score = round(ai_score, 4)
                    result.ai_reasons = ai_reasons[:5]
                    result.explanation.append("已完成 AI 图片复核")
                    result.final_score = round(result.final_score * 0.7 + ai_score * 0.3, 4)
                    result.needs_ai_review = 0.55 <= result.final_score < 0.9
                except Exception:
                    # Keep the deterministic result; a transient AI failure
                    # must not prevent users from seeing the candidate.
                    continue
            results.sort(key=lambda item: item.final_score, reverse=True)
        return results[:10]
