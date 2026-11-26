import { router } from '@kit.ArkUI';

interface MockPost {
  id: string;
  name: string;
  handle: string;
  time: string;
  body: string;
  replies: number;
  likes: number;
  avatarColor: string;
}

const POSTS: MockPost[] = [
  { id: 'p1', name: '林间散步', handle: '@walks.daily', time: '2 小时', body: '今天把节奏放慢一点。阳光、咖啡，还有一段没有目的地的散步。', replies: 12, likes: 86, avatarColor: '#8B6F5A' },
  { id: 'p2', name: '小岛来信', handle: '@island.notes', time: '4 小时', body: '做一个好用的客户端，先从认真照顾每一个细节开始。你最在意阅读、发布，还是切换设备时的连续感？', replies: 7, likes: 43, avatarColor: '#4A7B78' },
  { id: 'p3', name: '像素与纸', handle: '@pixels.and.paper', time: '昨天', body: '折叠屏合上时是一条舒适的时间线，展开后自然变成双栏。界面应该跟着设备形态长大。', replies: 19, likes: 122, avatarColor: '#776B9A' },
  { id: 'p4', name: '慢慢烘焙', handle: '@slow.bake', time: '昨天', body: '周末实验了新的酸种配方，厨房里全是面包出炉的香气。', replies: 5, likes: 31, avatarColor: '#C27B53' },
  { id: 'p5', name: '城市观察员', handle: '@city.notes', time: '2 天', body: '通勤路上看到一棵树冒出新芽，春天大概真的快来了。', replies: 9, likes: 64, avatarColor: '#6E8A62' },
  { id: 'p6', name: '周末书架', handle: '@weekend.books', time: '2 天', body: '在旧书里发现一张二十年前的车票。原来读到同一页的人，也可以离得这么远。', replies: 3, likes: 17, avatarColor: '#835B69' },
  { id: 'p7', name: '夜归电台', handle: '@night.radio', time: '3 天', body: '今晚的歌单只有三首，刚好够走完从车站回家的路。', replies: 2, likes: 23, avatarColor: '#485E81' },
  { id: 'p8', name: '山下邮局', handle: '@hill.post', time: '3 天', body: '把这周拍到的云印成四张明信片，寄给好久没见面的朋友。', replies: 6, likes: 39, avatarColor: '#866844' }
];

@Entry
@Component
struct Timeline {
  @State private likedIds: string[] = [];
  @State private followedIds: string[] = [];
  @State private notice: string = '';
  @State private openingWeb: boolean = false;

  private async openWeb(): Promise<void> {
    if (this.openingWeb) {
      return;
    }
    this.openingWeb = true;
    try {
      await router.pushUrl({ url: 'pages/Index' });
    } catch (_error) {
      this.notice = '暂时无法打开网页，请重试。';
    } finally {
      this.openingWeb = false;
    }
  }

  private toggleLike(id: string): void {
    this.likedIds = this.likedIds.includes(id)
      ? this.likedIds.filter((item: string) => item !== id)
      : [...this.likedIds, id];
  }

  private toggleFollow(id: string): void {
    this.followedIds = this.followedIds.includes(id)
      ? this.followedIds.filter((item: string) => item !== id)
      : [...this.followedIds, id];
  }

  @Builder
  PostCard(post: MockPost) {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Text(post.name.substring(0, 1)).width(42).height(42).fontSize(16).fontColor('#FFFFFF')
          .textAlign(TextAlign.Center).backgroundColor(post.avatarColor).borderRadius(21)
        Column({ space: 3 }) {
          Text(post.name).fontSize(15).fontWeight(FontWeight.Medium).fontColor('#171717')
          Text(`${post.handle} · ${post.time}`).fontSize(12).fontColor('#777777')
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Button(this.followedIds.includes(post.id) ? '已关注' : '关注')
          .height(32).fontSize(12).borderRadius(16)
          .backgroundColor(this.followedIds.includes(post.id) ? '#EFEFEF' : '#171717')
          .fontColor(this.followedIds.includes(post.id) ? '#444444' : '#FFFFFF')
          .onClick(() => this.toggleFollow(post.id))
      }.width('100%')
      Text(post.body).fontSize(15).fontColor('#202020').lineHeight(23).width('100%')
      Row({ space: 4 }) {
        Button(this.likedIds.includes(post.id) ? '♥' : '♡').fontSize(18)
          .buttonStyle(ButtonStyleMode.TEXTUAL).width(44).height(44)
          .accessibilityText(this.likedIds.includes(post.id) ? '取消点赞' : '点赞')
          .fontColor(this.likedIds.includes(post.id) ? '#D84A63' : '#555555')
          .onClick(() => this.toggleLike(post.id))
        Text(`${post.likes + (this.likedIds.includes(post.id) ? 1 : 0)}`).fontSize(12).fontColor('#555555')
        Button('◯').buttonStyle(ButtonStyleMode.TEXTUAL).width(44).height(44).margin({ left: 8 })
          .fontSize(15).fontColor('#555555').accessibilityText('回复')
          .onClick(() => { this.notice = '回复仅为界面演示，当前不会发送。'; })
        Text(`${post.replies}`).fontSize(12).fontColor('#555555')
        Blank().layoutWeight(1)
        Button('↗').buttonStyle(ButtonStyleMode.TEXTUAL).width(44).height(44)
          .fontSize(16).fontColor('#555555').accessibilityText('分享')
          .onClick(() => { this.notice = '分享功能尚未接入。'; })
      }.width('100%').height(44)
    }
    .width('100%').padding({ left: 18, right: 18, top: 16, bottom: 14 })
  }

  build() {
    Column() {
      Row() {
        Column({ space: 2 }) {
          Text('Threads').fontSize(25).fontWeight(FontWeight.Bold).fontColor('#171717')
          Text('为你推荐').fontSize(12).fontColor('#737373')
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Button('＋').width(42).height(42).fontSize(24).borderRadius(21)
          .backgroundColor('#171717').fontColor('#FFFFFF')
          .onClick(() => { this.notice = '发帖功能尚未接入；此页只展示模拟内容。'; })
        Button('网页').height(44).margin({ left: 8 }).enabled(!this.openingWeb)
          .onClick(() => { this.openWeb(); })
      }.width('100%').padding({ left: 18, right: 18, top: 14, bottom: 10 })

      Column({ space: 4 }) {
        Text('本地模拟内容 · 不会连接或发布到 Threads').fontSize(12).fontColor('#666666')
        if (this.notice.length > 0) {
          Text(this.notice).fontSize(12).fontColor('#555555')
        }
      }.alignItems(HorizontalAlign.Start).width('100%').padding({ left: 18, right: 18, bottom: 8 })

      Scroll() {
        Column() {
          ForEach(POSTS, (post: MockPost) => {
            Column() {
              this.PostCard(post)
              Divider().color('#E9E9E9').strokeWidth(1).margin({ left: 18, right: 18 })
            }.width('100%')
          }, (post: MockPost) => post.id)
        }.width('100%')
      }.layoutWeight(1).scrollBar(BarState.Auto)

      Row() {
        Text('⌂').fontSize(23).fontColor('#171717')
        Blank().layoutWeight(1)
        Text('♡').fontSize(23).fontColor('#777777')
        Blank().layoutWeight(1)
        Text('＋').fontSize(23).fontColor('#777777')
        Blank().layoutWeight(1)
        Text('⌕').fontSize(23).fontColor('#777777')
        Blank().layoutWeight(1)
        Text('◉').fontSize(23).fontColor('#777777')
      }.width('100%').padding({ left: 28, right: 28, top: 10, bottom: 10 })
        .border({ width: { top: 1 }, color: '#EEEEEE' })
    }.width('100%').height('100%').backgroundColor('#FFFFFF')
  }
}
