import { accessibility } from '@kit.AccessibilityKit';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { FrameCallback, LengthMetrics, router, SegmentButtonV2Items, TabSegmentButtonV2 } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { systemShare } from '@kit.ShareKit';
import { decodeLibrary, emptyLibrary, encodeLibrary, LibraryPost, LibraryReply, LIBRARY_POST_LIMIT, LIBRARY_REPLY_LIMIT,
  LOCAL_POST_BODY_LIMIT, LOCAL_REPLY_BODY_LIMIT, LocalLibrary, matchesPost, updateLibrary } from '../model/LocalLibrary';
import { decodeIdentity, emptyIdentity, LocalIdentity, normalizeIdentity } from '../model/LocalIdentity';
import { ActivityEntry, ActivityPane } from '../components/ActivityPane';
import { AuthorPane } from '../components/AuthorPane';
import { ConversationPane, ConversationReply } from '../components/ConversationPane';
import { DiscoveryAuthor, DiscoveryPane } from '../components/DiscoveryPane';
import { IdentityEditor, LibraryHub } from '../components/LibraryHub';
import { ReadingTabs } from '../components/ReadingTabs';
import { SettingsPane } from '../components/SettingsPane';

const LARGE_TEXT_SCALE = 1.4;
const WIDE_VIEWPORT = 680;
const SIDE_NAV_WIDTH = 840;
const MAX_LIST_WIDTH = 1248;
const REPLY_LIMIT = LOCAL_REPLY_BODY_LIMIT;
const POST_DETAIL = 'PostDetail';
const POST_COMPOSER = 'PostComposer';
const POST_DRAFT_LIMIT = LOCAL_POST_BODY_LIMIT;
const POST_SETTINGS = 'Settings';
const AUTHOR_PROFILE = 'AuthorProfile';
const IDENTITY_EDITOR = 'IdentityEditor';
const POST_EDITOR = 'PostEditor';
const DISCOVERY_TOPICS: string[] = ['折叠屏', '周末', '阅读', '通勤', '明信片', '歌单'];

enum ShellTab {
  Home,
  Search,
  Activity,
  Profile
}
const LIBRARY_STORE = 'timeline_local_library';
const LIBRARY_KEY = 'content_v1';
const IDENTITY_STORE = 'timeline_identity';
const IDENTITY_KEY = 'profile_v1';
const POST_DRAFT_STORE = 'timeline_post_draft';
const POST_DRAFT_KEY = 'body';

enum DraftDecision {
  None,
  Leave,
  Clear
}

interface DemoReply extends ConversationReply {}

const SAMPLE_REPLIES: DemoReply[] = [
  { id: 's1', postId: 'p1', author: '周末书架', body: '喜欢这种无目的的散步，回来时连熟悉的街道都不太一样了。', local: false },
  { id: 's2', postId: 'p1', author: '城市观察员', body: '把这段话留给下一个想慢下来的周末。', local: false },
  { id: 's3', postId: 'p2', author: '像素与纸', body: '切换设备时，我最想保留的是刚刚读到的那一句。', local: false },
  { id: 's5', postId: 'p2', author: '慢慢烘焙', body: '我在厨房里用折叠屏读长帖。展开时能同时看原帖和讨论当然很好，但合上屏幕去看烤箱，再打开时，我希望看到的还是刚刚那句话。读到一半去写回复也是一样：先让我知道我在回谁，收起键盘时别把没写完的话带走。少做一次重新寻找，比多一个动画更重要。', local: false, parentId: 's3', toAuthor: '像素与纸' },
  { id: 's4', postId: 'p3', author: '小岛来信', body: '展开以后多一列，合上以后还能接着读，这就很舒服。', local: false }
];

interface ReadingAnchor {
  postId: string;
  clipped: number;
}

class LayoutFrame extends FrameCallback {
  private readonly task: () => void;

  constructor(task: () => void) {
    super();
    this.task = task;
  }

  onIdle(_timeLeftInNano: number): void {
    this.task();
  }
}
const DISPLAY_PREFERENCES = 'timeline_display';
const REDUCE_MOTION_KEY = 'reduce_motion';

interface MockPost {
  id: string;
  name: string;
  handle: string;
  time: string;
  body: string;
  replies: number;
  likes: number;
  avatarColor: string;
  local?: boolean;
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
  @State private timelinePosts: MockPost[] = [...POSTS];
  @State private likedIds: string[] = [];
  @State private followedIds: string[] = [];
  @State private savedIds: string[] = [];
  @State private libraryReady: boolean = false;
  @State private libraryLoading: boolean = false;
  @State private libraryBusy: boolean = false;
  @State private libraryMessage: string = '';
  @State private selectedTab: ShellTab = ShellTab.Home;
  @State private searchQuery: string = '';
  @State private discoveryMode: number = 0;
  @State private libraryMode: number = 0;
  @State private hiddenIds: string[] = [];
  @State private identity: LocalIdentity = emptyIdentity();
  @State private identityReady: boolean = false;
  @State private identityBusy: boolean = false;
  @State private identityName: string = '';
  @State private identityBio: string = '';
  @State private identityMessage: string = '';
  @State private identityConfirmLeave: boolean = false;
  @State private editingPostId: string = '';
  @State private editBody: string = '';
  @State private editMessage: string = '';
  @State private editConfirmLeave: boolean = false;
  private menuOpen: boolean = false;
  @State private followingOnly: boolean = false;
  private homeTabAnchor: ReadingAnchor = { postId: '', clipped: 0 };
  private followingTabAnchor: ReadingAnchor = { postId: '', clipped: 0 };
  @State private confirmingDelete: boolean = false;
  @State private openingWeb: boolean = false;
  @State private viewportWidth: number = 0;
  @State private contentWidth: number = 0;
  @StorageProp('timelineFontScale') @Watch('onReadingLayoutChange') private fontScale: number = 1;
  @State private animationTriggers: number[] = POSTS.map((_post: MockPost) => -1);
  @State private reduceMotion: boolean = false;
  @State private systemReducesMotion: boolean = false;
  @State private motionPreferenceReady: boolean = false;
  @State private motionPreferenceSaving: boolean = false;
  @State private motionPreferenceWarning: string = '';
  private readonly feedSegments: SegmentButtonV2Items = new SegmentButtonV2Items([{ text: '为你' }, { text: '关注中' }]);
  @State private localReplies: DemoReply[] = [];
  @State private replyDraft: string = '';
  @State private activeDetailId: string = '';
  @State private focusedReplyId: string = '';
  @State private replyTargetId: string = '';
  @State private replyExpanded: boolean = false;
  @State private replyExitPending: boolean = false;
  @State private postDraft: string = '';
  @State private savedPostDraft: string = '';
  @State private postDraftReady: boolean = false;
  @State private postDraftBusy: boolean = false;
  @State private postDraftMessage: string = '';
  @State private draftDecision: DraftDecision = DraftDecision.None;
  @State private showingPostPreview: boolean = false;
  @State private previewBody: string = '';
  private library: LocalLibrary = emptyLibrary();
  private postSequence: number = 0;
  private postDraftLoadId: number = 0;
  private replySequence: number = 0;
  private readonly detailPaths: NavPathStack = new NavPathStack();
  private readonly timelineScroller: Scroller = new Scroller();
  private firstVisibleIndex: number = 0;
  private readingAnchor: ReadingAnchor = { postId: '', clipped: 0 };
  private restorePending: boolean = false;
  private restoreScheduled: boolean = false;
  private timelineVisible: boolean = false;
  private watchingSystemMotion: boolean = false;
  private readonly systemMotionListener = (enabled: boolean): void => {
    this.systemReducesMotion = enabled;
    if (enabled) {
      this.resetMotionFeedback();
    }
  };

  aboutToAppear(): void {
    try {
      this.systemMotionListener(accessibility.isAnimationReduceEnabledSync());
      accessibility.onAnimationReduceStateChange(this.systemMotionListener);
      this.watchingSystemMotion = true;
    } catch (_error) {
      // The local preference still works if this device cannot report system motion settings.
    }
    this.loadMotionPreference();
    this.loadLibrary();
    this.loadIdentity();
  }

  aboutToDisappear(): void {
    if (this.watchingSystemMotion) {
      this.watchingSystemMotion = false;
      try {
        accessibility.offAnimationReduceStateChange(this.systemMotionListener);
      } catch (_error) {
        // Keep the rest of the page teardown independent of the system service.
      }
    }
  }

  onPageShow(): void {
    this.timelineVisible = this.detailPaths.size() === 0 && this.selectedTab === ShellTab.Home;
    if (this.restorePending) {
      this.scheduleReadingRestore();
    }
  }

  onPageHide(): void {
    this.timelineVisible = false;
  }

  onBackPress(): boolean {
    if (this.detailPaths.size() === 0 && this.selectedTab !== ShellTab.Home) {
      this.selectTab(ShellTab.Home);
      return true;
    }
    return false;
  }

  private toolbarInList(): boolean {
    return this.fontScale >= LARGE_TEXT_SCALE;
  }

  private readingLaneCount(): number {
    return (this.contentWidth || this.viewportWidth) >= WIDE_VIEWPORT && !this.toolbarInList() ? 2 : 1;
  }

  private rememberReadingPosition(): void {
    if (!this.timelineVisible || this.restorePending) {
      return;
    }
    const index = this.firstVisibleIndex;
    try {
      const offset = this.timelineScroller.offset();
      if (offset === undefined || index < 0) {
        return;
      }
      const post = this.visibleFeed()[index - (this.toolbarInList() ? 1 : 0)];
      if (offset.yOffset <= 1 || (index === 0 && post === undefined)) {
        this.readingAnchor = { postId: '', clipped: 0 };
      } else if (post !== undefined) {
        const rect = this.timelineScroller.getItemRect(index);
        if (rect.height > 0) {
          this.readingAnchor = { postId: post.id, clipped: Math.max(0, -rect.y) };
        }
      }
    } catch (_error) {
      // The layout can be detached during a window transition.
    }
  }

  private onReadingLayoutChange(): void {
    this.restorePending = true;
    this.scheduleReadingRestore();
  }

  private scheduleReadingRestore(): void {
    if (!this.timelineVisible || this.restoreScheduled) {
      return;
    }
    this.restoreScheduled = true;
    this.getUIContext().postFrameCallback(new LayoutFrame(() => {
      this.restoreScheduled = false;
      if (!this.timelineVisible || !this.restorePending) {
        return;
      }
      this.restoreReadingPosition();
    }));
  }

  private restoreReadingPosition(): void {
    const anchor = this.readingAnchor;
    try {
      if (anchor.postId === '') {
        if ((this.timelineScroller.offset()?.yOffset ?? 0) > 1) {
          this.timelineScroller.scrollToIndex(0, false, ScrollAlign.START);
        }
        return;
      }
      const postIndex = this.visibleFeed().findIndex((post: MockPost) => post.id === anchor.postId);
      if (postIndex < 0) {
        return;
      }
      const index = postIndex + (this.toolbarInList() ? 1 : 0);
      const rect = this.timelineScroller.getItemRect(index);
      const clipped = rect.height > 0 ? Math.min(anchor.clipped, rect.height / 2) : 0;
      if (rect.height <= 0 || Math.abs(rect.y + clipped) > 1) {
        this.timelineScroller.scrollToIndex(index, false, ScrollAlign.START, { extraOffset: LengthMetrics.vp(clipped) });
      }
    } catch (_error) {
      // A different window may have detached the list before this frame.
    } finally {
      this.restorePending = false;
    }
  }

  private async displayPreferences(): Promise<preferences.Preferences> {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      throw new Error('Timeline host context unavailable');
    }
    return preferences.getPreferences(context, { name: DISPLAY_PREFERENCES });
  }

  private async loadMotionPreference(): Promise<void> {
    try {
      const store = await this.displayPreferences();
      this.setReduceMotion(await store.get(REDUCE_MOTION_KEY, false) === true);
    } catch (_error) {
      this.motionPreferenceWarning = '无法读取已保存的偏好。';
    } finally {
      this.motionPreferenceReady = true;
    }
  }

  private async updateMotionPreference(enabled: boolean): Promise<void> {
    if (!this.motionPreferenceReady || this.motionPreferenceSaving || this.reduceMotion === enabled) {
      return;
    }
    this.setReduceMotion(enabled);
    this.motionPreferenceSaving = true;
    this.motionPreferenceWarning = '';
    try {
      const store = await this.displayPreferences();
      await store.put(REDUCE_MOTION_KEY, enabled);
      await store.flush();
    } catch (_error) {
      this.motionPreferenceWarning = '偏好未能保存，本次仍然生效。';
    } finally {
      this.motionPreferenceSaving = false;
    }
  }

  private inform(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message, duration: 1800 });
    } catch (_error) {
      // A transient toast failure must not interrupt the post interaction.
    }
  }

  private allowsMotionFeedback(): boolean {
    return this.motionPreferenceReady && !this.reduceMotion && !this.systemReducesMotion;
  }

  private animationTriggerFor(id: string): number {
    const index = this.timelinePosts.findIndex((post: MockPost) => post.id === id);
    return index >= 0 && this.allowsMotionFeedback() ? this.animationTriggers[index] : -1;
  }

  private resetMotionFeedback(): void {
    this.animationTriggers = this.timelinePosts.map((_post: MockPost) => -1);
  }

  private setReduceMotion(enabled: boolean): void {
    this.reduceMotion = enabled;
    if (enabled) {
      this.resetMotionFeedback();
    }
  }

  private async openWeb(): Promise<void> {
    if (this.openingWeb) {
      return;
    }
    this.openingWeb = true;
    try {
      await router.pushUrl({ url: 'pages/Index' });
    } catch (_error) {
      this.inform('网页暂时无法打开，请稍后重试。');
    } finally {
      this.openingWeb = false;
    }
  }

  private async toggleLike(id: string): Promise<void> {
    const index = this.timelinePosts.findIndex((post: MockPost) => post.id === id);
    if (index < 0) {
      return;
    }
    const next = this.nextSelection(this.likedIds, id);
    if (await this.saveLibrary(updateLibrary(this.library, { likedIds: next }))) {
      const nextTriggers = [...this.animationTriggers];
      nextTriggers[index] = !next.includes(id) || !this.allowsMotionFeedback() ? -1 : nextTriggers[index] + 1;
      this.animationTriggers = nextTriggers;
    }
  }

  private async toggleFollow(id: string): Promise<void> {
    const next = this.nextSelection(this.followedIds, id);
    await this.saveLibrary(updateLibrary(this.library, { followedIds: next }));
  }

  private openPost(post: MockPost, focusId: string = ''): void {
    const paths = this.detailPaths.getAllPathName();
    if ((paths.length > 0 && (paths.length !== 1 || paths[0] !== AUTHOR_PROFILE)) ||
      !this.timelinePosts.some((item: MockPost) => item.id === post.id)) {
      return;
    }
    this.rememberReadingPosition();
    this.timelineVisible = false;
    this.activeDetailId = post.id;
    this.focusedReplyId = this.repliesFor(post.id).some((row: DemoReply) => row.id === focusId) ? focusId : '';
    this.replyTargetId = this.focusedReplyId;
    this.replyDraft = '';
    this.replyExpanded = false;
    this.replyExitPending = false;
    this.confirmingDelete = false;
    this.detailPaths.pushPath({ name: POST_DETAIL, param: post, onPop: () => {
      this.activeDetailId = '';
      this.focusedReplyId = '';
      this.replyTargetId = '';
      this.replyExpanded = false;
      this.replyExitPending = false;
      this.replyDraft = '';
      this.confirmingDelete = false;
      this.onPageShow();
    } }, this.allowsMotionFeedback());
  }

  private closePost(): void {
    if (this.confirmingDelete) {
      if (!this.libraryBusy) {
        this.confirmingDelete = false;
      }
    } else if (this.detailPaths.size() > 0) {
      this.detailPaths.pop({ closed: true }, this.allowsMotionFeedback());
    }
  }

  private repliesFor(postId: string): DemoReply[] {
    const rows = [...this.localReplies, ...SAMPLE_REPLIES].filter((row: DemoReply) => row.postId === postId);
    const children = new Map<string, DemoReply[]>();
    rows.forEach((row: DemoReply) => {
      const key = row.parentId ?? '';
      const group = children.get(key);
      if (group !== undefined) { group.push(row); } else { children.set(key, [row]); }
    });
    const pending: DemoReply[] = [...(children.get('') ?? [])].reverse();
    const ordered: DemoReply[] = [];
    while (pending.length > 0) {
      const item = pending.pop();
      if (item !== undefined) {
        ordered.push(item);
        const nested = children.get(item.id);
        if (nested !== undefined) {
          for (let i = nested.length - 1; i >= 0; i--) { pending.push(nested[i]); }
        }
      }
    }
    return ordered;
  }

  private replyCount(post: MockPost): number {
    return post.replies + this.localReplies.filter((reply: DemoReply) => reply.postId === post.id).length;
  }

  private previewReply(postId: string): DemoReply | undefined {
    return this.localReplies.find((row: DemoReply) => row.postId === postId) ??
      SAMPLE_REPLIES.find((row: DemoReply) => row.postId === postId);
  }

  private previewRows(postId: string): DemoReply[] {
    const latest = this.previewReply(postId);
    return latest === undefined ? [] : [latest];
  }

  private targetRow(postId: string): DemoReply | undefined {
    if (!this.replyTargetId) { return undefined; }
    return this.localReplies.find((row: DemoReply) => row.postId === postId && row.id === this.replyTargetId) ??
      SAMPLE_REPLIES.find((row: DemoReply) => row.postId === postId && row.id === this.replyTargetId);
  }

  private replyRecipient(post: MockPost): string {
    const row = this.targetRow(post.id);
    if (row === undefined) { return post.handle.startsWith('@') ? post.handle : '@' + post.name; }
    const author = POSTS.find((item: MockPost) => item.name === row.author);
    return author?.handle ?? '@' + row.author;
  }

  private beginReply(postId: string, targetId: string): void {
    if (this.activeDetailId !== postId || this.replyExitPending || this.confirmingDelete || this.libraryBusy) { return; }
    if (targetId && !this.repliesFor(postId).some((row: DemoReply) => row.id === targetId)) { return; }
    if (this.replyDraft.length > 0 && this.replyTargetId !== targetId) {
      this.inform('先完成当前回复，文字和回复对象都已保留。');
      return;
    }
    this.replyTargetId = targetId;
    this.replyExpanded = true;
  }

  private expandCurrentReply(postId: string): void {
    this.beginReply(postId, this.replyTargetId);
  }

  private requestDetailBack(): void {
    if (!this.activeDetailId || this.libraryBusy) { return; }
    if (this.confirmingDelete) { this.closePost(); return; }
    if (this.replyExitPending) { this.keepReplyDraft(); return; }
    if (this.replyDraft.length > 0) { this.replyExitPending = true; return; }
    if (this.replyExpanded) { this.replyExpanded = false; return; }
    this.closePost();
  }

  private keepReplyDraft(): void {
    this.replyExitPending = false;
  }

  private discardReplyAndClose(): void {
    if (!this.replyExitPending || !this.activeDetailId) { return; }
    this.replyDraft = '';
    this.replyExitPending = false;
    this.replyExpanded = false;
    this.closePost();
  }

  private async submitReply(postId: string): Promise<void> {
    const post = this.timelinePosts.find((item: MockPost) => item.id === postId);
    const body = this.replyDraft.trim();
    if (!this.replyExpanded || this.replyExitPending || this.libraryBusy || !this.libraryReady ||
      postId !== this.activeDetailId || post === undefined || !body || this.replyDraft.length > REPLY_LIMIT) { return; }
    if (this.library.replies.length >= LIBRARY_REPLY_LIMIT || this.replySequence >= 999999999999999) {
      this.inform('本机回复已达上限，可在「我的 → 回复」中管理。');
      return;
    }
    const parent = this.targetRow(postId);
    if (this.replyTargetId && parent === undefined) { return; }
    const sequence = this.replySequence + 1;
    const id = 'local-' + sequence;
    const reply: LibraryReply = { id: id, postId: postId, body: body, parentId: parent?.id };
    if (!(await this.saveLibrary(updateLibrary(this.library, { replies: [reply, ...this.library.replies] })))) { return; }
    this.replySequence = sequence;
    this.replyDraft = '';
    this.replyExpanded = false;
    this.focusedReplyId = id;
    this.replyTargetId = '';
  }

  private localPost(post: LibraryPost): MockPost {
    return { id: post.id, name: this.identity.name, handle: '本机帖子', time: '离线', body: post.body,
      replies: 0, likes: 0, avatarColor: '#4A7B78', local: true };
  }

  private async libraryPreferences(): Promise<preferences.Preferences> {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      throw new Error('Timeline host context unavailable');
    }
    return preferences.getPreferences(context, { name: LIBRARY_STORE });
  }

  private applyLibrary(value: LocalLibrary): void {
    const previousPosts = this.timelinePosts;
    const previousTriggers = this.animationTriggers;
    this.library = value;
    this.likedIds = value.likedIds;
    this.followedIds = value.followedIds;
    this.savedIds = value.savedIds;
    this.hiddenIds = value.hiddenIds;
    if (value.posts.length !== previousPosts.length - POSTS.length || value.posts.some((post: LibraryPost, index: number) =>
      post.id !== previousPosts[index]?.id || post.body !== previousPosts[index]?.body ||
      this.identity.name !== previousPosts[index]?.name)) {
      const next = [...value.posts.map((post: LibraryPost) => this.localPost(post)), ...POSTS];
      this.animationTriggers = next.map((post: MockPost) => {
        const index = previousPosts.findIndex((previous: MockPost) => previous.id === post.id);
        return index < 0 ? -1 : previousTriggers[index];
      });
      this.timelinePosts = next;
    }
    this.localReplies = value.replies.map((row: LibraryReply): DemoReply => {
      const sampleParent = SAMPLE_REPLIES.find((sample: DemoReply) => sample.id === row.parentId);
      const parent = row.parentId ? sampleParent?.author ?? '你' :
        this.timelinePosts.find((post: MockPost) => post.id === row.postId)?.name;
      return { id: row.id, postId: row.postId, body: row.body, author: '你', local: true,
        parentId: row.parentId, toAuthor: parent };
    });
  }

  private async loadLibrary(): Promise<void> {
    if (this.libraryLoading || this.libraryReady) {
      return;
    }
    this.libraryLoading = true;
    this.libraryMessage = '';
    try {
      const store = await this.libraryPreferences();
      const raw = await store.get(LIBRARY_KEY, '');
      if (typeof raw !== 'string') {
        throw new Error('Invalid library store');
      }
      const value = decodeLibrary(raw, POSTS.map((post: MockPost) => post.id), SAMPLE_REPLIES);
      this.applyLibrary(value);
      this.postSequence = value.posts.reduce((latest: number, post: LibraryPost) =>
        Math.max(latest, Number(post.id.substring('local-post-'.length))), 0);
      this.replySequence = value.replies.reduce((latest: number, row: LibraryReply) =>
        Math.max(latest, Number(row.id.substring('local-'.length))), 0);
      this.libraryReady = true;
    } catch (_error) {
      this.libraryMessage = '暂时无法读取本机内容，浏览演示帖不受影响。';
    } finally {
      this.libraryLoading = false;
    }
  }

  private async saveLibrary(value: LocalLibrary): Promise<boolean> {
    if (!this.libraryReady || this.libraryBusy) {
      return false;
    }
    this.libraryBusy = true;
    this.libraryMessage = '';
    try {
      const store = await this.libraryPreferences();
      await store.put(LIBRARY_KEY, encodeLibrary(value));
      await store.flush();
      this.applyLibrary(value);
      return true;
    } catch (_error) {
      this.libraryMessage = '未能保存本机更改，请重试。';
      this.inform(this.libraryMessage);
      return false;
    } finally {
      this.libraryBusy = false;
    }
  }

  private nextSelection(ids: string[], id: string): string[] {
    return ids.includes(id) ? ids.filter((item: string) => item !== id) : [...ids, id];
  }

  private async toggleSaved(post: MockPost): Promise<void> {
    const next = this.nextSelection(this.savedIds, post.id);
    await this.saveLibrary(updateLibrary(this.library, { savedIds: next }));
  }

  private selectTab(tab: ShellTab): void {
    if (tab === this.selectedTab || this.detailPaths.size() > 0) {
      return;
    }
    this.rememberReadingPosition();
    this.selectedTab = tab;
    this.onPageShow();
  }

  private openSettings(): void {
    if (this.detailPaths.size() > 0) {
      return;
    }
    this.rememberReadingPosition();
    this.timelineVisible = false;
    this.detailPaths.pushPath({ name: POST_SETTINGS, onPop: () => this.onPageShow() }, this.allowsMotionFeedback());
  }

  private visibleFeed(): MockPost[] {
    return this.timelinePosts.filter((post: MockPost) => !this.hiddenIds.includes(post.id) &&
      (!this.followingOnly || this.followedIds.includes(post.id)));
  }

  private selectFeed(following: boolean): void {
    if (following === this.followingOnly) {
      return;
    }
    this.rememberReadingPosition();
    if (this.followingOnly) {
      this.followingTabAnchor = this.readingAnchor;
    } else {
      this.homeTabAnchor = this.readingAnchor;
    }
    this.followingOnly = following;
    this.readingAnchor = following ? this.followingTabAnchor : this.homeTabAnchor;
    this.onReadingLayoutChange();
  }

  private activityEntries(): ActivityEntry[] {
    const entries: ActivityEntry[] = [];
    this.timelinePosts.forEach((post: MockPost) => {
      if (this.likedIds.includes(post.id)) {
        entries.push({ id: `like-${post.id}`, postId: post.id, author: post.name, body: post.body, kind: 'like' });
      }
      if (this.savedIds.includes(post.id)) {
        entries.push({ id: `save-${post.id}`, postId: post.id, author: post.name, body: post.body, kind: 'save' });
      }
    });
    this.localReplies.forEach((reply: DemoReply) => {
      const post = this.timelinePosts.find((item: MockPost) => item.id === reply.postId);
      if (post !== undefined) {
        entries.push({ id: `reply-${reply.id}`, postId: post.id, author: post.name, body: reply.body, kind: 'reply' });
      }
    });
    return entries;
  }

  private openActivityPost(entry: ActivityEntry): void {
    const post = this.timelinePosts.find((item: MockPost) => item.id === entry.postId);
    if (post !== undefined) {
      this.openPost(post, entry.kind === 'reply' ? entry.id.substring('reply-'.length) : '');
    }
  }

  private discoveryPosts(): MockPost[] {
    return this.timelinePosts.filter((post: MockPost) => !this.hiddenIds.includes(post.id) &&
      matchesPost(this.searchQuery, post.name, post.handle, post.body));
  }

  private authorSummary(id: string): DiscoveryAuthor {
    const post = POSTS.find((item: MockPost) => item.id === id);
    return { id: post?.id ?? '', name: post?.name ?? '', handle: post?.handle ?? '',
      avatarColor: post?.avatarColor ?? '', followed: this.followedIds.includes(id),
      postCount: post === undefined || this.hiddenIds.includes(id) ? 0 : 1 };
  }

  private discoveryAuthors(): DiscoveryAuthor[] {
    return POSTS.filter((post: MockPost) => matchesPost(this.searchQuery, post.name, post.handle, ''))
      .map((post: MockPost) => this.authorSummary(post.id));
  }

  private profilePosts(): MockPost[] {
    return this.timelinePosts.filter((post: MockPost) => this.libraryMode === 1 ? this.savedIds.includes(post.id) :
      this.libraryMode === 2 ? this.likedIds.includes(post.id) : post.local === true);
  }

  private openAuthor(id: string): void {
    const post = POSTS.find((item: MockPost) => item.id === id);
    if (this.detailPaths.size() > 0 || post === undefined) { return; }
    this.rememberReadingPosition();
    this.timelineVisible = false;
    this.detailPaths.pushPath({ name: AUTHOR_PROFILE, param: post, onPop: () => this.onPageShow() },
      this.allowsMotionFeedback());
  }

  private async loadIdentity(): Promise<void> {
    if (this.identityBusy || this.identityReady) { return; }
    this.identityBusy = true;
    this.identityMessage = '';
    try {
      const store = await this.identityPreferences();
      const raw = await store.get(IDENTITY_KEY, '');
      if (typeof raw !== 'string') { throw new Error('Invalid identity store'); }
      this.identity = decodeIdentity(raw);
      this.applyLibrary(this.library);
      this.identityReady = true;
    } catch (_error) {
      this.identityMessage = '本机资料暂时无法读取，点「编辑资料」重试。';
    } finally {
      this.identityBusy = false;
    }
  }

  private async identityPreferences(): Promise<preferences.Preferences> {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) { throw new Error('Identity host context unavailable'); }
    return preferences.getPreferences(context, { name: IDENTITY_STORE });
  }

  private async openIdentity(): Promise<void> {
    if (this.detailPaths.size() > 0 || this.identityBusy) { return; }
    if (!this.identityReady) { await this.loadIdentity(); }
    if (!this.identityReady || this.detailPaths.size() > 0 || this.selectedTab !== ShellTab.Profile) { return; }
    this.identityName = this.identity.name;
    this.identityBio = this.identity.bio;
    this.identityConfirmLeave = false;
    this.identityMessage = '';
    this.detailPaths.pushPath({ name: IDENTITY_EDITOR, onPop: () => this.onPageShow() }, this.allowsMotionFeedback());
  }

  private requestIdentityBack(): void {
    if (this.identityBusy) { return; }
    if (this.identityConfirmLeave) { this.identityConfirmLeave = false; }
    else if (this.identityName !== this.identity.name || this.identityBio !== this.identity.bio) {
      this.identityConfirmLeave = true;
    } else { this.closePost(); }
  }

  private async saveIdentity(): Promise<void> {
    const value = normalizeIdentity(this.identityName, this.identityBio);
    if (this.identityBusy || this.identityConfirmLeave || value === undefined) { return; }
    this.identityBusy = true;
    try {
      const store = await this.identityPreferences();
      await store.put(IDENTITY_KEY, JSON.stringify(value));
      await store.flush();
      this.identity = value;
      this.applyLibrary(this.library);
      this.closePost();
    } catch (_error) {
      this.identityMessage = '未能保存，本次输入仍在。';
    } finally {
      this.identityBusy = false;
    }
  }

  private currentPostBody(post: MockPost): string {
    return post.local ? this.timelinePosts.find((item: MockPost) => item.id === post.id)?.body ?? post.body : post.body;
  }

  private async copyPost(post: MockPost): Promise<void> {
    try {
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.currentPostBody(post)));
      this.inform('已复制正文');
    } catch (_error) { this.inform('无法复制，请重试。'); }
  }

  private async sharePost(post: MockPost): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const data = new systemShare.SharedData({ utd: 'general.plain-text', content: this.currentPostBody(post),
        title: post.local ? '本机帖子' : '示例帖子' });
      await new systemShare.ShareController(data).show(context, { anchor: 'post-menu-' + post.id });
    } catch (_error) { this.inform('系统分享不可用，可以复制正文。'); }
  }

  @Builder
  PostMenu(post: MockPost) {
    Menu() {
      MenuItem({ content: '复制正文' }).onClick(() => { this.copyPost(post); })
      MenuItem({ content: '系统分享…' }).onClick(() => { this.sharePost(post); })
      if (post.local) {
        MenuItem({ content: '编辑本机帖子' }).onClick(() => this.openPostEditor(post))
      } else {
        MenuItem({ content: this.hiddenIds.includes(post.id) ? '恢复显示' : '隐藏此示例' })
          .onClick(() => { this.toggleHidden(post.id); })
      }
    }
  }

  private async toggleHidden(id: string): Promise<void> {
    if (!POSTS.some((post: MockPost) => post.id === id)) { return; }
    this.rememberReadingPosition();
    if (await this.saveLibrary(updateLibrary(this.library, { hiddenIds: this.nextSelection(this.hiddenIds, id) }))) {
      this.inform(this.hiddenIds.includes(id) ? '已从首页和发现隐藏，可在设置中恢复。' : '已恢复显示');
      this.onReadingLayoutChange();
    }
  }

  private async restoreHidden(): Promise<void> {
    if (this.hiddenIds.length > 0 && await this.saveLibrary(updateLibrary(this.library, { hiddenIds: [] }))) {
      this.restorePending = true;
      this.inform('已恢复所有示例帖子');
    }
  }

  private openPostEditor(post: MockPost): void {
    const paths = this.detailPaths.getAllPathName();
    if (!post.local || !this.libraryReady || this.libraryBusy || this.replyExpanded || this.replyExitPending ||
      (paths.length > 0 && (paths.length !== 1 || paths[0] !== POST_DETAIL))) { return; }
    const stored = this.library.posts.find((item: LibraryPost) => item.id === post.id);
    if (stored === undefined) { return; }
    this.rememberReadingPosition();
    this.timelineVisible = false;
    this.editingPostId = stored.id;
    this.editBody = stored.body;
    this.editMessage = '';
    this.editConfirmLeave = false;
    this.detailPaths.pushPath({ name: POST_EDITOR, onPop: () => this.onPageShow() }, this.allowsMotionFeedback());
  }

  private requestPostEditorBack(): void {
    if (this.libraryBusy) { return; }
    const stored = this.library.posts.find((post: LibraryPost) => post.id === this.editingPostId);
    if (this.editConfirmLeave) { this.editConfirmLeave = false; }
    else if (stored !== undefined && stored.body !== this.editBody) { this.editConfirmLeave = true; }
    else { this.leaveComposer(); }
  }

  private async savePostEdit(): Promise<void> {
    if (this.editConfirmLeave || !this.isValidPostBody(this.editBody) ||
      !this.library.posts.some((post: LibraryPost) => post.id === this.editingPostId)) { return; }
    const posts = this.library.posts.map((post: LibraryPost): LibraryPost =>
      post.id === this.editingPostId ? { id: post.id, body: this.editBody } : post);
    if (await this.saveLibrary(updateLibrary(this.library, { posts: posts }))) { this.leaveComposer(); }
    else { this.editMessage = '未能保存，本次输入仍在。'; }
  }

  private async removeReply(reply: DemoReply): Promise<void> {
    if (this.menuOpen || this.libraryBusy) { return; }
    this.menuOpen = true;
    try {
      const decision = await this.getUIContext().getPromptAction().showDialog({ title: '删除本机回复？',
        message: '这条回复及其下的本机回复会删除，不会影响 Threads。',
        buttons: [{ text: '取消', color: '' }, { text: '删除', color: '' }] });
      if (decision.index !== 1) { return; }
      const removed: string[] = [reply.id];
      for (let i = 0; i < removed.length; i++) {
        this.library.replies.forEach((row: LibraryReply) => {
          if (row.parentId === removed[i] && !removed.includes(row.id)) { removed.push(row.id); }
        });
      }
      if (await this.saveLibrary(updateLibrary(this.library, { replies: this.library.replies.filter((row: LibraryReply) =>
        !removed.includes(row.id)) }))) { this.inform('已删除本机回复'); }
    } catch (_error) {
      // Dismissal leaves the discussion unchanged.
    } finally { this.menuOpen = false; }
  }

  private async removeLocalPost(post: MockPost): Promise<void> {
    if (!post.local || !this.confirmingDelete || this.libraryBusy) {
      return;
    }
    const saved = await this.saveLibrary(updateLibrary(this.library, {
      posts: this.library.posts.filter((item: LibraryPost) => item.id !== post.id),
      likedIds: this.likedIds.filter((id: string) => id !== post.id),
      savedIds: this.savedIds.filter((id: string) => id !== post.id),
      replies: this.library.replies.filter((row: LibraryReply) => row.postId !== post.id)
    }));
    if (saved) {
      this.confirmingDelete = false;
      if (this.readingAnchor.postId === post.id) {
        this.readingAnchor = { postId: '', clipped: 0 };
      }
      this.restorePending = true;
      this.closePost();
    }
  }

  private async postDraftPreferences(): Promise<preferences.Preferences> {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      throw new Error('Timeline host context unavailable');
    }
    return preferences.getPreferences(context, { name: POST_DRAFT_STORE });
  }

  private openComposer(): void {
    if (this.detailPaths.size() > 0) {
      return;
    }
    this.rememberReadingPosition();
    this.timelineVisible = false;
    this.postDraft = this.savedPostDraft;
    this.postDraftMessage = '';
    this.draftDecision = DraftDecision.None;
    this.detailPaths.pushPath({ name: POST_COMPOSER, onPop: () => {
      this.postDraftLoadId += 1;
      this.postDraftBusy = false;
      this.closePostPreview();
      this.onPageShow();
    } }, this.allowsMotionFeedback());
    if (!this.postDraftReady) {
      this.loadPostDraft();
    }
  }

  private async loadPostDraft(): Promise<void> {
    if (this.postDraftReady || this.postDraftBusy) {
      return;
    }
    const loadId = ++this.postDraftLoadId;
    this.postDraftBusy = true;
    this.postDraftMessage = '';
    try {
      const store = await this.postDraftPreferences();
      const body = await store.get(POST_DRAFT_KEY, '');
      if (loadId !== this.postDraftLoadId) {
        return;
      }
      if (typeof body !== 'string' || body.length > POST_DRAFT_LIMIT) {
        throw new Error('Invalid local draft');
      }
      this.savedPostDraft = body;
      this.postDraft = body;
      this.postDraftReady = true;
    } catch (_error) {
      if (loadId === this.postDraftLoadId) {
        this.postDraftMessage = '草稿暂时无法读取，请重试。';
      }
    } finally {
      if (loadId === this.postDraftLoadId) {
        this.postDraftBusy = false;
      }
    }
  }

  private isValidPostBody(body: string): boolean {
    return body.length <= POST_DRAFT_LIMIT && body.trim().length > 0;
  }

  private canSavePostDraft(): boolean {
    return this.postDraftReady && !this.postDraftBusy && this.isValidPostBody(this.postDraft) &&
      this.postDraft !== this.savedPostDraft;
  }

  private canPreviewPostDraft(): boolean {
    return this.postDraftReady && !this.postDraftBusy && this.draftDecision === DraftDecision.None &&
      !this.showingPostPreview && this.isValidPostBody(this.postDraft);
  }

  private openPostPreview(): void {
    if (!this.canPreviewPostDraft()) {
      return;
    }
    this.previewBody = this.postDraft;
    this.showingPostPreview = true;
  }

  private closePostPreview(): void {
    this.showingPostPreview = false;
    this.previewBody = '';
  }

  private async addPreviewToTimeline(): Promise<void> {
    if (!this.showingPostPreview || !this.isValidPostBody(this.previewBody) || this.libraryBusy || !this.libraryReady) {
      return;
    }
    if (this.library.posts.length >= LIBRARY_POST_LIMIT) {
      this.inform('本机帖子已满，请在「我的」中删除不再需要的帖子。');
      return;
    }
    const body = this.previewBody;
    this.postSequence = Math.max(this.postSequence + 1, Date.now());
    const post: LibraryPost = { id: `local-post-${this.postSequence}`, body: body };
    const saved = await this.saveLibrary(updateLibrary(this.library, { posts: [post, ...this.library.posts] }));
    if (saved) {
      this.selectedTab = ShellTab.Home;
      this.followingOnly = false;
      this.closePostPreview();
      this.postDraft = this.savedPostDraft;
      this.readingAnchor = { postId: '', clipped: 0 };
      this.restorePending = true;
      this.leaveComposer();
    }
  }

  private leaveComposer(): void {
    this.detailPaths.pop({ closed: true }, this.allowsMotionFeedback());
  }

  private requestComposerExit(): void {
    if ((this.postDraftReady && this.postDraftBusy) || (this.showingPostPreview && this.libraryBusy)) {
      return;
    }
    if (this.showingPostPreview) {
      this.closePostPreview();
    } else if (this.draftDecision !== DraftDecision.None) {
      this.draftDecision = DraftDecision.None;
    } else if (this.postDraft !== this.savedPostDraft) {
      this.draftDecision = DraftDecision.Leave;
    } else {
      this.leaveComposer();
    }
  }

  private discardPostEdits(): void {
    if (this.draftDecision === DraftDecision.Leave && !this.postDraftBusy) {
      this.postDraft = this.savedPostDraft;
      this.leaveComposer();
    }
  }

  private async savePostDraft(clear: boolean): Promise<void> {
    if (clear ? (!this.postDraftReady || this.postDraftBusy || this.draftDecision !== DraftDecision.Clear)
      : !this.canSavePostDraft()) {
      return;
    }
    const body = clear ? '' : this.postDraft;
    this.postDraftBusy = true;
    this.postDraftMessage = '';
    this.draftDecision = DraftDecision.None;
    try {
      const store = await this.postDraftPreferences();
      await store.put(POST_DRAFT_KEY, body);
      await store.flush();
      this.savedPostDraft = body;
      this.postDraft = body;
      this.postDraftMessage = clear ? '本机草稿已清空。' : '草稿已保存到本机。';
    } catch (_error) {
      this.postDraftMessage = '未能写入本机，当前文字仍保留。';
    } finally {
      this.postDraftBusy = false;
    }
  }

  @Builder
  FollowAction(post: MockPost) {
    Button(this.followedIds.includes(post.id) ? '已关注' : '关注')
      .id('follow-' + post.id).buttonStyle(ButtonStyleMode.TEXTUAL)
      .constraintSize({ minWidth: 48, minHeight: 44 }).padding({ left: 6, right: 6 })
      .fontSize(13).fontColor($r('app.color.timeline_text_secondary'))
      .accessibilitySelected(this.followedIds.includes(post.id))
      .enabled(this.libraryReady && !this.libraryBusy).onClick(() => { this.toggleFollow(post.id); })
  }

  @Builder
  PostActions(post: MockPost, inDetail: boolean) {
    Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
      Button({ type: ButtonType.Capsule }) {
        Row({ space: 5 }) {
          if (this.allowsMotionFeedback()) {
            SymbolGlyph(this.likedIds.includes(post.id) ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
              .fontSize(17).fontColor([this.likedIds.includes(post.id) ? $r('app.color.timeline_like') : $r('app.color.timeline_text_secondary')])
              .symbolEffect(new BounceSymbolEffect(EffectScope.WHOLE), this.animationTriggerFor(post.id))
          } else {
            SymbolGlyph(this.likedIds.includes(post.id) ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
              .fontSize(17).fontColor([this.likedIds.includes(post.id) ? $r('app.color.timeline_like') : $r('app.color.timeline_text_secondary')])
          }
          Text(String(post.likes + (this.likedIds.includes(post.id) ? 1 : 0))).fontSize(12).fontColor($r('app.color.timeline_text_secondary'))
        }
      }.id('like-' + post.id).buttonStyle(ButtonStyleMode.TEXTUAL).constraintSize({ minHeight: 44, minWidth: 48 })
        .padding({ left: 0, right: 10 }).accessibilityText(this.likedIds.includes(post.id) ? '取消点赞' : '点赞')
        .accessibilitySelected(this.likedIds.includes(post.id)).enabled(this.libraryReady && !this.libraryBusy)
        .onClick(() => { this.toggleLike(post.id); })
      if (!inDetail) {
        Button({ type: ButtonType.Capsule }) {
          Row({ space: 5 }) {
            SymbolGlyph($r('sys.symbol.message')).fontSize(17).fontColor([$r('app.color.timeline_text_secondary')])
            Text(String(this.replyCount(post))).fontSize(12).fontColor($r('app.color.timeline_text_secondary'))
          }
        }.id('replies-' + post.id).constraintSize({ minWidth: 48, minHeight: 44 }).buttonStyle(ButtonStyleMode.TEXTUAL)
          .padding({ left: 8, right: 10 }).accessibilityText('查看' + post.name + '的帖子详情，' + this.replyCount(post) + ' 条回复')
          .onClick(() => this.openPost(post))
      }
      Blank().layoutWeight(1)
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph(this.savedIds.includes(post.id) ? $r('sys.symbol.bookmark_fill') : $r('sys.symbol.bookmark'))
          .fontSize(17).fontColor([$r('app.color.timeline_text_secondary')])
      }.id('save-' + post.id).width(44).height(44).buttonStyle(ButtonStyleMode.TEXTUAL)
        .accessibilityText(this.savedIds.includes(post.id) ? '已收藏' : '收藏').accessibilitySelected(this.savedIds.includes(post.id))
        .enabled(this.libraryReady && !this.libraryBusy).onClick(() => { this.toggleSaved(post); })
      Button({ type: ButtonType.Circle }) {
        Text('···').fontSize('20vp').fontColor($r('app.color.timeline_text_secondary')).accessibilityLevel('no')
      }.id('post-menu-' + post.id).width(44).height(44).buttonStyle(ButtonStyleMode.TEXTUAL)
        .accessibilityText('帖子操作')
        .enabled(!this.libraryBusy && (!inDetail || (!this.replyExpanded && !this.replyExitPending && !this.confirmingDelete)))
        .bindMenu(this.PostMenu(post))
    }.width('100%')
  }

  @Builder
  SummaryEntry(post: MockPost, reply?: DemoReply) {
    if (reply !== undefined) {
      Row({ space: 12 }) {
        Column({ space: 3 }) {
          Divider().vertical(true).height(8).strokeWidth(1).color($r('app.color.timeline_border'))
          Text(reply.author.substring(0, 1)).width(22).height(22).fontSize('11vp')
            .backgroundColor($r('app.color.timeline_surface_muted')).fontColor($r('app.color.timeline_text_secondary'))
            .borderRadius(11).textAlign(TextAlign.Center).accessibilityLevel('no')
        }.width(36)
        Text(reply.author + '：' + reply.body)
          .fontSize(13).fontColor($r('app.color.timeline_text_secondary')).layoutWeight(1)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.width('100%').constraintSize({ minHeight: 44 }).accessibilityGroup(true)
        .id('summary-' + post.id).accessibilityText('查看回复：' + reply.author)
        .onClick(() => this.openPost(post, reply.id))
    }
  }

  @Builder
  PostCard(post: MockPost, inDetail: boolean, authorLink: boolean = true) {
    Column() {
      Row({ space: 12 }) {
        Text(post.name.substring(0, 1)).width(36).height(36).fontSize('15vp').fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.timeline_on_avatar')).textAlign(TextAlign.Center).backgroundColor(post.avatarColor)
          .borderRadius(18).accessibilityLevel('no')
        Column({ space: 4 }) {
          Row({ space: 4 }) {
            Column({ space: 2 }) {
              if (authorLink && !inDetail && !post.local) {
                Text(post.name).id('post-author-' + post.id).fontSize(16).fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.timeline_text_primary')).accessibilityText('查看作者 ' + post.name)
                  .onClick(() => this.openAuthor(post.id))
              } else {
                Text(post.local ? this.identity.name : post.name).fontSize(16).fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.timeline_text_primary'))
              }
              Text(post.handle + ' · ' + post.time).fontSize(12).fontColor($r('app.color.timeline_text_secondary'))
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            if (!post.local && this.fontScale < LARGE_TEXT_SCALE && this.viewportWidth >= 360) { this.FollowAction(post) }
          }.width('100%')
          if (!post.local && (this.fontScale >= LARGE_TEXT_SCALE || this.viewportWidth < 360)) { this.FollowAction(post) }
          if (inDetail) {
            Text(this.currentPostBody(post)).fontSize(16).fontColor($r('app.color.timeline_text_body')).width('100%')
              .textAlign(TextAlign.Start).copyOption(CopyOptions.InApp)
          } else {
            Text(post.body).id('body-' + post.id).fontSize(16).fontColor($r('app.color.timeline_text_body')).width('100%')
              .textAlign(TextAlign.Start).accessibilityText('打开原帖：' + post.body).onClick(() => this.openPost(post))
          }
          this.PostActions(post, inDetail)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%').alignItems(VerticalAlign.Top)
      if (!inDetail) {
        ForEach(this.previewRows(post.id), (reply: DemoReply) => {
          this.SummaryEntry(post, reply)
        }, (reply: DemoReply) => reply.id)
      }
      Divider().strokeWidth(0.5).color($r('app.color.timeline_border')).margin({ top: 6 })
    }.width('100%').constraintSize({ maxWidth: 600 }).padding({ top: 14 })
  }

  @Builder
  DiscussionRoot(post: MockPost) {
    Column({ space: 6 }) {
      this.PostCard(post, true)
      if (post.local) {
        if (this.confirmingDelete) {
          Text('删除本机帖子和相关互动？').fontSize(14).fontColor($r('app.color.timeline_text_secondary'))
          Button('取消删除').buttonStyle(ButtonStyleMode.TEXTUAL).enabled(!this.libraryBusy)
            .onClick(() => { this.confirmingDelete = false; })
          Button('确认删除').buttonStyle(ButtonStyleMode.TEXTUAL).enabled(!this.libraryBusy)
            .onClick(() => { this.removeLocalPost(post); })
        } else {
          Button('删除本机帖子').buttonStyle(ButtonStyleMode.TEXTUAL)
            .enabled(this.libraryReady && !this.libraryBusy && !this.replyExpanded && !this.replyExitPending)
            .onClick(() => { this.confirmingDelete = true; })
        }
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  DetailContent(post: MockPost) {
    ConversationPane({ rootPost: () => { this.DiscussionRoot(post) }, rootAuthor: post.name, rows: this.repliesFor(post.id),
      focusId: this.focusedReplyId, recipient: this.replyRecipient(post), contextLine: this.targetRow(post.id)?.body ?? this.currentPostBody(post),
      expanded: this.replyExpanded, draft: this.replyDraft, confirmLeave: this.replyExitPending, largeText: this.toolbarInList(),
      busy: this.libraryBusy,
      onBack: () => this.requestDetailBack(), onEdit: (id: string) => this.beginReply(post.id, id),
      onExpand: () => this.expandCurrentReply(post.id), onDraft: (value: string) => { this.replyDraft = value; },
      onSend: () => this.submitReply(post.id), onDiscard: () => this.discardReplyAndClose(), onKeep: () => this.keepReplyDraft() })
  }

  @Builder
  PostPreviewContent() {
    Scroll() {
      Column({ space: 18 }) {
        Button('返回编辑', { type: ButtonType.Capsule })
          .constraintSize({ minHeight: 48 }).padding({ left: 16, right: 16 })
          .backgroundColor($r('app.color.timeline_toolbar_button')).fontColor($r('app.color.timeline_text_body'))
          .enabled(!this.libraryBusy).onClick(() => this.closePostPreview())
        Column({ space: 6 }) {
          Text('帖子预览').fontSize(28).fontWeight(FontWeight.Bold).fontColor($r('app.color.timeline_text_primary'))
          Text('保存到这台设备，不会发送到 Threads，也不会更改已保存的草稿。')
            .fontSize(14).fontColor($r('app.color.timeline_text_secondary'))
        }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 12 }) {
          Text(this.identity.name + ' · 本机预览').fontSize(15).fontWeight(FontWeight.Bold).fontColor($r('app.color.timeline_text_primary'))
          Text(this.previewBody).width('100%').fontSize(15).textAlign(TextAlign.Start)
            .fontColor($r('app.color.timeline_text_body')).copyOption(CopyOptions.InApp)
        }.width('100%').padding(18).alignItems(HorizontalAlign.Start)
          .backgroundColor($r('app.color.timeline_surface')).borderRadius(22)
          .border({ width: 1, color: $r('app.color.timeline_border') })
        Button(this.libraryBusy ? '正在保存…' : '加入本机时间线', { type: ButtonType.Capsule })
          .width('100%').constraintSize({ minHeight: 48 }).padding({ left: 16, right: 16, top: 10, bottom: 10 })
          .backgroundColor($r('app.color.timeline_action')).fontColor($r('app.color.timeline_on_action'))
          .enabled(this.libraryReady && !this.libraryBusy).onClick(() => { this.addPreviewToTimeline(); })
        this.LibraryStatus()
      }.width('100%').constraintSize({ maxWidth: 600 }).alignItems(HorizontalAlign.Start)
        .padding({ left: 18, right: 18, top: 16, bottom: 24 })
    }.width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Auto)
  }

  @Builder
  ComposerContent() {
    Scroll() {
      Column({ space: 18 }) {
        Button('返回', { type: ButtonType.Capsule })
          .constraintSize({ minHeight: 48 }).padding({ left: 16, right: 16 })
          .backgroundColor($r('app.color.timeline_toolbar_button')).fontColor($r('app.color.timeline_text_body'))
          .enabled(!this.postDraftReady || !this.postDraftBusy)
          .onClick(() => this.requestComposerExit())
        Column({ space: 6 }) {
          Text('写帖草稿').fontSize(28).fontWeight(FontWeight.Bold).fontColor($r('app.color.timeline_text_primary'))
          Text('只保存在这台设备，不会发布到 Threads。').fontSize(14).fontColor($r('app.color.timeline_text_secondary'))
        }.width('100%').alignItems(HorizontalAlign.Start)
        if (this.postDraftReady) {
          Column({ space: 12 }) {
            TextArea({ text: this.postDraft, placeholder: '此刻，想写点什么？' })
              .width('100%').constraintSize({ minHeight: 140, maxHeight: 260 }).maxLength(POST_DRAFT_LIMIT)
              .fontSize(16).fontColor($r('app.color.timeline_text_body')).placeholderColor($r('app.color.timeline_text_muted'))
              .backgroundColor($r('app.color.timeline_background')).borderRadius(16)
              .accessibilityText('写帖草稿正文')
              .enabled(!this.postDraftBusy && this.draftDecision === DraftDecision.None)
              .onChange((value: string) => { this.postDraft = value; this.postDraftMessage = ''; })
            Text(`${this.postDraft.length} / ${POST_DRAFT_LIMIT}`).fontSize(12)
              .fontColor($r('app.color.timeline_text_secondary'))
            if (this.draftDecision === DraftDecision.None) {
              Button(this.postDraftBusy ? '正在写入本机…' : '保存到本机', { type: ButtonType.Capsule })
                .width('100%').constraintSize({ minHeight: 48 }).padding({ left: 16, right: 16, top: 10, bottom: 10 })
                .backgroundColor($r('app.color.timeline_action')).fontColor($r('app.color.timeline_on_action'))
                .enabled(this.canSavePostDraft()).onClick(() => { this.savePostDraft(false); })
              Button('预览帖子', { type: ButtonType.Capsule })
                .width('100%').constraintSize({ minHeight: 48 }).padding({ left: 16, right: 16, top: 10, bottom: 10 })
                .backgroundColor($r('app.color.timeline_toolbar_button')).fontColor($r('app.color.timeline_text_body'))
                .enabled(this.canPreviewPostDraft()).onClick(() => this.openPostPreview())
              if (this.savedPostDraft.length > 0 && !this.postDraftBusy) {
                Button('清空本机草稿', { type: ButtonType.Capsule })
                  .constraintSize({ minHeight: 48 }).buttonStyle(ButtonStyleMode.TEXTUAL)
                  .fontColor($r('app.color.timeline_text_body'))
                  .onClick(() => { this.draftDecision = DraftDecision.Clear; })
              }
            }
          }.width('100%').padding(18).alignItems(HorizontalAlign.Start)
            .backgroundColor($r('app.color.timeline_surface')).borderRadius(22)
            .border({ width: 1, color: $r('app.color.timeline_border') })
        } else if (this.postDraftBusy) {
          Text('正在读取本机草稿…').fontSize(14).fontColor($r('app.color.timeline_text_secondary'))
        } else {
          Button('重新读取草稿').constraintSize({ minHeight: 48 }).onClick(() => { this.loadPostDraft(); })
        }
        if (this.draftDecision !== DraftDecision.None) {
          Column({ space: 10 }) {
            Text(this.draftDecision === DraftDecision.Clear ? '清空已经保存的草稿？' : '放弃未保存的修改？')
              .fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('app.color.timeline_text_primary'))
            Text(this.draftDecision === DraftDecision.Clear ? '已保存的内容与当前修改都会清空。' : '之前保存到本机的内容会保留。')
              .fontSize(13).fontColor($r('app.color.timeline_text_secondary'))
            Button('继续编辑', { type: ButtonType.Capsule })
              .width('100%').constraintSize({ minHeight: 48 }).padding({ left: 16, right: 16 })
              .backgroundColor($r('app.color.timeline_action')).fontColor($r('app.color.timeline_on_action'))
              .onClick(() => { this.draftDecision = DraftDecision.None; })
            Button(this.draftDecision === DraftDecision.Clear ? '确认清空' : '放弃修改并返回')
              .constraintSize({ minHeight: 48 }).buttonStyle(ButtonStyleMode.TEXTUAL)
              .fontColor($r('app.color.timeline_text_body'))
              .onClick(() => {
                if (this.draftDecision === DraftDecision.Clear) {
                  this.savePostDraft(true);
                } else {
                  this.discardPostEdits();
                }
              })
          }.width('100%').alignItems(HorizontalAlign.Start).padding(18)
            .backgroundColor($r('app.color.timeline_surface')).borderRadius(18)
        }
        if (this.postDraftMessage.length > 0) {
          Text(this.postDraftMessage).fontSize(14).fontColor($r('app.color.timeline_text_secondary'))
        }
      }.width('100%').constraintSize({ maxWidth: 600 }).alignItems(HorizontalAlign.Start)
        .padding({ left: 18, right: 18, top: 16, bottom: 24 })
    }.width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Auto)
  }

  @Builder
  LibraryStatus() {
    if (this.libraryLoading) {
      Text('正在读取本机内容…').fontSize(13).fontColor($r('app.color.timeline_text_secondary'))
    } else if (this.libraryMessage.length > 0) {
      Text(this.libraryMessage).fontSize(13).fontColor($r('app.color.timeline_text_secondary'))
      if (!this.libraryReady) {
        Button('重试读取').constraintSize({ minHeight: 48 }).onClick(() => { this.loadLibrary(); })
      }
    }
  }

  @Builder
  DiscoveryPostRows() {
    ForEach(this.discoveryPosts(), (post: MockPost) => {
      ListItem() { this.PostCard(post, false) }
    }, (post: MockPost) => post.id + ':' + post.body)
  }

  @Builder
  AuthorPostRows(post: MockPost) {
    if (!this.hiddenIds.includes(post.id)) {
      ListItem() { this.PostCard(post, false, false) }
    }
  }

  @Builder
  ProfileItems() {
    if (this.libraryMode === 3) {
      ForEach(this.localReplies, (reply: DemoReply) => {
        Column({ space: 4 }) {
          Button({ type: ButtonType.Normal }) {
            Column({ space: 5 }) {
              Text('回复 '+ (reply.toAuthor ?? '原帖')).fontSize(13).fontColor($r('app.color.timeline_text_secondary'))
              Text(reply.body).fontSize(16).fontColor($r('app.color.timeline_text_body')).wordBreak(WordBreak.BREAK_WORD)
            }.width('100%').alignItems(HorizontalAlign.Start)
          }.id('profile-reply-' + reply.id).width('100%').constraintSize({ minHeight: 48 })
            .padding({ left: 0, right: 0 }).buttonStyle(ButtonStyleMode.TEXTUAL)
            .onClick(() => this.openActivityPost({ id: 'reply-' + reply.id, postId: reply.postId,
              author: reply.author, body: reply.body, kind: 'reply' }))
          Button('删除回复').buttonStyle(ButtonStyleMode.TEXTUAL).constraintSize({ minHeight: 44 })
            .enabled(this.libraryReady && !this.libraryBusy).fontColor($r('app.color.timeline_text_secondary'))
            .onClick(() => { this.removeReply(reply); })
          Divider().strokeWidth(0.5).color($r('app.color.timeline_border'))
        }.width('100%').alignItems(HorizontalAlign.Start)
      }, (reply: DemoReply) => reply.id)
    } else {
      ForEach(this.profilePosts(), (post: MockPost) => { this.PostCard(post, false) },
        (post: MockPost) => post.id + ':' + post.body)
    }
  }

  @Builder
  EditorDecision(onContinue: () => void, onDiscard: () => void) {
    Column({ space: 8 }) {
      Text('放弃未保存的修改？').fontSize(17).fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.timeline_text_primary'))
      Button('继续编辑').constraintSize({ minHeight: 48 })
        .backgroundColor($r('app.color.timeline_action')).fontColor($r('app.color.timeline_on_action'))
        .onClick(() => onContinue())
      Button('放弃修改并返回').constraintSize({ minHeight: 48 }).buttonStyle(ButtonStyleMode.TEXTUAL)
        .fontColor($r('app.color.timeline_text_body')).onClick(() => onDiscard())
    }.width('100%').alignItems(HorizontalAlign.Start).padding(20)
  }

  @Builder
  PostEditorContent() {
    Scroll() {
      Column({ space: 14 }) {
        Button('返回').buttonStyle(ButtonStyleMode.TEXTUAL).constraintSize({ minHeight: 48 })
          .fontColor($r('app.color.timeline_text_body')).onClick(() => this.requestPostEditorBack())
        Text('编辑本机帖子').fontSize(26).fontWeight(FontWeight.Bold).fontColor($r('app.color.timeline_text_primary'))
        Text('只修改这台设备上的正文，原讨论和互动会保留。')
          .fontSize(14).fontColor($r('app.color.timeline_text_secondary'))
        if (this.editConfirmLeave) {
          this.EditorDecision(() => { this.editConfirmLeave = false; }, () => this.leaveComposer())
        } else {
          TextArea({ text: this.editBody, placeholder: '帖子正文' }).id('post-editor-input')
            .width('100%').constraintSize({ minHeight: 140, maxHeight: 260 }).maxLength(POST_DRAFT_LIMIT)
            .fontSize(16).fontColor($r('app.color.timeline_text_body'))
            .backgroundColor($r('app.color.timeline_surface_muted')).enabled(!this.libraryBusy)
            .onChange((value: string) => { this.editBody = value; this.editMessage = ''; })
          Text(this.editBody.length + ' / ' + POST_DRAFT_LIMIT).fontSize(13)
            .fontColor($r('app.color.timeline_text_secondary'))
          Button('保存修改').id('post-editor-save').width('100%').constraintSize({ minHeight: 48 })
            .backgroundColor($r('app.color.timeline_action')).fontColor($r('app.color.timeline_on_action'))
            .enabled(!this.libraryBusy && this.isValidPostBody(this.editBody)).onClick(() => { this.savePostEdit(); })
          if (this.editMessage) {
            Text(this.editMessage).fontSize(14).fontColor($r('app.color.timeline_text_secondary'))
          }
        }
      }.width('100%').constraintSize({ maxWidth: 640 }).alignItems(HorizontalAlign.Start).padding(18)
    }.width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Auto)
  }

  @Builder
  DetailDestination(name: string, post?: MockPost) {
    if (name === POST_COMPOSER) {
      NavDestination() {
        if (this.showingPostPreview) {
          this.PostPreviewContent()
        } else {
          this.ComposerContent()
        }
      }.hideTitleBar(true).backgroundColor($r('app.color.timeline_background'))
        .onBackPressed(() => {
          this.requestComposerExit();
          return true;
        })
    } else if (name === POST_SETTINGS) {
      NavDestination() {
        SettingsPane({
          reduceMotion: this.reduceMotion, systemReducesMotion: this.systemReducesMotion,
          motionPreferenceReady: this.motionPreferenceReady, motionPreferenceSaving: this.motionPreferenceSaving,
          motionPreferenceWarning: this.motionPreferenceWarning, openingWeb: this.openingWeb,
          onClose: () => this.closePost(), onMotionChange: (enabled: boolean) => { this.updateMotionPreference(enabled); },
          onWeb: () => { this.openWeb(); }, hiddenCount: this.hiddenIds.length, libraryBusy: this.libraryBusy,
           onRestoreHidden: () => { this.restoreHidden(); }
        })
      }.hideTitleBar(true).backgroundColor($r('app.color.timeline_background'))
        .onBackPressed(() => { this.closePost(); return true; })
    } else if (name === IDENTITY_EDITOR) {
      NavDestination() {
        if (this.identityConfirmLeave) {
          this.EditorDecision(() => { this.identityConfirmLeave = false; }, () => this.closePost())
        } else {
          IdentityEditor({ name: this.identityName, bio: this.identityBio, busy: this.identityBusy, message: this.identityMessage,
            onName: (value: string) => { this.identityName = value; this.identityMessage = ''; },
            onBio: (value: string) => { this.identityBio = value; this.identityMessage = ''; },
            onSave: () => { this.saveIdentity(); }, onBack: () => this.requestIdentityBack() })
        }
      }.hideTitleBar(true).backgroundColor($r('app.color.timeline_surface'))
        .onBackPressed(() => { this.requestIdentityBack(); return true; })
    } else if (name === POST_EDITOR) {
      NavDestination() { this.PostEditorContent() }.hideTitleBar(true).backgroundColor($r('app.color.timeline_surface'))
        .onBackPressed(() => { this.requestPostEditorBack(); return true; })
    } else if (name === AUTHOR_PROFILE && post !== undefined) {
      NavDestination() {
        AuthorPane({ author: this.authorSummary(post.id), posts: () => { this.AuthorPostRows(post) },
          onBack: () => this.closePost(), onFollow: () => { this.toggleFollow(post.id); } })
      }.hideTitleBar(true).backgroundColor($r('app.color.timeline_surface'))
        .onBackPressed(() => { this.closePost(); return true; })
    } else if (name === POST_DETAIL && post !== undefined) {
      NavDestination() {
        this.DetailContent(post)
      }.hideTitleBar(true).backgroundColor($r('app.color.timeline_surface'))
        .onBackPressed(() => {
          this.requestDetailBack();
          return true;
        })
    }
  }

  @Builder
  Toolbar() {
    Column({ space: 7 }) {
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center, justifyContent: FlexAlign.SpaceBetween,
        space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(4) } }) {
        Text('Threads').fontSize(28).fontWeight(FontWeight.Bold).fontColor($r('app.color.timeline_text_primary'))
        Text('本机预览').fontSize(12).fontColor($r('app.color.timeline_text_secondary'))
      }.width('100%')
      TabSegmentButtonV2({ items: this.feedSegments, itemMaxFontScale: 2, selectedIndex: this.followingOnly ? 1 : 0,
        $selectedIndex: (index: number) => this.selectFeed(index === 1) })
        .id('feed-segment').width(this.fontScale >= LARGE_TEXT_SCALE ? '100%' : 176)
      this.LibraryStatus()
    }.width('100%').constraintSize({ maxWidth: MAX_LIST_WIDTH }).alignItems(HorizontalAlign.Start)
      .padding({ left: 18, right: 18, top: 10, bottom: 8 })
  }

  @Builder
  SearchRoot() {
    DiscoveryPane({ query: this.searchQuery, mode: this.discoveryMode, authors: this.discoveryAuthors(),
      topics: DISCOVERY_TOPICS, hasPosts: this.discoveryPosts().length > 0,
      posts: () => { this.DiscoveryPostRows() }, status: () => { this.LibraryStatus() },
      onQuery: (value: string) => { this.searchQuery = value; },
      onMode: (value: number) => { this.discoveryMode = value === 1 ? 1 : 0; },
      onAuthor: (id: string) => this.openAuthor(id),
      onTopic: (topic: string) => { this.searchQuery = topic; this.discoveryMode = 0; } })
  }

  @Builder
  ProfileRoot() {
    LibraryHub({ identity: this.identity, mode: this.libraryMode,
      hasItems: this.libraryMode === 3 ? this.localReplies.length > 0 : this.profilePosts().length > 0,
      busy: this.libraryLoading || this.identityBusy, message: this.identityMessage || this.libraryMessage,
      items: () => { this.ProfileItems() }, onMode: (value: number) => { this.libraryMode = value; },
      onEdit: () => { this.openIdentity(); }, onCompose: () => this.openComposer(), onSettings: () => this.openSettings(),
      onWeb: () => { this.openWeb(); } })
  }

  @Builder
  ActivityRoot() {
    ActivityPane({ entries: this.activityEntries(), onOpen: (entry: ActivityEntry) => this.openActivityPost(entry) })
  }

  @Builder
  Shell() {
    ReadingTabs({ activeIndex: this.selectedTab, wide: this.viewportWidth >= SIDE_NAV_WIDTH,
      home: () => { this.Feed() }, search: () => { this.SearchRoot() },
      activity: () => { this.ActivityRoot() }, profile: () => { this.ProfileRoot() },
      onSelectTab: (index: number) => this.selectTab(index as ShellTab), onCompose: () => this.openComposer() })
      .width('100%').height('100%').backgroundColor($r('app.color.timeline_surface'))
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        const width = Number(newArea.width);
        if (Number.isFinite(width) && width > 0 && width !== this.viewportWidth) { this.viewportWidth = width; }
      })
  }

  @Builder
  Feed() {
    Column() {
      if (!this.toolbarInList()) {
        this.Toolbar()
      }
      List({ scroller: this.timelineScroller }) {
        if (this.toolbarInList()) {
          ListItem() { this.Toolbar() }
        }
        ForEach(this.visibleFeed(), (post: MockPost) => {
          ListItem() { this.PostCard(post, false) }
        }, (post: MockPost) => post.local ? post.id + ':' + post.name + ':' + post.body : post.id)
        if (this.followingOnly && this.visibleFeed().length === 0) {
          ListItem() {
            Column({ space: 8 }) {
              Text('还没有关注内容').fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.timeline_text_primary'))
              Text('在「为你」中关注示例帖子后，可以在这里查看。')
                .fontSize(14).fontColor($r('app.color.timeline_text_secondary'))
              Button('浏览为你').constraintSize({ minHeight: 48 }).onClick(() => this.selectFeed(false))
            }.width('100%').constraintSize({ maxWidth: 600 }).padding(18).alignItems(HorizontalAlign.Start)
              .backgroundColor($r('app.color.timeline_surface')).borderRadius(18)
          }
        }
      }
      .id('home-feed')
      .lanes(this.readingLaneCount(), 12)
      .alignListItem(ListItemAlign.Center)
      .cachedCount(2)
      .layoutWeight(1)
      .width('100%')
      .constraintSize({ maxWidth: MAX_LIST_WIDTH })
      .padding({ left: 18, right: 18, bottom: 12 })
      .scrollBar(BarState.Auto)
      .onScrollIndex((start: number) => { this.firstVisibleIndex = start; })
      .onDidScroll((_offset: number, state: ScrollState) => {
        if (state !== ScrollState.Idle) {
          this.rememberReadingPosition();
        }
      })
      .onScrollStop(() => this.rememberReadingPosition())
    }.width('100%').height('100%')
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        const width = Number(newArea.width);
        if (Number.isFinite(width) && width > 0 && width !== this.contentWidth) {
          const previousWidth = this.contentWidth;
          this.contentWidth = width;
          if (previousWidth > 0 && Math.min(previousWidth, MAX_LIST_WIDTH) !== Math.min(width, MAX_LIST_WIDTH)) {
            this.onReadingLayoutChange();
          }
        }
      })
  }

  build() {
    Navigation(this.detailPaths) {
      this.Shell()
    }
    .width('100%').height('100%').mode(NavigationMode.Stack).hideTitleBar(true)
    .navDestination(this.DetailDestination)
  }
}
