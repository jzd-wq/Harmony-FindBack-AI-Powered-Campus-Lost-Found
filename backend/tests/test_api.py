import os
import unittest

os.environ["APP_ENV"] = "test"
os.environ["DATABASE_URL"] = "sqlite:///:memory:"

from fastapi.testclient import TestClient

from app.main import app


class ShiguangApiTest(unittest.TestCase):
    def setUp(self) -> None:
        self.client = TestClient(app)

    def test_health_and_schools(self) -> None:
        self.assertEqual(self.client.get('/api/v1/health').status_code, 200)
        self.assertEqual(len(self.client.get('/api/v1/schools').json()), 2)

    def test_same_school_scope(self) -> None:
        lost = self.client.post('/api/v1/items', json={
            'user_school_id': 'school-a',
            'item_school_id': 'school-a',
            'location': '图书馆',
            'item_type': 'lost',
            'title': '蓝色校园卡',
            'description': '透明卡套',
            'category': '校园卡',
            'color': '蓝色',
            'occurred_at': '2026-09-21T14:00:00',
            'scope_mode': 'same_school',
        }).json()

        self.client.post('/api/v1/items', json={
            'user_school_id': 'school-b',
            'item_school_id': 'school-b',
            'location': '图书馆',
            'item_type': 'found',
            'title': '蓝色校园卡',
            'description': '透明卡套',
            'category': '校园卡',
            'color': '蓝色',
            'occurred_at': '2026-09-21T14:20:00',
            'scope_mode': 'same_school',
        })

        matches = self.client.get(
            f"/api/v1/items/{lost['id']}/matches"
        ).json()
        self.assertEqual(matches, [])

    def test_match_candidates_are_scored_with_legacy_and_utc_timestamps(self) -> None:
        lost = self.client.post('/api/v1/items', json={
            'user_school_id': 'school-a',
            'item_school_id': 'school-a',
            'location': '图书馆一楼',
            'item_type': 'lost',
            'title': '黑色头戴式耳机',
            'description': '耳罩外侧有圆形金属网格',
            'category': '头戴式耳机',
            'color': '黑色',
            'occurred_at': '2026-09-24T05:00:00Z',
            'scope_mode': 'same_school',
        }).json()
        found = self.client.post('/api/v1/items', json={
            'user_school_id': 'school-a',
            'item_school_id': 'school-a',
            'location': '图书馆一楼',
            'item_type': 'found',
            'title': '黑色头戴式耳机',
            'description': '耳罩外侧有圆形金属网格',
            'category': '头戴式耳机',
            'color': '黑色',
            'occurred_at': '2026-09-24T05:10:00',
            'scope_mode': 'same_school',
        }).json()

        response = self.client.get(f"/api/v1/items/{lost['id']}/matches")

        self.assertEqual(response.status_code, 200)
        candidate = next(
            match for match in response.json()
            if match['found_item_id'] == found['id']
        )
        self.assertGreater(candidate['final_score'], 0.8)
        self.assertIn('物品类别一致', candidate['explanation'])
        self.assertIn('颜色一致', candidate['explanation'])

    def test_cross_school_matches_require_explicit_opt_in(self) -> None:
        found = self.client.post('/api/v1/items', json={
            'user_school_id': 'school-b',
            'item_school_id': 'school-b',
            'location': '图书馆一楼',
            'item_type': 'found',
            'title': '蓝色校园卡',
            'description': '透明卡套，顶部有挂孔',
            'category': '校园卡',
            'color': '蓝色',
            'occurred_at': '2026-09-24T05:10:00',
            'scope_mode': 'same_school',
        }).json()

        def create_lost(scope_mode: str) -> dict:
            return self.client.post('/api/v1/items', json={
                'user_school_id': 'school-a',
                'item_school_id': 'school-a',
                'location': '图书馆一楼',
                'item_type': 'lost',
                'title': '蓝色校园卡',
                'description': '透明卡套，顶部有挂孔',
                'category': '校园卡',
                'color': '蓝色',
                'occurred_at': '2026-09-24T05:00:00Z',
                'scope_mode': scope_mode,
            }).json()

        same_school_only = create_lost('same_school')
        same_school_matches = self.client.get(
            f"/api/v1/items/{same_school_only['id']}/matches"
        ).json()
        self.assertFalse(any(
            match['found_item_id'] == found['id'] for match in same_school_matches
        ))

        cross_school_allowed = create_lost('cross_school')
        cross_school_matches = self.client.get(
            f"/api/v1/items/{cross_school_allowed['id']}/matches"
        ).json()
        self.assertTrue(any(
            match['found_item_id'] == found['id'] for match in cross_school_matches
        ))

    def test_analyze_rejects_items_without_images(self) -> None:
        item = self.client.post('/api/v1/items', json={
            'user_school_id': 'school-a',
            'item_school_id': 'school-a',
            'location': '图书馆',
            'item_type': 'lost',
            'title': '无图片测试线索',
            'occurred_at': '2026-09-24T05:00:00Z',
        }).json()

        response = self.client.post(f"/api/v1/items/{item['id']}/analyze")

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json()['detail'], 'image_url is required')

    def test_item_list_can_filter_by_school_or_include_all(self) -> None:
        school_a = self.client.post('/api/v1/items', json={
            'user_school_id': 'school-a',
            'item_school_id': 'school-a',
            'location': '高校A图书馆',
            'item_type': 'lost',
            'title': '范围测试A',
            'occurred_at': '2026-09-22T09:00:00',
        }).json()
        school_b = self.client.post('/api/v1/items', json={
            'user_school_id': 'school-b',
            'item_school_id': 'school-b',
            'location': '高校B图书馆',
            'item_type': 'found',
            'title': '范围测试B',
            'occurred_at': '2026-09-22T09:05:00',
        }).json()

        same_school_ids = {
            item['id'] for item in self.client.get('/api/v1/items?school_id=school-a').json()
        }
        all_school_ids = {
            item['id'] for item in self.client.get('/api/v1/items').json()
        }
        self.assertIn(school_a['id'], same_school_ids)
        self.assertNotIn(school_b['id'], same_school_ids)
        self.assertTrue({school_a['id'], school_b['id']}.issubset(all_school_ids))

    def test_upload_and_persisted_item_shape(self) -> None:
        response = self.client.post(
            "/api/v1/uploads",
            files={"file": ("card.png", b"not-a-real-png", "image/png")},
        )
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()["url"].startswith("/uploads/"))

        item = self.client.post(
            "/api/v1/items",
            json={
                "user_school_id": "school-a",
                "item_school_id": "school-a",
                "location": "食堂",
                "item_type": "lost",
                "title": "白色耳机",
                "occurred_at": "2026-09-21T14:00:00",
                "image_url": response.json()["url"],
            },
        )
        self.assertEqual(item.status_code, 200)
        fetched = self.client.get(f"/api/v1/items/{item.json()['id']}")
        self.assertEqual(fetched.status_code, 200)
        self.assertEqual(fetched.json()["image_url"], response.json()["url"])

    def test_raw_upload_for_native_client(self) -> None:
        response = self.client.post(
            "/api/v1/uploads/raw",
            content=b"native-image-bytes",
            headers={"content-type": "image/jpeg"},
        )
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()["url"].endswith(".jpg"))

    def test_chat_thread_and_messages(self) -> None:
        item = self.client.post('/api/v1/items', json={
            'publisher_id': 'owner-002',
            'user_school_id': 'school-b',
            'item_school_id': 'school-b',
            'location': '图书馆',
            'item_type': 'found',
            'title': '蓝色校园卡',
            'occurred_at': '2026-09-21T14:00:00',
        }).json()
        thread = self.client.post('/api/v1/chats', json={
            'item_id': item['id'],
            'participant_id': 'owner-001',
        })
        self.assertEqual(thread.status_code, 200)
        chat_id = thread.json()['id']

        sent = self.client.post(f'/api/v1/chats/{chat_id}/messages', json={
            'sender_id': 'owner-001',
            'body': '你好，请问校园卡是在图书馆捡到的吗？',
        })
        self.assertEqual(sent.status_code, 200)
        messages = self.client.get(f'/api/v1/chats/{chat_id}/messages')
        self.assertEqual(messages.status_code, 200)
        self.assertEqual(messages.json()[0]['body'], '你好，请问校园卡是在图书馆捡到的吗？')
        owner_threads = self.client.get('/api/v1/chats/inbox?owner_id=owner-002')
        unrelated_threads = self.client.get('/api/v1/chats/inbox?owner_id=someone-else')
        self.assertEqual([entry['id'] for entry in owner_threads.json()], [chat_id])
        self.assertEqual(unrelated_threads.json(), [])


if __name__ == '__main__':
    unittest.main()
