import http from '@ohos.net.http';
import fileIo from '@ohos.file.fs';

// Set this to a backend address reachable from the target device before testing.
// Keep provider API credentials on the server; never embed them in the HAP.
export const API_BASE_URL: string = 'http://127.0.0.1:8000';

export interface ApiAnalysis {
  category?: string;
  color?: string;
  brand?: string;
  model?: string;
  visible_text: string[];
  sensitive_text: string[];
  features: string[];
  confidence: number;
}

export interface ApiHealth {
  status: string;
  ai_enabled: boolean;
}

export interface ApiItem {
  id: string;
  publisher_id: string;
  user_school_id: string;
  item_school_id: string;
  campus_id?: string;
  location: string;
  item_type: string;
  title: string;
  description: string;
  category?: string;
  color?: string;
  image_url?: string;
  occurred_at: string;
  scope_mode: string;
  status: string;
  ai_features?: ApiAnalysis;
  created_at: string;
}

export interface ApiMatch {
  lost_item_id: string;
  found_item_id: string;
  final_score: number;
  score_breakdown: Record<string, number>;
  explanation: string[];
  needs_ai_review: boolean;
  ai_score?: number;
  ai_reasons?: string[];
}

export interface ApiChatThread {
  id: string;
  item_id: string;
  participant_id: string;
  created_at: string;
}

export interface ApiChatMessage {
  id: string;
  chat_id: string;
  item_id: string;
  sender_id: string;
  body: string;
  created_at: string;
}

interface ApiUploadResponse {
  url: string;
  filename: string;
  content_type: string;
}

export interface ApiCreateItem {
  publisher_id: string;
  user_school_id: string;
  item_school_id: string;
  location: string;
  item_type: string;
  title: string;
  description: string;
  category: string;
  color: string;
  occurred_at: string;
  scope_mode: string;
  image_url?: string;
}

export class ShiguangApiClient {
  private async request<T>(path: string, method: http.RequestMethod = http.RequestMethod.GET,
    body?: string): Promise<T> {
    const request = http.createHttp();
    try {
      const response = await request.request(`${API_BASE_URL}${path}`, {
        method: method,
        header: { 'Content-Type': 'application/json' },
        extraData: body,
        connectTimeout: 10000,
        readTimeout: 60000,
        expectDataType: http.HttpDataType.STRING
      });
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`服务器请求失败（${response.responseCode}）`);
      }
      return JSON.parse(String(response.result)) as T;
    } finally {
      request.destroy();
    }
  }

  async health(): Promise<ApiHealth> {
    return this.request<ApiHealth>('/api/v1/health');
  }

  async listItems(schoolId?: string): Promise<ApiItem[]> {
    const query = schoolId ? `?school_id=${encodeURIComponent(schoolId)}` : '';
    return this.request<ApiItem[]>(`/api/v1/items${query}`);
  }

  async createItem(payload: ApiCreateItem): Promise<ApiItem> {
    return this.request<ApiItem>('/api/v1/items', http.RequestMethod.POST, JSON.stringify(payload));
  }

  async analyzeItem(itemId: string): Promise<ApiAnalysis> {
    return this.request<ApiAnalysis>(`/api/v1/items/${itemId}/analyze`, http.RequestMethod.POST);
  }

  async getMatches(itemId: string): Promise<ApiMatch[]> {
    return this.request<ApiMatch[]>(`/api/v1/items/${itemId}/matches`);
  }

  async uploadImage(fileUri: string): Promise<string> {
    const file = fileIo.openSync(fileUri, fileIo.OpenMode.READ_ONLY);
    try {
      const stat = fileIo.statSync(file.fd);
      if (stat.size <= 0 || stat.size > 10 * 1024 * 1024) {
        throw new Error('图片大小必须在 10 MB 以内');
      }
      const buffer = new ArrayBuffer(stat.size);
      const readBytes = fileIo.readSync(file.fd, buffer);
      if (readBytes !== stat.size) {
        throw new Error('图片读取不完整');
      }
      const request = http.createHttp();
      try {
        const response = await request.request(`${API_BASE_URL}/api/v1/uploads/raw`, {
          method: http.RequestMethod.POST,
          header: { 'Content-Type': this.imageContentType(fileUri) },
          extraData: buffer,
          connectTimeout: 15000,
          readTimeout: 30000,
          expectDataType: http.HttpDataType.STRING
        });
        if (response.responseCode < 200 || response.responseCode >= 300) {
          throw new Error(`图片上传失败（${response.responseCode}）`);
        }
        const result = JSON.parse(String(response.result)) as ApiUploadResponse;
        return this.assetUrl(result.url);
      } finally {
        request.destroy();
      }
    } finally {
      fileIo.closeSync(file.fd);
    }
  }

  async openChat(itemId: string, participantId: string): Promise<ApiChatThread> {
    return this.request<ApiChatThread>('/api/v1/chats', http.RequestMethod.POST,
      JSON.stringify({ item_id: itemId, participant_id: participantId }));
  }

  async listInbox(ownerId: string): Promise<ApiChatThread[]> {
    return this.request<ApiChatThread[]>(`/api/v1/chats/inbox?owner_id=${encodeURIComponent(ownerId)}`);
  }

  async listMessages(chatId: string): Promise<ApiChatMessage[]> {
    return this.request<ApiChatMessage[]>(`/api/v1/chats/${chatId}/messages`);
  }

  async sendMessage(chatId: string, senderId: string, body: string): Promise<ApiChatMessage> {
    return this.request<ApiChatMessage>(`/api/v1/chats/${chatId}/messages`, http.RequestMethod.POST,
      JSON.stringify({ sender_id: senderId, body: body }));
  }

  assetUrl(path?: string): string {
    if (!path) {
      return '';
    }
    return path.startsWith('http') ? path : `${API_BASE_URL}${path}`;
  }

  private imageContentType(fileUri: string): string {
    const lower = fileUri.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }
}
