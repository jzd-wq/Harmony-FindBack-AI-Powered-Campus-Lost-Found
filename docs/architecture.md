# 拾光失物：可扩展架构设计

## 1. 产品边界

拾光失物面向高校学生，围绕“发布拾获物—发布丢失物—AI 提取特征—本校匹配—主动提醒—安全认领”建立闭环。

默认只在同一所高校内匹配。用户主动打开“跨校匹配”后，系统才允许扩大候选范围。

`userSchoolId` 表示用户所属高校，`itemSchoolId` 表示物品丢失或拾取所在高校，两者必须分开保存。

## 2. 总体架构

```text
HarmonyOS App
  ├─ ArkUI 页面
  ├─ Domain 用例
  ├─ Repository 数据接口
  ├─ 本地数据库
  ├─ HarmonyOS 通知 / 服务卡片 / 分布式协同
  └─ HTTP API
          │
          ▼
FastAPI 模块化后端
  ├─ Identity / School
  ├─ Item / Media
  ├─ AI Analysis
  ├─ Matching
  ├─ Claim
  ├─ Notification
  ├─ Moderation / Audit
  └─ Administration
          │
          ├─ PostgreSQL / SQLite
          ├─ Object Storage
          ├─ Task Queue
          └─ AI Provider Adapter
                  └─ DeepSeek-V4.1-Flash
```

## 3. 架构原则

1. 客户端不直接调用 DeepSeek，API Key 只保存在后端。
2. AI 只负责图像理解、文字提取和候选复核；最终匹配由可解释的规则引擎决定。
3. 后端采用模块化单体，比赛版部署简单，后续可以拆分 AI、匹配和通知服务。
4. 所有关键策略通过接口和配置注入，避免把高校范围、模型和匹配权重写死。
5. AI 分析结果记录模型版本、提示词版本和结构版本，保证结果可追溯。

## 4. 客户端分层

```text
pages / components
        ↓
viewmodels
        ↓
domain usecases
        ↓
repository interfaces
        ↓
remote / local / HarmonyOS adapters
```

页面不直接访问网络和数据库。后续更换后端、增加离线模式或接入分布式数据时，不需要重写页面。

## 5. AI 与匹配流程

```text
创建物品
  ↓
AI 提取类别、颜色、品牌、文字、可见特征
  ↓
敏感信息识别与公开内容打码
  ↓
同校 / 同校区 / 时间 / 地点硬过滤
  ↓
规则评分
  ↓
DeepSeek 对少量高候选进行二次视觉复核
  ↓
生成匹配解释
  ↓
按阈值发送站内通知和鸿蒙通知
```

## 6. 可替换接口

```text
VisionAnalysisProvider
  ├─ DeepSeekVisionProvider
  ├─ HarmonyVisionProvider
  └─ LocalVisionProvider

MatchingStrategy
  ├─ WeightedFeatureMatching
  ├─ VectorMatching
  └─ HybridMatching

ScopePolicy
  ├─ SameSchoolPolicy
  ├─ SameCampusPolicy
  └─ CrossSchoolPolicy

NotificationProvider
  ├─ InAppNotificationProvider
  ├─ HarmonyPushProvider
  └─ EmailNotificationProvider
```

## 7. 分阶段实现

### 比赛版

- ArkTS + ArkUI 原生客户端
- FastAPI
- SQLite
- 本地图片目录
- DeepSeek API
- 规则匹配
- 站内通知
- 服务卡片或分布式协同演示

### 可运营版

- PostgreSQL
- 对象存储
- Redis 任务队列
- 高校身份认证
- pgvector 图像检索
- 鸿蒙 Push
- 校方管理员和审核台

### 平台版

- 多高校租户
- 校园失物中心
- 跨校匹配授权
- 运营数据分析
- 多模型路由
- 风险识别和反欺诈
