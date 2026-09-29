import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { fileIo } from '@kit.CoreFileKit';
import { ItemSummary, ItemType, LocalAnalysis, LocalChatMessage } from '../domain/Item';
import { ApiAnalysis, ApiChatMessage, ApiChatThread, ApiItem, ApiMatch, ShiguangApiClient } from './ApiClient';

export interface LocalItem extends ItemSummary {
  description: string;
  schoolId: string;
  publisherId: string;
  scopeMode: string;
  occurredAt: string;
}

export interface LocalInboxThread {
  id: string;
  participantId: string;
  item: LocalItem;
}

export interface LocalItemInput {
  title: string;
  description: string;
  category: string;
  color: string;
  location: string;
  type: ItemType;
  schoolId: string;
  scopeMode: string;
}

export interface LocalMatch {
  item: LocalItem;
  score: number;
  explanation: string[];
  aiScore?: number;
  aiReasons?: string[];
}

interface LocalScore {
  value: number;
  explanation: string[];
}

interface LocalState {
  version: number;
  items: LocalItem[];
  chats: Record<string, LocalChatMessage[]>;
  clientId?: string;
  remoteItems?: LocalItem[];
}

const STATE_KEY: string = 'state.v1';
const MAX_IMAGE_BYTES: number = 10 * 1024 * 1024;

/** App内本地数据服务：首次启动创建本地存储，所有数据只留在当前设备。 */
class LocalAppServiceImpl {
  private api: ShiguangApiClient = new ShiguangApiClient();
  private store?: preferences.Preferences;
  private initTask?: Promise<void>;
  private items: LocalItem[] = [];
  private remoteItems: LocalItem[] = [];
  private chats: Record<string, LocalChatMessage[]> = {};
  private clientId: string = '';
  private remoteAvailable: boolean = false;
  private aiAvailable: boolean = false;

  async initialize(context: common.UIAbilityContext): Promise<void> {
    if (this.store) {
      return;
    }
    if (!this.initTask) {
      this.initTask = (async () => {
        const store = await preferences.getPreferences(context, 'shiguang-local-data');
        const saved = await store.get(STATE_KEY, '') as string;
        if (saved) {
          try {
            const decoded = JSON.parse(saved) as LocalState;
            this.items = Array.isArray(decoded.items) ? decoded.items : [];
            this.remoteItems = Array.isArray(decoded.remoteItems) ? decoded.remoteItems : [];
            this.chats = decoded.chats ?? {};
            this.clientId = decoded.clientId ?? '';
          } catch (error) {
            this.items = [];
            this.remoteItems = [];
            this.chats = {};
          }
        }
        this.store = store;
        if (!this.clientId) {
          this.clientId = `student-${Date.now()}-${Math.floor(Math.random() * 1000000)}`;
          await this.persist();
        }
        try {
          const health = await this.api.health();
          this.remoteAvailable = health.status === 'ok';
          this.aiAvailable = this.remoteAvailable && health.ai_enabled;
        } catch (error) {
          this.remoteAvailable = false;
          this.aiAvailable = false;
        }
      })();
    }
    await this.initTask;
  }

  async listItems(schoolId?: string, includeOtherSchools: boolean = false): Promise<LocalItem[]> {
    await this.ensureInitialized();
    if (!this.remoteAvailable) {
      await this.refreshHealth();
    }
    if (this.remoteAvailable) {
      try {
        const remote = await this.api.listItems(includeOtherSchools ? undefined : schoolId);
        this.remoteItems = remote.map((item: ApiItem) => this.fromApiItem(item));
        await this.persist();
      } catch (error) {
        this.remoteAvailable = false;
        this.aiAvailable = false;
        this.aiAvailable = false;
      }
    }
    const visible = this.remoteAvailable ? this.remoteItems : [...this.remoteItems, ...this.items];
    const filtered = visible.filter((item: LocalItem) =>
      !schoolId || includeOtherSchools || item.schoolId === schoolId
    );
    for (const item of this.items) {
      if (!item.serverSynced && (!schoolId || includeOtherSchools || item.schoolId === schoolId) &&
        !filtered.some((existing: LocalItem) => existing.id === item.id)) {
        filtered.push(item);
      }
    }
    return filtered;
  }

  async createItem(input: LocalItemInput, imageUri: string, context: common.UIAbilityContext): Promise<LocalItem> {
    await this.ensureInitialized();
    let savedImageUri: string = '';
    if (imageUri) {
      savedImageUri = await this.copyImageToAppStorage(imageUri, context);
    }
    const occurredAt = new Date().toISOString();
    const id = `item-${Date.now()}-${Math.floor(Math.random() * 100000)}`;
    if (this.remoteAvailable) {
      try {
        const remoteImageUrl = savedImageUri ? await this.api.uploadImage(savedImageUri) : undefined;
        const created = await this.api.createItem({
          publisher_id: this.clientId,
          user_school_id: input.schoolId,
          item_school_id: input.schoolId,
          location: input.location,
          item_type: input.type,
          title: input.title,
          description: input.description,
          category: input.category,
          color: input.color,
          occurred_at: occurredAt,
          scope_mode: input.scopeMode,
          image_url: remoteImageUrl
        });
        const remoteItem = this.fromApiItem(created);
        this.remoteItems = [remoteItem, ...this.remoteItems.filter((item: LocalItem) => item.id !== remoteItem.id)];
        await this.persist();
        return remoteItem;
      } catch (error) {
        this.remoteAvailable = false;
        this.aiAvailable = false;
      }
    }
    const item: LocalItem = {
      id,
      title: input.title,
      description: input.description,
      type: input.type,
      publisherId: this.clientId,
      category: input.category,
      color: input.color,
      location: input.location,
      schoolId: input.schoolId,
      scopeMode: input.scopeMode,
      occurredAt,
      timeLabel: this.formatTime(occurredAt),
      status: input.type === ItemType.LOST ? '寻找中' : '等待认领',
      imageUri: savedImageUri || undefined,
      serverSynced: false
    };
    this.items = [item, ...this.items];
    await this.persist();
    return item;
  }

  async findMatches(itemId: string, includeOtherSchools: boolean = false): Promise<LocalMatch[]> {
    await this.ensureInitialized();
    const remoteSource = this.remoteItems.find((item: LocalItem) => item.id === itemId);
    if (remoteSource && this.remoteAvailable) {
      try {
        const apiMatches = await this.api.getMatches(itemId);
        const results: LocalMatch[] = [];
        for (const candidate of apiMatches) {
          const candidateId = remoteSource.type === ItemType.LOST
            ? candidate.found_item_id : candidate.lost_item_id;
          const matchedItem = this.remoteItems.find((item: LocalItem) => item.id === candidateId);
          if (matchedItem) {
            results.push({
              item: matchedItem,
              score: candidate.final_score,
              explanation: candidate.explanation,
              aiScore: candidate.ai_score,
              aiReasons: candidate.ai_reasons
            });
          }
        }
        results.sort((a: LocalMatch, b: LocalMatch) => b.score - a.score);
        return results.slice(0, 3);
      } catch (error) {
        this.remoteAvailable = false;
        this.aiAvailable = false;
      }
    }
    const source = this.items.find((item: LocalItem) => item.id === itemId);
    const localSource = source ?? remoteSource;
    if (!localSource) {
      return [];
    }
    const results: LocalMatch[] = [];
    const candidates = [...this.remoteItems, ...this.items];
    for (const candidate of candidates) {
      if (candidate.id === localSource.id || candidate.type === localSource.type) {
        continue;
      }
      const lost = localSource.type === ItemType.LOST ? localSource : candidate;
      const found = localSource.type === ItemType.FOUND ? localSource : candidate;
      const sameSchool = lost.schoolId === found.schoolId;
      if (!sameSchool && !includeOtherSchools && lost.scopeMode !== 'cross_school') {
        continue;
      }
      const score = this.score(lost, found);
      if (score.value >= 0.35) {
        results.push({ item: candidate, score: score.value, explanation: score.explanation });
      }
    }
    results.sort((a: LocalMatch, b: LocalMatch) => b.score - a.score);
    return results.slice(0, 3);
  }

  async openChat(itemId: string): Promise<string> {
    await this.ensureInitialized();
    if (this.remoteAvailable && this.remoteItems.some((item: LocalItem) => item.id === itemId)) {
      try {
        const thread = await this.api.openChat(itemId, this.clientId);
        return thread.id;
      } catch (error) {
        this.remoteAvailable = false;
        this.aiAvailable = false;
      }
    }
    return `local-${itemId}`;
  }

  async listInbox(): Promise<LocalInboxThread[]> {
    await this.ensureInitialized();
    if (!this.remoteAvailable) {
      await this.refreshHealth();
    }
    if (!this.remoteAvailable) {
      return [];
    }
    try {
      const threads: ApiChatThread[] = await this.api.listInbox(this.clientId);
      const items = await this.api.listItems();
      this.remoteItems = items.map((item: ApiItem) => this.fromApiItem(item));
      await this.persist();
      const entries: LocalInboxThread[] = [];
      for (const thread of threads) {
        const item = this.remoteItems.find((current: LocalItem) => current.id === thread.item_id);
        if (item) {
          entries.push({ id: thread.id, participantId: thread.participant_id, item: item });
        }
      }
      return entries;
    } catch (error) {
      this.remoteAvailable = false;
      this.aiAvailable = false;
      return [];
    }
  }

  async getMessages(chatId: string): Promise<LocalChatMessage[]> {
    await this.ensureInitialized();
    if (this.remoteAvailable && !chatId.startsWith('local-')) {
      try {
        const messages = await this.api.listMessages(chatId);
        return messages.map((message: ApiChatMessage) => this.fromApiMessage(message));
      } catch (error) {
        this.remoteAvailable = false;
      }
    }
    return [...(this.chats[chatId] ?? [])];
  }

  async sendMessage(chatId: string, body: string): Promise<LocalChatMessage> {
    await this.ensureInitialized();
    if (this.remoteAvailable && !chatId.startsWith('local-')) {
      try {
        const message = await this.api.sendMessage(chatId, this.clientId, body);
        return this.fromApiMessage(message);
      } catch (error) {
        this.remoteAvailable = false;
      }
    }
    const message: LocalChatMessage = {
      id: `message-${Date.now()}-${Math.floor(Math.random() * 100000)}`,
      chat_id: chatId,
      item_id: chatId.replace('local-', ''),
      sender_id: this.clientId,
      body,
      created_at: new Date().toISOString()
    };
    const existing = this.chats[chatId] ?? [];
    this.chats[chatId] = [...existing, message];
    await this.persist();
    return message;
  }

  currentUserId(): string {
    return this.clientId;
  }

  isServerAvailable(): boolean {
    return this.remoteAvailable;
  }

  isAiAvailable(): boolean {
    return this.aiAvailable;
  }

  /**
   * 当前无端侧视觉模型时，只汇总用户填写的结构化字段与文字关键词。
   * 不读取图片内容，不将规则提取伪称为AI图像识别。
   */
  analyzeLocalClues(item: LocalItem): LocalAnalysis {
    const text = `${item.title} ${item.description} ${item.category} ${item.color}`.trim();
    const features = this.extractTerms(text).slice(0, 6);
    return {
      category: item.category && item.category !== '其他' ? item.category : undefined,
      color: item.color && item.color !== '未填写' ? item.color : undefined,
      visible_text: [],
      sensitive_text: [],
      features,
      source: 'local-fallback'
    };
  }

  async analyzeItem(itemId: string): Promise<LocalAnalysis> {
    await this.ensureInitialized();
    const item = this.remoteItems.find((current: LocalItem) => current.id === itemId) ??
      this.items.find((current: LocalItem) => current.id === itemId);
    if (!item) {
      throw new Error('未找到该条失物信息');
    }
    if (this.remoteAvailable && this.aiAvailable && item.serverSynced && item.imageUri) {
      try {
        const analysis: ApiAnalysis = await this.api.analyzeItem(itemId);
        const result: LocalAnalysis = {
          brand: analysis.brand,
          model: analysis.model,
          category: analysis.category,
          color: analysis.color,
          visible_text: analysis.visible_text ?? [],
          sensitive_text: analysis.sensitive_text ?? [],
          features: analysis.features ?? [],
          confidence: analysis.confidence,
          source: 'deepseek-vision'
        };
        await this.updateAnalysis(itemId, result);
        return result;
      } catch (error) {
        // Analysis-provider errors should not make a healthy API look offline.
        await this.refreshHealth();
      }
    }
    const fallback = this.analyzeLocalClues(item);
    await this.updateAnalysis(itemId, fallback);
    return fallback;
  }

  async updateAnalysis(itemId: string, analysis: LocalAnalysis): Promise<void> {
    await this.ensureInitialized();
    this.items = this.items.map((item: LocalItem) => this.withAnalysis(item, itemId, analysis));
    this.remoteItems = this.remoteItems.map((item: LocalItem) => this.withAnalysis(item, itemId, analysis));
    await this.persist();
  }

  private withAnalysis(item: LocalItem, itemId: string, analysis: LocalAnalysis): LocalItem {
    if (item.id !== itemId) {
      return item;
    }
    return {
      id: item.id,
      title: item.title,
      description: item.description,
      type: item.type,
      category: analysis.category || item.category,
      color: analysis.color || item.color,
      location: item.location,
      schoolId: item.schoolId,
      publisherId: item.publisherId,
      scopeMode: item.scopeMode,
      occurredAt: item.occurredAt,
      timeLabel: item.timeLabel,
      status: item.status,
      imageUri: item.imageUri,
      aiFeatures: analysis.features,
      aiConfidence: analysis.confidence,
      serverSynced: item.serverSynced
    };
  }

  private fromApiItem(api: ApiItem): LocalItem {
    const analysis = api.ai_features;
    const features: string[] = [];
    if (analysis) {
      for (const feature of [...(analysis.features ?? []), ...(analysis.visible_text ?? [])]) {
        if (feature && !features.includes(feature)) {
          features.push(feature);
        }
      }
    }
    return {
      id: api.id,
      title: api.title,
      description: api.description ?? '',
      type: api.item_type === 'found' ? ItemType.FOUND : ItemType.LOST,
      category: api.category ?? '其他',
      color: api.color ?? '未填写',
      location: api.location,
      schoolId: api.item_school_id,
      publisherId: api.publisher_id,
      scopeMode: api.scope_mode,
      occurredAt: api.occurred_at,
      timeLabel: this.formatTime(api.occurred_at),
      status: api.status === 'matched' || api.status === 'returned'
        ? '已匹配' : api.item_type === 'lost' ? '寻找中' : '等待认领',
      imageUri: this.api.assetUrl(api.image_url) || undefined,
      aiFeatures: analysis ? features : undefined,
      aiConfidence: analysis?.confidence,
      serverSynced: true
    };
  }

  private fromApiMessage(api: ApiChatMessage): LocalChatMessage {
    return {
      id: api.id,
      chat_id: api.chat_id,
      item_id: api.item_id,
      sender_id: api.sender_id,
      body: api.body,
      created_at: api.created_at
    };
  }

  private async ensureInitialized(): Promise<void> {
    if (!this.store) {
      throw new Error('本地数据尚未初始化');
    }
  }

  private async refreshHealth(): Promise<void> {
    try {
      const health = await this.api.health();
      this.remoteAvailable = health.status === 'ok';
      this.aiAvailable = this.remoteAvailable && health.ai_enabled;
    } catch (error) {
      this.remoteAvailable = false;
      this.aiAvailable = false;
    }
  }

  private async persist(): Promise<void> {
    if (!this.store) {
      throw new Error('本地数据尚未初始化');
    }
    const state: LocalState = {
      version: 1,
      items: this.items,
      remoteItems: this.remoteItems,
      chats: this.chats,
      clientId: this.clientId
    };
    await this.store.put(STATE_KEY, JSON.stringify(state));
    await this.store.flush();
  }

  private async copyImageToAppStorage(sourceUri: string, context: common.UIAbilityContext): Promise<string> {
    const source = fileIo.openSync(sourceUri, fileIo.OpenMode.READ_ONLY);
    let destination: fileIo.File | undefined;
    try {
      const stat = fileIo.statSync(source.fd);
      if (stat.size <= 0 || stat.size > MAX_IMAGE_BYTES) {
        throw new Error('图片大小必须在 10 MB 以内');
      }
      const buffer = new ArrayBuffer(stat.size);
      const bytesRead = fileIo.readSync(source.fd, buffer);
      if (bytesRead !== stat.size) {
        throw new Error('图片读取不完整');
      }
      const extension = this.imageExtension(sourceUri);
      const path = `${context.filesDir}/item-${Date.now()}-${Math.floor(Math.random() * 100000)}.${extension}`;
      destination = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      const bytesWritten = fileIo.writeSync(destination.fd, buffer);
      if (bytesWritten !== stat.size) {
        throw new Error('图片保存不完整');
      }
      return `file://${path}`;
    } finally {
      if (destination) {
        fileIo.closeSync(destination.fd);
      }
      fileIo.closeSync(source.fd);
    }
  }

  private imageExtension(sourceUri: string): string {
    const cleanUri = sourceUri.toLowerCase().split('?')[0];
    if (cleanUri.endsWith('.png')) {
      return 'png';
    }
    if (cleanUri.endsWith('.webp')) {
      return 'webp';
    }
    if (cleanUri.endsWith('.gif')) {
      return 'gif';
    }
    return 'jpg';
  }

  private score(lost: LocalItem, found: LocalItem): LocalScore {
    const category = Number(Boolean(lost.category && lost.category === found.category));
    const color = Number(Boolean(lost.color && lost.color !== '未填写' && lost.color === found.color));
    const lostTokens = this.extractTerms(`${lost.title} ${lost.description} ${lost.category} ${lost.color}`);
    const foundTokens = this.extractTerms(`${found.title} ${found.description} ${found.category} ${found.color}`);
    const intersection = lostTokens.filter((token: string) => foundTokens.includes(token)).length;
    const unionTokens: string[] = [];
    for (const token of lostTokens) {
      if (!unionTokens.includes(token)) unionTokens.push(token);
    }
    for (const token of foundTokens) {
      if (!unionTokens.includes(token)) unionTokens.push(token);
    }
    const union = unionTokens.length;
    const text = intersection / Math.max(1, union);
    const location = Number(Boolean(lost.location && lost.location.trim().toLowerCase() === found.location.trim().toLowerCase()));
    const lostTime = Date.parse(lost.occurredAt);
    const foundTime = Date.parse(found.occurredAt);
    const hours = Number.isFinite(lostTime) && Number.isFinite(foundTime)
      ? Math.abs(lostTime - foundTime) / 3600000
      : 168;
    const time = Math.max(0, 1 - Math.min(hours, 168) / 168);
    const school = Number(lost.schoolId === found.schoolId);
    const value = category * 0.20 + color * 0.10 + text * 0.25 + location * 0.20 + time * 0.15 + school * 0.10;
    const explanation: string[] = [];
    if (school) explanation.push('高校范围一致');
    if (category) explanation.push('类别一致');
    if (color) explanation.push('颜色一致');
    if (location) explanation.push('地点一致');
    if (time >= 0.8) explanation.push('时间接近');
    if (text >= 0.15) explanation.push('描述关键词相似');
    return { value: Math.round(value * 10000) / 10000, explanation };
  }

  private extractTerms(value: string): string[] {
    const normalized = value.toLowerCase();
    const terms: string[] = [];
    const latin = normalized.match(/[a-z0-9]+/g) ?? [];
    for (const term of latin) {
      terms.push(term);
    }
    const chinese = normalized.match(/[\u4e00-\u9fff]/g) ?? [];
    for (const character of chinese) {
      terms.push(character);
    }
    for (let index = 0; index < chinese.length - 1; index++) {
      terms.push(chinese[index] + chinese[index + 1]);
    }
    const unique: string[] = [];
    for (const term of terms) {
      if (term.length > 1 && !unique.includes(term)) {
        unique.push(term);
      }
    }
    return unique;
  }

  private formatTime(value: string): string {
    const date = new Date(value);
    const month = `${date.getMonth() + 1}`.padStart(2, '0');
    const day = `${date.getDate()}`.padStart(2, '0');
    const hours = `${date.getHours()}`.padStart(2, '0');
    const minutes = `${date.getMinutes()}`.padStart(2, '0');
    return `${month}-${day} ${hours}:${minutes}`;
  }
}

export const LocalAppService = new LocalAppServiceImpl();
