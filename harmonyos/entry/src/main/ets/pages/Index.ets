import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { LocalAppService, LocalInboxThread, LocalItem, LocalItemInput } from '../data/LocalAppService';
import { NotificationService } from '../data/NotificationService';
import { ItemSummary, ItemType, LocalAnalysis, LocalChatMessage } from '../domain/Item';

interface MatchSuggestion {
  item: ItemSummary;
  score: number;
  explanation: string[];
  aiScore?: number;
  aiReasons?: string[];
}

@Entry
@Component
struct Index {
  @State selectedSchool: string = '高校A';
  @State activeTab: number = 0;
  @State items: ItemSummary[] = [];
  @State chatInbox: LocalInboxThread[] = [];
  @State isScopePanelVisible: boolean = false;
  @State isPublishPanelVisible: boolean = false;
  @State isChatPanelVisible: boolean = false;
  @State publishType: ItemType = ItemType.LOST;
  @State crossSchoolEnabled: boolean = false;
  @State statusMessage: string = '正在连接服务并初始化数据…';
  @State formTitle: string = '';
  @State formCategory: string = '';
  @State formColor: string = '';
  @State formLocation: string = '';
  @State formDescription: string = '';
  @State selectedImageUri: string = '';
  @State chatTitle: string = '';
  @State chatItemId: string = '';
  @State chatId: string = '';
  @State chatMessages: LocalChatMessage[] = [];
  @State chatDraft: string = '';
  @State aiAnalysis: LocalAnalysis | null = null;
  @State aiAnalyzingItemId: string = '';
  @State aiStatusMessage: string = '';
  @State isPublishAiPanelVisible: boolean = false;
  @State isPublishAiWorking: boolean = false;
  @State matchScanComplete: boolean = false;
  @State publishAiMessage: string = '';
  @State matchSuggestions: MatchSuggestion[] = [];

  private notificationService: NotificationService = new NotificationService();

  private abilityContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  aboutToAppear(): void {
    this.loadItems();
  }

  private selectedSchoolId(): string {
    return 'wust';
  }

  async loadItems(): Promise<void> {
    try {
      await LocalAppService.initialize(this.abilityContext());
      this.items = await LocalAppService.listItems(
        this.crossSchoolEnabled ? undefined : this.selectedSchoolId(),
        this.crossSchoolEnabled
      );
      this.chatInbox = await LocalAppService.listInbox();
      this.statusMessage = LocalAppService.isServerAvailable()
        ? `服务已连接 · 已同步 ${this.items.length} 条线索`
        : `离线本机模式 · ${this.items.length} 条线索`;
    } catch (error) {
      this.items = [];
      this.statusMessage = '本机数据初始化失败，请重新打开应用';
    }
  }

  build() {
    Stack() {
      Column() {
        Scroll() {
          Column() {
            if (this.isChatPanelVisible) {
              this.chatContent()
            } else if (this.activeTab === 0) {
              this.homeContent()
            } else if (this.activeTab === 1) {
              this.publishContent()
            } else if (this.activeTab === 2) {
              this.noticeContent()
            } else {
              this.profileContent()
            }
          }
          .width('100%')
          .padding({ bottom: 20 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)

        this.bottomNavigation()
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))

      if (this.isPublishAiPanelVisible) {
        Column() {
          Blank()
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#990B1620')

        Column() {
          this.publishAiResultPanel()
        }
          .width('calc(100% - 36vp)')
          .align(Alignment.Center)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  homeContent() {
    this.header()
    this.heroBanner()
    this.scopeBanner()
    this.primaryActions()
    if (this.isPublishPanelVisible) {
      this.publishPanel()
    }
    this.matchIntro()
    this.itemList()
    if (this.aiAnalysis !== null) {
      this.aiAnalysisPanel()
    }
  }

  @Builder
  header() {
    Row() {
      Column() {
        Text('拾光失物')
          .fontSize(27)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text('让每一份遗失，都有回家的可能')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 4 })
        Text(this.statusMessage)
          .fontSize(10)
          .fontColor('#6B7280')
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)

      Blank()

      Text('通知')
        .fontSize(13)
        .fontColor('#3E7A62')
        .padding({ left: 13, right: 13, top: 8, bottom: 8 })
        .backgroundColor('#E4F4EA')
        .borderRadius(20)
        .onClick(() => {
          this.activeTab = 2;
        })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 20, bottom: 12 })
  }

  @Builder
  heroBanner() {
    Stack({ alignContent: Alignment.BottomStart }) {
      Image($r('app.media.campus_hero'))
        .width('100%')
        .height(178)
        .objectFit(ImageFit.Cover)
        .borderRadius(24)

      Column() {
        Text('你好，同学')
          .fontSize(23)
          .fontWeight(FontWeight.Bold)
          .fontColor('#214D3A')
        Text('让好物回到它的主人身边')
          .fontSize(13)
          .fontColor('#3E6B55')
          .margin({ top: 7 })
      }
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 20, bottom: 20 })
    }
    .width('calc(100% - 40vp)')
    .margin({ left: 20, right: 20 })
    .clip(true)
  }

  @Builder
  scopeBanner() {
    Row() {
      Row() {
        Text('范围')
          .fontSize(12)
          .fontColor('#3E7A62')
          .padding({ left: 7, right: 7, top: 4, bottom: 4 })
          .backgroundColor('#E4F4EA')
          .borderRadius(9)
        Text('高校A · ' + (this.crossSchoolEnabled ? '跨校匹配' : '本校匹配'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#2C5946')
          .margin({ left: 8 })
      }

      Blank()

      Text('查看')
        .fontSize(12)
        .fontColor('#57906F')
    }
    .width('calc(100% - 40vp)')
    .padding({ left: 16, right: 14, top: 13, bottom: 13 })
    .margin({ left: 20, right: 20, top: 12 })
    .backgroundColor('#FFFFFF')
    .borderRadius(18)
    .onClick(() => {
      this.isScopePanelVisible = !this.isScopePanelVisible;
    })

    if (this.isScopePanelVisible) {
      Row() {
        Text(LocalAppService.isServerAvailable() ? '信息发布后可同步给其他用户' : '服务未连接：信息只保存在本机')
          .fontSize(13)
          .fontColor('#3E7A62')
        Text(this.crossSchoolEnabled ? '关闭跨校匹配' : '开启跨校匹配')
          .fontSize(13)
          .fontColor('#6B7280')
          .margin({ left: 22 })
          .onClick(() => {
            this.crossSchoolEnabled = !this.crossSchoolEnabled;
            this.isScopePanelVisible = false;
            this.loadItems();
          })
      }
      .width('calc(100% - 40vp)')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .margin({ left: 20, right: 20, top: 7 })
      .backgroundColor('#F0F8F2')
      .borderRadius(14)
    }
  }

  @Builder
  primaryActions() {
    Row() {
      this.actionCard('我丢了东西', '发布丢失信息', '让更多同学帮你找', $r('app.media.action_lost'), '#BFE8CF', '#2C6B4A', ItemType.LOST)
      this.actionCard('我捡到东西', '发布拾获信息', '帮助失主回家', $r('app.media.action_found'), '#FFE5A6', '#8D651A', ItemType.FOUND)
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceEvenly)
    .margin({ top: 14 })
  }

  @Builder
  actionCard(title: string, subtitle: string, helper: string, image: Resource, background: string, textColor: string, type: ItemType) {
    Stack({ alignContent: Alignment.TopStart }) {
      Image(image)
        .width('100%')
        .height(154)
        .objectFit(ImageFit.Cover)
        .opacity(0.28)
      Column() {
        Row() {
          Text(title)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(textColor)
          Blank()
          Text('›')
            .width(27)
            .height(27)
            .textAlign(TextAlign.Center)
            .fontSize(25)
            .fontColor(textColor)
            .backgroundColor('#FFFFFF55')
            .borderRadius(14)
        }
        .width('100%')
        Text(subtitle)
          .fontSize(12)
          .fontColor(textColor)
          .opacity(0.85)
          .margin({ top: 6 })
        Text(helper)
          .fontSize(11)
          .fontColor(textColor)
          .opacity(0.78)
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 15, right: 14, top: 15 })
    }
    .width('46%')
    .height(154)
    .backgroundColor(background)
    .borderRadius(21)
    .clip(true)
    .onClick(() => {
      this.publishType = type;
      this.resetPublishForm();
      this.isPublishPanelVisible = true;
    })
  }

  @Builder
  publishPanel() {
    Column() {
      Row() {
        Text(this.publishType === ItemType.LOST ? '发布一条丢失信息' : '发布一条拾获信息')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text('收起')
          .fontSize(12)
          .fontColor('#57906F')
          .onClick(() => {
            this.isPublishPanelVisible = false;
          })
      }
      TextInput({ placeholder: '物品名称', text: this.formTitle })
        .margin({ top: 12 })
        .onChange((value: string) => this.formTitle = value)
      Row() {
        TextInput({ placeholder: '类别', text: this.formCategory })
          .layoutWeight(1)
          .onChange((value: string) => this.formCategory = value)
        TextInput({ placeholder: '颜色', text: this.formColor })
          .layoutWeight(1)
          .margin({ left: 8 })
          .onChange((value: string) => this.formColor = value)
      }
      .margin({ top: 8 })
      TextInput({ placeholder: '地点', text: this.formLocation })
        .margin({ top: 8 })
        .onChange((value: string) => this.formLocation = value)
      TextInput({ placeholder: '补充描述', text: this.formDescription })
        .margin({ top: 8 })
        .onChange((value: string) => this.formDescription = value)

      if (this.selectedImageUri) {
        Image(this.selectedImageUri)
          .width('100%')
          .height(120)
          .objectFit(ImageFit.Cover)
          .borderRadius(14)
          .margin({ top: 10 })
      }

      Row() {
        Button(this.selectedImageUri ? '重新选图片' : '选择图片')
          .layoutWeight(1)
          .onClick(() => this.pickImage())
        Button('发布信息')
          .layoutWeight(1)
          .margin({ left: 8 })
          .backgroundColor('#5EA378')
          .fontColor(Color.White)
          .onClick(() => this.publishItem())
      }
      .margin({ top: 12 })
    }
    .width('calc(100% - 40vp)')
    .padding(17)
    .margin({ left: 20, right: 20, top: 12 })
    .backgroundColor(Color.White)
    .borderRadius(20)
  }

  @Builder
  matchIntro() {
    Row() {
      Column() {
        Text('AI 智能线索匹配')
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor('#244F70')
        Text('类别、颜色、文字、地点和时间综合计算')
          .fontSize(12)
          .fontColor('#557A92')
          .margin({ top: 5 })
      }
      .alignItems(HorizontalAlign.Start)

      Blank()

      Text('整理线索')
        .fontSize(12)
        .fontColor('#557A92')
        .onClick(() => this.analyzeFirstItem())
    }
    .width('calc(100% - 40vp)')
    .padding({ left: 18, right: 18, top: 15, bottom: 15 })
    .margin({ left: 20, right: 20, top: 16 })
    .backgroundColor('#DFF2FB')
    .borderRadius(20)
  }

  @Builder
  aiAnalysisPanel() {
    if (this.aiAnalysis !== null) {
      Column() {
        Row() {
          Text(this.aiAnalysis.source === 'deepseek-vision' ? 'DeepSeek 图像识别结果' : '本机文字线索整理结果')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#244F70')
          Blank()
          Text('清除')
            .fontSize(12)
            .fontColor('#557A92')
            .onClick(() => {
              this.aiAnalysis = null;
              this.aiStatusMessage = '';
            })
        }
        Text('类别：' + (this.aiAnalysis.category ?? '未识别'))
          .fontSize(13)
          .fontColor('#3E6B55')
          .margin({ top: 10 })
        Text('颜色：' + (this.aiAnalysis.color ?? '未填写'))
          .fontSize(12)
          .fontColor('#557A92')
          .margin({ top: 5 })
        Text(this.aiAnalysis.features.length > 0 ? '特征：' + this.aiAnalysis.features.join('、') : '暂未识别到明显特征')
          .fontSize(12)
          .fontColor('#557A92')
          .margin({ top: 5 })
        if (this.aiAnalysis.visible_text.length > 0) {
          Text('可见文字：' + this.aiAnalysis.visible_text.join('、'))
            .fontSize(12)
            .fontColor('#557A92')
            .margin({ top: 5 })
        }
      }
      .width('calc(100% - 40vp)')
      .padding(16)
      .margin({ left: 20, right: 20, top: 12 })
      .backgroundColor('#EDF8FC')
      .borderRadius(18)
    }
  }

  @Builder
  publishAiResultPanel() {
    Column() {
      Row() {
        Column() {
          Text('AI 线索整理与匹配')
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .fontColor('#173B50')
          Text(LocalAppService.isServerAvailable()
            ? '信息、图片已同步服务端，正在进行 AI 分析与匹配'
            : '当前离线：信息保存在本机，联网后可使用云端功能')
            .fontSize(11)
            .fontColor('#6A7D8A')
            .margin({ top: 5 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text('×')
          .fontSize(25)
          .fontColor('#71808A')
          .onClick(() => this.isPublishAiPanelVisible = false)
      }
      .width('100%')
      .margin({ bottom: 12 })

      Scroll() {
        Column() {
          Row() {
            Text(LocalAppService.isServerAvailable() ? 'AI' : '离线')
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
              .width(42)
              .height(30)
              .textAlign(TextAlign.Center)
              .backgroundColor('#347B9B')
              .borderRadius(15)
            Text(this.publishAiMessage)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor('#31566A')
              .margin({ left: 9 })
              .layoutWeight(1)
          }
          .width('100%')
          .padding(12)
          .backgroundColor('#EAF5FA')
          .borderRadius(15)

          if (this.aiAnalysis !== null) {
            Column() {
              Row() {
                Text(this.aiAnalysis.source === 'deepseek-vision' ? 'DeepSeek 图像线索' : '本机文字线索')
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#173B50')
                Blank()
                Text(this.aiAnalysis.source === 'deepseek-vision' ? '视觉分析' : '离线兜底')
                  .fontSize(11)
                  .fontColor('#32735E')
                  .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  .backgroundColor('#E1F3E9')
                  .borderRadius(10)
              }
              .width('100%')
              Text('类别：' + (this.aiAnalysis.category ?? '未识别'))
                .fontSize(13)
                .fontColor('#31566A')
                .margin({ top: 10 })
              Text('颜色：' + (this.aiAnalysis.color ?? '未识别'))
                .fontSize(13)
                .fontColor('#31566A')
                .margin({ top: 6 })
              Text(this.aiAnalysis.features.length > 0
                ? '描述关键词：' + this.aiAnalysis.features.join('、')
                : '描述关键词：请补充物品特征')
                .fontSize(12)
                .fontColor('#557A92')
                .margin({ top: 6 })
                .maxLines(4)
            }
            .width('100%')
            .padding(14)
            .margin({ top: 12 })
            .backgroundColor('#F4FAFC')
            .borderRadius(16)
          } else if (!this.isPublishAiWorking) {
            Text('无可识别图片时，将根据已填写的类别、颜色和描述生成文字线索。')
              .fontSize(12)
              .fontColor('#557A92')
              .width('100%')
              .padding(12)
              .margin({ top: 10 })
              .backgroundColor('#F4FAFC')
              .borderRadius(14)
          }

          Text(this.publishType === ItemType.LOST ? '可能是你要找的' : '可能正在被寻找的物品')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#173B50')
            .width('100%')
            .margin({ top: 18, bottom: 8 })

          if (this.matchSuggestions.length > 0) {
            ForEach(this.matchSuggestions, (suggestion: MatchSuggestion) => {
              this.matchSuggestionCard(suggestion)
            }, (suggestion: MatchSuggestion) => suggestion.item.id)
          } else if (this.matchScanComplete) {
            Text('暂时没有发现相似线索。你的信息已发布，后续新线索也会继续进入匹配。')
              .fontSize(12)
              .fontColor('#6A7D8A')
              .width('100%')
              .padding(12)
              .backgroundColor('#F4F7F8')
              .borderRadius(14)
          } else {
            Text('正在比对类别、颜色、描述、地点和时间…')
              .fontSize(12)
              .fontColor('#557A92')
              .width('100%')
              .padding(12)
              .backgroundColor('#F4F7F8')
              .borderRadius(14)
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      Button(this.matchSuggestions.length > 0 ? '稍后再看' : '完成')
        .width('100%')
        .margin({ top: 12 })
        .backgroundColor('#347B9B')
        .fontColor(Color.White)
        .onClick(() => this.isPublishAiPanelVisible = false)
    }
    .width('100%')
    .height(600)
    .padding(18)
    .backgroundColor(Color.White)
    .borderRadius(24)
  }

  @Builder
  matchSuggestionCard(suggestion: MatchSuggestion) {
    Row() {
      if (suggestion.item.imageUri) {
        Image(suggestion.item.imageUri)
          .width(54)
          .height(54)
          .objectFit(ImageFit.Cover)
          .borderRadius(12)
      } else {
        Column() {
          Text('暂无图片')
            .fontSize(9)
            .fontColor('#557A92')
        }
        .width(54)
        .height(54)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#E6F2F6')
        .borderRadius(12)
      }
      Column() {
        Text(suggestion.item.title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#203B4A')
          .maxLines(1)
        Text(suggestion.item.category + ' · ' + suggestion.item.color)
          .fontSize(11)
          .fontColor('#6A7D8A')
          .margin({ top: 4 })
        Text('相似度 ' + Math.round(suggestion.score * 100) + '% · ' + suggestion.item.location)
          .fontSize(10)
          .fontColor('#32735E')
          .margin({ top: 4 })
          .maxLines(1)
        if (suggestion.aiScore !== undefined) {
          Text('AI 图片复核 ' + Math.round(suggestion.aiScore * 100) + '%'
            + (suggestion.aiReasons && suggestion.aiReasons.length > 0
              ? ' · ' + suggestion.aiReasons.slice(0, 2).join('、') : ''))
            .fontSize(10)
            .fontColor('#8A6424')
            .margin({ top: 4 })
            .maxLines(2)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 10 })
      Text('查看 ›')
        .fontSize(12)
        .fontColor('#347B9B')
    }
    .width('100%')
    .padding(11)
    .margin({ bottom: 8 })
    .backgroundColor('#F4FAFC')
    .borderRadius(15)
    .onClick(() => this.openSuggestedItem(suggestion.item))
  }

  @Builder
  itemList() {
    Column() {
      Row() {
        Text('大家正在找')
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text('更多')
          .fontSize(12)
          .fontColor('#6B7280')
          .onClick(() => this.activeTab = 1)
      }
      .width('100%')
      .margin({ bottom: 10 })

      ForEach(this.items, (item: ItemSummary) => {
        this.itemCard(item)
      }, (item: ItemSummary) => item.id)

      if (this.items.length === 0) {
        Column() {
          Text('当前还没有失物线索')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#2C5946')
          Text(LocalAppService.isServerAvailable()
            ? '发布后将同步到服务，供其他用户查看和匹配。'
            : '暂时无法连接服务，发布内容会先保存在本机。')
            .fontSize(12)
            .fontColor('#6B7280')
            .margin({ top: 7 })
          Button('发布第一条信息')
            .margin({ top: 13 })
            .backgroundColor('#5EA378')
            .fontColor(Color.White)
            .onClick(() => {
              this.publishType = ItemType.LOST;
              this.resetPublishForm();
              this.isPublishPanelVisible = true;
            })
        }
        .width('100%')
        .padding(18)
        .margin({ top: 4, bottom: 12 })
        .backgroundColor(Color.White)
        .borderRadius(16)
      }
    }
    .width('calc(100% - 40vp)')
    .alignItems(HorizontalAlign.Start)
    .margin({ left: 20, right: 20, top: 18 })
  }

  @Builder
  itemCard(item: ItemSummary) {
    Row() {
      Image(this.itemImage(item))
        .width(66)
        .height(66)
        .objectFit(ImageFit.Cover)
        .borderRadius(15)

      Column() {
        Row() {
          Text(item.title)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          if (item.matchScore !== undefined) {
            Text(Math.round(item.matchScore * 100) + '%匹配')
              .fontSize(11)
              .fontColor('#3E7A62')
              .backgroundColor('#E4F4EA')
              .padding({ left: 7, right: 7, top: 4, bottom: 4 })
              .borderRadius(10)
              .margin({ left: 7 })
          }
        }
        Text(item.category + ' · ' + item.color)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 5 })
        Text(item.location + ' · ' + item.timeLabel)
          .fontSize(11)
          .fontColor('#9299A5')
          .margin({ top: 5 })
        if (item.aiFeatures !== undefined && item.aiFeatures.length > 0) {
          Text('AI线索 · ' + item.aiFeatures.slice(0, 3).join('、'))
            .fontSize(10)
            .fontColor('#326A8A')
            .margin({ top: 6 })
            .maxLines(2)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
      .layoutWeight(1)

      Column() {
        Text(this.aiAnalyzingItemId === item.id ? '整理中' :
          (item.aiFeatures !== undefined ? '查看线索' : '整理线索'))
          .fontSize(11)
          .fontColor(item.aiFeatures !== undefined ? '#326A8A' : '#557A92')
          .onClick(() => this.analyzeItem(item))
        Text('聊一聊')
          .fontSize(12)
          .fontColor('#57906F')
          .margin({ top: 9 })
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .padding(12)
    .margin({ bottom: 10 })
    .backgroundColor(Color.White)
    .borderRadius(18)
    .onClick(() => this.openChat(item))
  }

  @Builder
  publishContent() {
    this.header()
    Column() {
      Text('我的发布')
        .fontSize(23)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Text('点击物品卡片可以直接和相关同学沟通')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 7, bottom: 14 })
      this.itemList()
    }
    .width('100%')
  }

  @Builder
  noticeContent() {
    this.header()
    Column() {
      Text('通知')
        .fontSize(23)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Text('与发布者的沟通')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor('#3E7A62')
        .width('calc(100% - 40vp)')
        .margin({ top: 18, left: 20, right: 20, bottom: 10 })
      if (this.chatInbox.length > 0) {
        ForEach(this.chatInbox, (thread: LocalInboxThread) => {
          Row() {
            Column() {
              Text(thread.item.title + ' · ' + thread.item.location)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor('#203B4A')
                .maxLines(1)
              Text('来自体验用户 ' + thread.participantId)
                .fontSize(11)
                .fontColor('#6B7280')
                .margin({ top: 5 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text('进入 ›')
              .fontSize(12)
              .fontColor('#347B9B')
          }
          .width('calc(100% - 40vp)')
          .padding(15)
          .margin({ left: 20, right: 20, bottom: 8 })
          .backgroundColor(Color.White)
          .borderRadius(16)
          .onClick(() => this.openInboxThread(thread))
        }, (thread: LocalInboxThread) => thread.id)
      } else {
        Text(LocalAppService.isServerAvailable()
          ? '还没有收到沟通消息。其他同学从线索卡片联系你后，会显示在这里。'
          : '连接服务后可查看其他设备发来的沟通消息。')
          .fontSize(13)
          .fontColor('#6B7280')
          .width('calc(100% - 40vp)')
          .padding(18)
          .margin({ left: 20, right: 20 })
          .backgroundColor(Color.White)
          .borderRadius(18)
      }
    }
    .width('100%')
  }

  @Builder
  profileContent() {
    this.header()
    Column() {
      Text('我的')
        .fontSize(23)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Text('体验身份：' + LocalAppService.currentUserId())
        .fontSize(14)
        .fontColor('#6B7280')
        .margin({ top: 12 })
      Text('高校A · ' + (LocalAppService.isServerAvailable() ? '服务已连接' : '本机离线模式'))
        .fontSize(14)
        .fontColor('#3E7A62')
        .margin({ top: 8 })
    }
    .width('calc(100% - 40vp)')
    .padding(20)
    .margin({ left: 20, right: 20, top: 18 })
    .backgroundColor(Color.White)
    .borderRadius(18)
  }

  @Builder
  chatContent() {
    Row() {
      Text('‹')
        .fontSize(30)
        .fontColor('#3E7A62')
        .onClick(() => this.isChatPanelVisible = false)
      Text('和同学聊一聊')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ left: 10 })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 20, bottom: 14 })

    Text(this.chatTitle)
      .fontSize(13)
      .fontColor('#6B7280')
      .width('calc(100% - 40vp)')
      .margin({ left: 20, right: 20, bottom: 10 })

    if (this.chatMessages.length === 0) {
      Text('还没有消息，先礼貌地问候一下吧')
        .fontSize(13)
        .fontColor('#9299A5')
        .margin({ top: 30, bottom: 20 })
    }

    Text(LocalAppService.isServerAvailable()
      ? '服务端会话 · 消息已同步'
      : '离线会话 · 消息仅保存在当前设备')
      .fontSize(11)
      .fontColor('#8B6A31')
      .width('calc(100% - 40vp)')
      .padding(10)
      .margin({ left: 20, right: 20, bottom: 12 })
      .backgroundColor('#FFF4D8')
      .borderRadius(12)

    ForEach(this.chatMessages, (message: LocalChatMessage) => {
      Row() {
        if (message.sender_id === LocalAppService.currentUserId()) {
          Blank()
        }
        Text(message.body)
          .fontSize(14)
          .fontColor(message.sender_id === LocalAppService.currentUserId() ? Color.White : '#2C5946')
          .padding({ left: 13, right: 13, top: 10, bottom: 10 })
          .backgroundColor(message.sender_id === LocalAppService.currentUserId() ? '#5EA378' : '#E4F4EA')
          .borderRadius(15)
        if (message.sender_id !== LocalAppService.currentUserId()) {
          Blank()
        }
      }
      .width('calc(100% - 40vp)')
      .margin({ left: 20, right: 20, bottom: 10 })
    }, (message: LocalChatMessage) => message.id)

    Row() {
      TextInput({ placeholder: '输入消息', text: this.chatDraft })
        .layoutWeight(1)
        .onChange((value: string) => this.chatDraft = value)
      Button('发送')
        .margin({ left: 8 })
        .backgroundColor('#5EA378')
        .fontColor(Color.White)
        .onClick(() => this.sendChatMessage())
    }
    .width('calc(100% - 40vp)')
    .margin({ left: 20, right: 20, top: 16 })
  }

  @Builder
  bottomNavigation() {
    Row() {
      this.navItem('首页', 0)
      this.navItem('我的发布', 1)
      this.navItem('通知', 2)
      this.navItem('我的', 3)
    }
    .width('100%')
    .height(68)
    .backgroundColor(Color.White)
    .justifyContent(FlexAlign.SpaceAround)
  }

  @Builder
  navItem(label: string, index: number) {
    Text(label)
      .fontSize(13)
      .fontColor(this.activeTab === index ? '#3E7A62' : $r('app.color.text_secondary'))
      .onClick(() => {
        this.isChatPanelVisible = false;
        this.activeTab = index;
        if (index === 2) {
          this.refreshChatInbox();
        }
      })
  }

  private itemImage(item: ItemSummary): string | Resource {
    if (item.imageUri) {
      return item.imageUri;
    }
    if (item.id === 'found-001') {
      return $r('app.media.item_student_card');
    }
    if (item.id === 'lost-001') {
      return $r('app.media.item_earbuds');
    }
    return $r('app.media.item_backpack');
  }

  private resetPublishForm(): void {
    this.formTitle = '';
    this.formCategory = '';
    this.formColor = '';
    this.formLocation = '';
    this.formDescription = '';
    this.selectedImageUri = '';
  }

  private async pickImage(): Promise<void> {
    try {
      const options = new picker.PhotoSelectOptions();
      options.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const result = await new picker.PhotoViewPicker().select(options);
      if (result.photoUris.length > 0) {
        this.selectedImageUri = result.photoUris[0];
        this.statusMessage = '图片已选择';
      }
    } catch (error) {
      this.statusMessage = '图片选择失败，请重试';
    }
  }

  private async publishItem(): Promise<void> {
    const abilityContext = this.abilityContext();
    if (!this.formTitle.trim() || !this.formLocation.trim()) {
      this.statusMessage = '请先填写物品名称和地点';
      return;
    }

    const payload: LocalItemInput = {
      location: this.formLocation.trim(),
      type: this.publishType,
      title: this.formTitle.trim(),
      description: this.formDescription.trim(),
      category: this.formCategory.trim() || '其他',
      color: this.formColor.trim() || '未填写',
      schoolId: this.selectedSchoolId(),
      scopeMode: this.crossSchoolEnabled ? 'cross_school' : 'same_school'
    };

    const hasImage = this.selectedImageUri.length > 0;
    let created: LocalItem;
    try {
      this.statusMessage = hasImage ? '正在保存并同步图片…' : '正在保存并同步信息…';
      created = await LocalAppService.createItem(payload, this.selectedImageUri, abilityContext);
    } catch (error) {
      this.statusMessage = '发布失败，请检查网络、图片权限或设备存储空间';
      return;
    }

    this.items = await LocalAppService.listItems(
      this.crossSchoolEnabled ? undefined : this.selectedSchoolId(),
      this.crossSchoolEnabled
    );
    this.isPublishPanelVisible = false;
    this.activeTab = 1;
    this.aiAnalysis = null;
    this.matchSuggestions = [];
    this.matchScanComplete = false;
    this.isPublishAiWorking = true;
    this.isPublishAiPanelVisible = true;
    this.publishAiMessage = created.serverSynced
      ? '信息已发布到服务端，正在分析图片并寻找相似线索…'
      : '信息已暂存本机，当前无法连接服务，先整理文字线索…';
    this.statusMessage = created.serverSynced ? '已同步，正在进行 AI 线索分析' : '仅保存在本机，暂未发布到服务端';
    this.resetPublishForm();
    await this.notificationService.publish('拾光失物', created.serverSynced
      ? '信息已发布，正在进行 AI 线索分析' : '服务未连接，信息仅保存在本机', abilityContext);

    const analysis = await LocalAppService.analyzeItem(created.id);
    this.aiAnalysis = analysis;
    await LocalAppService.updateAnalysis(created.id, analysis);
    this.items = this.items.map((item: ItemSummary) => {
      if (item.id !== created.id) {
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
        scopeMode: item.scopeMode,
        occurredAt: item.occurredAt,
        timeLabel: item.timeLabel,
        status: item.status,
        imageUri: item.imageUri,
        aiFeatures: analysis.features
      };
    });
    const matches = await LocalAppService.findMatches(created.id, this.crossSchoolEnabled);
    const suggestions: MatchSuggestion[] = [];
    for (const match of matches) {
      const suggestion: MatchSuggestion = {
        item: match.item,
        score: match.score,
        explanation: match.explanation,
        aiScore: match.aiScore,
        aiReasons: match.aiReasons
      };
      suggestions.push(suggestion);
    }
    this.matchSuggestions = suggestions;
    this.matchScanComplete = true;
    this.publishAiMessage = analysis.source === 'deepseek-vision'
      ? 'DeepSeek 已提取图片类别、颜色与可见特征，并结合地点、时间和文本匹配相关线索。'
      : '当前使用本机文字规则整理类别、颜色和描述；联网并上传图片后可调用云端视觉识别。';
    this.statusMessage = this.matchSuggestions.length > 0
      ? '线索分析完成，发现相似信息'
      : created.serverSynced ? '信息已同步，暂未发现相似线索' : '信息暂存在本机，暂未发现相似线索';
    this.isPublishAiWorking = false;
  }

  private async analyzeFirstItem(): Promise<void> {
    for (let item of this.items) {
      if (item.description || item.category || item.color || item.imageUri) {
        await this.analyzeItem(item);
        return;
      }
    }
    this.aiStatusMessage = '请先发布一条失物或招领信息';
    this.statusMessage = this.aiStatusMessage;
  }

  private async analyzeItem(item: ItemSummary): Promise<void> {
    const abilityContext = this.abilityContext();
    this.aiAnalyzingItemId = item.id;
    this.aiStatusMessage = '正在分析图片与文字线索…';
    this.statusMessage = this.aiStatusMessage;
    try {
      const analysis = await LocalAppService.analyzeItem(item.id);
      this.aiAnalysis = analysis;
      await LocalAppService.updateAnalysis(item.id, analysis);
      this.items = this.items.map((current: ItemSummary) => {
        if (current.id !== item.id) {
          return current;
        }
        return {
          id: current.id,
          title: current.title,
          type: current.type,
          category: analysis.category || current.category,
          color: analysis.color || current.color,
          description: current.description,
          location: current.location,
          timeLabel: current.timeLabel,
          status: current.status,
          imageUri: current.imageUri,
          aiFeatures: analysis.features
        };
      });
      this.aiStatusMessage = analysis.source === 'deepseek-vision'
        ? 'DeepSeek 图像识别完成' : '本机文字线索整理完成（离线兜底）';
      this.statusMessage = this.aiStatusMessage;
      const category = analysis.category ?? '物品';
      const color = analysis.color ?? '特征';
      await this.notificationService.publish('线索整理完成', `${category} · ${color}，已生成匹配线索`, abilityContext);
    } catch (error) {
      this.aiStatusMessage = '线索分析失败，请检查网络或稍后重试';
      this.statusMessage = this.aiStatusMessage;
    } finally {
      this.aiAnalyzingItemId = '';
    }
  }

  private async openSuggestedItem(item: ItemSummary): Promise<void> {
    this.isPublishAiPanelVisible = false;
    await this.openChat(item);
  }

  private async openChat(item: ItemSummary): Promise<void> {
    if (item.publisherId === LocalAppService.currentUserId()) {
      this.activeTab = 2;
      this.chatInbox = await LocalAppService.listInbox();
      this.statusMessage = '这是你发布的信息，请在“通知”查看收到的沟通';
      return;
    }
    this.chatTitle = item.title + ' · ' + item.location;
    this.chatItemId = item.id;
    this.chatDraft = '';
    this.chatId = await LocalAppService.openChat(item.id);
    this.chatMessages = await LocalAppService.getMessages(this.chatId);
    this.statusMessage = LocalAppService.isServerAvailable() ? '服务端会话已打开' : '本机离线会话已打开';
    this.isChatPanelVisible = true;
  }

  private async openInboxThread(thread: LocalInboxThread): Promise<void> {
    this.chatTitle = thread.item.title + ' · ' + thread.item.location;
    this.chatItemId = thread.item.id;
    this.chatId = thread.id;
    this.chatDraft = '';
    this.chatMessages = await LocalAppService.getMessages(thread.id);
    this.isChatPanelVisible = true;
    this.statusMessage = '服务端会话已打开';
  }

  private async refreshChatInbox(): Promise<void> {
    this.chatInbox = await LocalAppService.listInbox();
  }

  private async sendChatMessage(): Promise<void> {
    const body = this.chatDraft.trim();
    if (!body) {
      return;
    }
    try {
      const message = await LocalAppService.sendMessage(this.chatId, body);
      this.chatMessages = [...this.chatMessages, message];
      this.chatDraft = '';
    } catch (error) {
      this.statusMessage = '消息发送失败，请检查网络后重试';
    }
  }
}
