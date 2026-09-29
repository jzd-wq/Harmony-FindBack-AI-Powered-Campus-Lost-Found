export enum ItemType {
  LOST = 'lost',
  FOUND = 'found'
}

export interface ItemSummary {
  id: string;
  title: string;
  type: ItemType;
  category: string;
  color: string;
  location: string;
  timeLabel: string;
  description?: string;
  schoolId?: string;
  publisherId?: string;
  scopeMode?: string;
  occurredAt?: string;
  matchScore?: number;
  status: string;
  imageUri?: string;
  aiFeatures?: string[];
  aiConfidence?: number;
  serverSynced?: boolean;
}

export interface LocalChatMessage {
  id: string;
  chat_id: string;
  item_id: string;
  sender_id: string;
  body: string;
  created_at: string;
}

export interface LocalAnalysis {
  brand?: string;
  model?: string;
  category?: string;
  color?: string;
  visible_text: string[];
  sensitive_text: string[];
  features: string[];
  confidence?: number;
  source: 'deepseek-vision' | 'local-fallback';
}
