import { accessibility } from '@kit.AccessibilityKit';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { FrameCallback, KeyboardAvoidMode, LengthMetrics, router, SegmentButtonV2Items, TabSegmentButtonV2 } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { systemShare } from '@kit.ShareKit';
import { canPublishThread, decodeLibrary, decodePostDraft, emptyLibrary, encodeLibrary, isPostPhotoKey, LibraryPost, isPostVideoKey,
  LibraryReply, LIBRARY_POST_LIMIT, LIBRARY_REPLY_LIMIT, LOCAL_POST_BODY_LIMIT, LOCAL_REPLY_BODY_LIMIT,
  LocalLibrary, matchesPost, MAX_POST_PHOTOS, MAX_THREAD_PARTS, PostDraft, PostVideoAttachment, ThreadPart,
  updateLibrary } from '../model/LocalLibrary';
import { ThreadPartPicker } from '../components/ThreadPartPicker';
import { discardPostPhoto, pickPostPhotos, postPhotoUri } from '../model/PostPhotoStore';
import { PhotoViewer, PostGallery, PostPhoto } from '../components/PostPhoto';
import { discardPostVideo, pickPostVideo, postVideoPosterUri, postVideoUri } from '../model/PostVideoStore';
import { PostVideo, PostVideoPlayer } from '../components/PostVideo';
import { decodeIdentity, emptyIdentity, LocalIdentity, normalizeIdentity } from '../model/LocalIdentity';
import { ActivityEntry, ActivityPane } from '../components/ActivityPane';
import { AuthorPane } from '../components/AuthorPane';
import { ConversationPane, ConversationReply } from '../components/ConversationPane';
import { DiscoveryAuthor, DiscoveryPane } from '../components/DiscoveryPane';
import { IdentityEditor, LibraryHub } from '../components/LibraryHub';
import { ReadingTabs } from '../components/ReadingTabs';
import { SettingsPane } from '../components/SettingsPane';
import { ThreadsPublicPane } from '../components/ThreadsPublicPane';

const LARGE_TEXT_SCALE = 1.4;
const WIDE_VIEWPORT = 680;
const SIDE_NAV_WIDTH = 840;
const MAX_LIST_WIDTH = 1248;
const FEED_INLINE_PADDING = 18;
const REPLY_LIMIT = LOCAL_REPLY_BODY_LIMIT;
const POST_DETAIL = 'PostDetail';
const PUBLIC_THREADS = 'PublicThreads';
const POST_COMPOSER = 'PostComposer';
const POST_DRAFT_LIMIT = LOCAL_POST_BODY_LIMIT;
const POST_SETTINGS = 'Settings';
const AUTHOR_PROFILE = 'AuthorProfile';
const IDENTITY_EDITOR = 'IdentityEditor';
const POST_EDITOR = 'PostEditor';
const PHOTO_VIEWER = 'PhotoViewer';
const VIDEO_PLAYER = 'VideoPlayer';
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
const POST_DRAFT_CONTENT_KEY = 'content_v2';

enum DraftDecision {
  None,
  Leave,
  Clear,
  RemovePart
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

interface DiscussionOrigin {
  id: string;
  tab: ShellTab;
  authorPage: boolean;
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
  photoKeys?: string[];
  video?: PostVideoAttachment;
  continuation?: ThreadPart[];
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
  @State private profileMediaMode: number = 0;
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
  @State private sideNavigation: boolean = false;
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
  @State private discussionShown: boolean = false;
  @State private postDraft: string = '';
  @State private savedPostDraft: string = '';
  @State private draftPhotoKeys: string[] = [];
  @State private savedDraftPhotoKeys: string[] = [];
  @State private previewPhotoKeys: string[] = [];
  @State private viewerPhotoKeys: string[] = [];
  @State private viewerPhotoIndex: number = 0;
  @State private photoPicking: boolean = false;
  @State private draftVideo: PostVideoAttachment | undefined = undefined;
  @State private savedDraftVideo: PostVideoAttachment | undefined = undefined;
  @State private previewVideo: PostVideoAttachment | undefined = undefined;
  @State private playerVideo: PostVideoAttachment | undefined = undefined;
  @State private videoDestinationVisible: boolean = false;
  @StorageProp('timelineAppForeground') private appForeground: boolean = false;
  @State private postDraftReady: boolean = false;
  @State private postDraftBusy: boolean = false;
  @State private postDraftMessage: string = '';
  @State private draftDecision: DraftDecision = DraftDecision.None;
  @State private showingPostPreview: boolean = false;
  @State private previewBody: string = '';
  @State private draftParts: ThreadPart[] = [{ body: '' }];
  @State private activeDraftPart: number = 0;
  @State private savedContinuation: ThreadPart[] = [];
  @State private previewContinuation: ThreadPart[] = [];
  @State private composerInputVersion: number = 0;
  @State private composerHeight: number = 0;
  private readonly composerInput: TextAreaController = new TextAreaController();
  private readonly composerScroller: Scroller = new Scroller();
  private composerKeyboardMode: KeyboardAvoidMode | undefined = undefined;
  private composerVisible: boolean = false;
  private previewReturnOffset: number = -1;
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
  private shellShown: boolean = true;
  private authorShown: boolean = false;
  private discussionReturn: DiscussionOrigin | undefined = undefined;
  private discussionReturnScheduled: DiscussionOrigin | undefined = undefined;
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
    this.discussionReturn = undefined;
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

  private updateViewportWidth(width: number): void {
    if (!Number.isFinite(width) || width <= 0 || width === this.viewportWidth) { return; }
    const nextSideNavigation = width >= (this.sideNavigation ? SIDE_NAV_WIDTH - 24 : SIDE_NAV_WIDTH);
    if (nextSideNavigation !== this.sideNavigation) {
      this.rememberReadingPosition();
      this.sideNavigation = nextSideNavigation;
      this.onReadingLayoutChange();
    }
    this.viewportWidth = width;
  }

  private updateFeedWidth(width: number): void {
    if (!Number.isFinite(width) || width <= 0 || width === this.contentWidth) { return; }
    const previousWidth = this.contentWidth;
    // An area callback can arrive after the list has already reflowed. Keep the last stable post anchor.
    this.contentWidth = width;
    if (previousWidth > 0 && Math.min(previousWidth, MAX_LIST_WIDTH) !== Math.min(width, MAX_LIST_WIDTH)) {
      this.onReadingLayoutChange();
    }
  }

  private readingLaneCount(): number {
    return this.contentWidth - 2 * FEED_INLINE_PADDING >= WIDE_VIEWPORT && !this.toolbarInList() ? 2 : 1;
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

  private discussionControlId(surface: string, control: string, postId: string): string {
    // The cached tabs may contain the same post. Keep the existing Discovery IDs.
    return (surface === 'search' ? '' : surface + '-') + control + '-' + postId;
  }

  private restoreDiscussionFocus(retry: boolean = true): void {
    const origin = this.discussionReturn;
    if (origin === undefined || origin === this.discussionReturnScheduled) { return; }
    const paths = this.detailPaths.getAllPathName();
    if (origin.tab !== this.selectedTab || (origin.authorPage ? paths.length !== 1 || paths[0] !== AUTHOR_PROFILE : paths.length !== 0)) {
      this.discussionReturn = undefined;
      return;
    }
    if (!this.appForeground || !(origin.authorPage ? this.authorShown : this.shellShown)) { return; }
    this.discussionReturnScheduled = origin;
    this.getUIContext().postFrameCallback(new LayoutFrame(() => {
      if (this.discussionReturnScheduled === origin) { this.discussionReturnScheduled = undefined; }
      if (this.discussionReturn !== origin) { return; }
      if (origin.tab !== this.selectedTab || this.detailPaths.size() !== (origin.authorPage ? 1 : 0)) {
        this.discussionReturn = undefined;
        return;
      }
      if (!this.appForeground || !(origin.authorPage ? this.authorShown : this.shellShown)) { return; }
      try {
        this.getUIContext().getFocusController().requestFocus(origin.id);
        this.discussionReturn = undefined;
      } catch (_error) {
        if (retry) {
          this.restoreDiscussionFocus(false);
        } else {
          this.discussionReturn = undefined;
        }
      }
    }));
  }

  private openPost(post: MockPost, focusId: string = '', originId: string = ''): void {
    const paths = this.detailPaths.getAllPathName();
    if ((paths.length > 0 && (paths.length !== 1 || paths[0] !== AUTHOR_PROFILE)) ||
      !this.timelinePosts.some((item: MockPost) => item.id === post.id)) {
      return;
    }
    const origin: DiscussionOrigin = { id: originId, tab: this.selectedTab, authorPage: paths.length === 1 };
    this.discussionReturn = undefined;
    this.discussionShown = false;
    if (origin.authorPage) { this.authorShown = false; } else { this.shellShown = false; }
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
      this.discussionShown = false;
      this.activeDetailId = '';
      this.focusedReplyId = '';
      this.replyTargetId = '';
      this.replyExpanded = false;
      this.replyExitPending = false;
      this.replyDraft = '';
      this.confirmingDelete = false;
      this.discussionReturn = origin.id ? origin : undefined;
      this.onPageShow();
      this.restoreDiscussionFocus();
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
      replies: 0, likes: 0, avatarColor: '#4A7B78', local: true, photoKeys: post.photoKeys, video: post.video,
      continuation: post.continuation };
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
      !(this.samePhotoOrder(post.photoKeys ?? [], previousPosts[index]?.photoKeys ?? [])) ||
      post.video?.key !== previousPosts[index]?.video?.key ||
      post.video?.durationMs !== previousPosts[index]?.video?.durationMs ||
      !this.sameParts(post.continuation ?? [], previousPosts[index]?.continuation ?? []) ||
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
    this.discussionReturn = undefined;
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

  private openActivityPost(entry: ActivityEntry, originId: string = ''): void {
    const post = this.timelinePosts.find((item: MockPost) => item.id === entry.postId);
    if (post !== undefined) {
      this.openPost(post, entry.kind === 'reply' ? entry.id.substring('reply-'.length) : '', originId);
    }
  }

  private discoveryPosts(): MockPost[] {
    return this.timelinePosts.filter((post: MockPost) => !this.hiddenIds.includes(post.id) &&
      matchesPost(this.searchQuery, post.name, post.handle, this.threadText(post)));
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
      this.libraryMode === 2 ? this.likedIds.includes(post.id) : post.local === true &&
      (this.profileMediaMode === 1 ? (post.photoKeys?.length ?? 0) > 0 ||
        (post.continuation ?? []).some((part: ThreadPart) => (part.photoKeys?.length ?? 0) > 0) :
        this.profileMediaMode === 2 ? post.video !== undefined ||
          (post.continuation ?? []).some((part: ThreadPart) => part.video !== undefined) : true));
  }

  private openPublicThreads(): void {
    if (this.detailPaths.size() > 0 || this.selectedTab !== ShellTab.Search) { return; }
    this.rememberReadingPosition();
    this.timelineVisible = false;
    this.detailPaths.pushPath({ name: PUBLIC_THREADS, onPop: () => this.onPageShow() }, this.allowsMotionFeedback());
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
    this.identityMessage = '';
    this.identityBusy = true;
    try {
      const store = await this.identityPreferences();
      await store.put(IDENTITY_KEY, JSON.stringify(value));
      await store.flush();
      this.identity = value;
      this.applyLibrary(this.library);
      this.closePost();
      this.inform('本机资料已保存。');
    } catch (_error) {
      this.identityMessage = '未能保存，本次输入仍在。';
    } finally {
      this.identityBusy = false;
    }
  }

  private currentPostBody(post: MockPost): string {
    return post.local ? this.timelinePosts.find((item: MockPost) => item.id === post.id)?.body ?? post.body : post.body;
  }

  private currentContinuation(post: MockPost): ThreadPart[] {
    return post.local ? this.timelinePosts.find((item: MockPost) => item.id === post.id)?.continuation ?? [] :
      post.continuation ?? [];
  }

  private threadText(post: MockPost): string {
    return [this.currentPostBody(post), ...this.currentContinuation(post).map((part: ThreadPart) => part.body)]
      .filter((body: string) => body.trim().length > 0).join('\n\n');
  }

  private sameParts(left: ThreadPart[], right: ThreadPart[]): boolean {
    return left.length === right.length && left.every((part: ThreadPart, index: number) =>
      part.body === right[index].body && this.samePhotoOrder(part.photoKeys ?? [], right[index].photoKeys ?? []) &&
      part.video?.key === right[index].video?.key && part.video?.durationMs === right[index].video?.durationMs);
  }

  private samePhotoOrder(left: string[], right: string[]): boolean {
    return left.length === right.length && left.every((key: string, index: number) => key === right[index]);
  }

  private currentPhotoKeys(post: MockPost): string[] {
    return this.timelinePosts.find((item: MockPost) => item.id === post.id)?.photoKeys ?? [];
  }

  private photoUri(key: string): string {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    return context !== undefined && isPostPhotoKey(key) ? postPhotoUri(context, key) : '';
  }

  private photoUris(keys: string[]): string[] {
    return keys.map((key: string) => this.photoUri(key));
  }

  private openPhoto(keys: string[], index: number): void {
    const paths = this.detailPaths.getAllPathName();
    if (this.libraryBusy || this.photoPicking || this.viewerPhotoKeys.length > 0 ||
      !Number.isInteger(index) || index < 0 || index >= keys.length || !isPostPhotoKey(keys[index]) ||
      this.replyExpanded || this.replyExitPending || this.confirmingDelete ||
      (paths.length > 0 && paths[paths.length - 1] !== POST_DETAIL &&
        paths[paths.length - 1] !== POST_COMPOSER && paths[paths.length - 1] !== AUTHOR_PROFILE)) { return; }
    this.rememberReadingPosition();
    this.timelineVisible = false;
    this.viewerPhotoKeys = keys.slice();
    this.viewerPhotoIndex = index;
    this.detailPaths.pushPath({ name: PHOTO_VIEWER, onPop: () => {
      this.viewerPhotoKeys = [];
      this.viewerPhotoIndex = 0;
      this.onPageShow();
    } }, this.allowsMotionFeedback());
  }

  private currentVideo(post: MockPost): PostVideoAttachment | undefined {
    return this.timelinePosts.find((item: MockPost) => item.id === post.id)?.video;
  }

  private videoUri(key: string, poster: boolean = false): string {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (context === undefined || !isPostVideoKey(key)) { return ''; }
    return poster ? postVideoPosterUri(context, key) : postVideoUri(context, key);
  }

  private openVideo(video?: PostVideoAttachment): void {
    const paths = this.detailPaths.getAllPathName();
    if (video === undefined || !isPostVideoKey(video.key) || this.playerVideo !== undefined ||
      this.libraryBusy || this.photoPicking || this.replyExpanded || this.replyExitPending || this.confirmingDelete ||
      (paths.length > 0 && paths[paths.length - 1] !== POST_DETAIL &&
        paths[paths.length - 1] !== POST_COMPOSER && paths[paths.length - 1] !== AUTHOR_PROFILE)) { return; }
    this.rememberReadingPosition();
    this.timelineVisible = false;
    this.videoDestinationVisible = false;
    this.playerVideo = video;
    this.detailPaths.pushPath({ name: VIDEO_PLAYER, onPop: () => {
      this.videoDestinationVisible = false;
      this.playerVideo = undefined;
      this.onPageShow();
    } }, this.allowsMotionFeedback());
  }

  private closeVideo(): void {
    this.videoDestinationVisible = false;
    this.closePost();
  }

  private async copyPost(post: MockPost): Promise<void> {
    try {
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.threadText(post)));
      this.inform('已复制正文');
    } catch (_error) { this.inform('无法复制，请重试。'); }
  }

  private async sharePost(post: MockPost): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const data = new systemShare.SharedData({ utd: 'general.plain-text', content: this.threadText(post),
        title: post.local ? '本机帖子' : '示例帖子' });
      await new systemShare.ShareController(data).show(context, { anchor: 'post-menu-' + post.id });
    } catch (_error) { this.inform('系统分享不可用，可以复制正文。'); }
  }

  @Builder
  PostMenu(post: MockPost) {
    Menu() {
      if (this.threadText(post).trim()) {
        MenuItem({ content: '复制正文' }).onClick(() => { this.copyPost(post); })
        MenuItem({ content: '分享正文…' }).onClick(() => { this.sharePost(post); })
      }
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

  private canSavePostEdit(): boolean {
    const stored = this.library.posts.find((post: LibraryPost) => post.id === this.editingPostId);
    return stored !== undefined && this.editBody !== stored.body &&
      canPublishThread(this.makePart(this.editBody, stored.photoKeys ?? [], stored.video), stored.continuation ?? []);
  }

  private async savePostEdit(): Promise<void> {
    if (this.editConfirmLeave || !this.canSavePostEdit()) { return; }
    const posts = this.library.posts.map((post: LibraryPost): LibraryPost =>
      post.id === this.editingPostId ? { id: post.id, body: this.editBody, photoKeys: post.photoKeys, video: post.video,
        continuation: post.continuation } : post);
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
    const removed = [this.makePart(this.currentPostBody(post), this.currentPhotoKeys(post), this.currentVideo(post)),
      ...this.currentContinuation(post)];
    const saved = await this.saveLibrary(updateLibrary(this.library, {
      posts: this.library.posts.filter((item: LibraryPost) => item.id !== post.id),
      likedIds: this.likedIds.filter((id: string) => id !== post.id),
      savedIds: this.savedIds.filter((id: string) => id !== post.id),
      replies: this.library.replies.filter((row: LibraryReply) => row.postId !== post.id)
    }));
    if (saved) {
      this.releaseParts(removed);
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

  private makePart(body: string, keys: string[], video?: PostVideoAttachment): ThreadPart {
    return { body: body, photoKeys: keys.length > 0 ? keys.slice() : undefined, video: video };
  }

  private composerParts(): ThreadPart[] {
    const parts = this.draftParts.slice();
    parts[this.activeDraftPart] = this.makePart(this.postDraft, this.draftPhotoKeys, this.draftVideo);
    return parts;
  }

  private updateComposerInput(version: number, value: string): void {
    if (version !== this.composerInputVersion || !this.canChangeDraftPhotos()) { return; }
    this.postDraft = value;
    this.postDraftMessage = '';
  }

  private setComposerKeyboard(visible: boolean): void {
    this.composerVisible = visible;
    const ui = this.getUIContext();
    if (visible && this.composerKeyboardMode === undefined) {
      this.composerKeyboardMode = ui.getKeyboardAvoidMode();
      ui.setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    } else if (!visible && this.composerKeyboardMode !== undefined) {
      if (ui.getKeyboardAvoidMode() === KeyboardAvoidMode.RESIZE) {
        ui.setKeyboardAvoidMode(this.composerKeyboardMode);
      }
      this.composerKeyboardMode = undefined;
    }
  }

  private stopComposerInput(): void {
    this.composerInput.stopEditing();
  }

  private stackedComposerActions(): boolean {
    return this.fontScale >= LARGE_TEXT_SCALE || (this.viewportWidth > 0 && this.viewportWidth < 340);
  }

  private composerActionHeight(): number {
    return this.composerHeight > 0 ? Math.max(48, this.composerHeight * 0.46) : 360;
  }

  private restoreComposerOffset(): void {
    if (this.previewReturnOffset < 0) { return; }
    const offset = this.previewReturnOffset;
    this.previewReturnOffset = -1;
    this.getUIContext().postFrameCallback(new LayoutFrame(() => {
      if (this.composerVisible && !this.showingPostPreview) {
        this.composerScroller.scrollTo({ xOffset: 0, yOffset: offset, animation: false });
      }
    }));
  }

  private setComposerParts(parts: ThreadPart[], index: number): void {
    this.composerInputVersion += 1;
    this.draftParts = parts;
    this.activeDraftPart = index;
    this.postDraft = parts[index].body;
    this.draftPhotoKeys = (parts[index].photoKeys ?? []).slice();
    this.draftVideo = parts[index].video;
  }

  private restoreSavedParts(): void {
    this.setComposerParts([this.makePart(this.savedPostDraft, this.savedDraftPhotoKeys, this.savedDraftVideo),
      ...this.savedContinuation], 0);
  }

  private selectDraftPart(index: number): void {
    if (!this.canChangeDraftPhotos() || index === this.activeDraftPart || !Number.isInteger(index) ||
      index < 0 || index >= this.draftParts.length) { return; }
    this.stopComposerInput();
    this.setComposerParts(this.composerParts(), index);
    this.composerScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false });
    this.postDraftMessage = '';
  }

  private addDraftPart(): void {
    if (!this.canChangeDraftPhotos() || this.draftParts.length >= MAX_THREAD_PARTS) { return; }
    this.stopComposerInput();
    const parts = this.composerParts();
    parts.push({ body: '' });
    this.setComposerParts(parts, parts.length - 1);
    this.composerScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false });
    this.postDraftMessage = '';
  }

  private moveDraftPart(direction: number): void {
    const current = this.activeDraftPart;
    const next = current + direction;
    if (!this.canChangeDraftPhotos() || (direction !== -1 && direction !== 1) || next < 0 ||
      next >= this.draftParts.length) { return; }
    this.stopComposerInput();
    const parts = this.composerParts();
    const moved = parts[current];
    parts[current] = parts[next];
    parts[next] = moved;
    this.setComposerParts(parts, next);
    this.postDraftMessage = '';
  }

  private removeDraftPart(): void {
    if (this.draftDecision !== DraftDecision.RemovePart || this.postDraftBusy || this.photoPicking ||
      this.draftParts.length < 2) { return; }
    const parts = this.composerParts();
    const removed = parts.splice(this.activeDraftPart, 1);
    this.setComposerParts(parts, Math.min(this.activeDraftPart, parts.length - 1));
    this.composerScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false });
    this.draftDecision = DraftDecision.None;
    this.postDraftMessage = '';
    this.releaseParts(removed);
  }

  private releaseParts(parts: ThreadPart[]): void {
    const photos: string[] = [];
    const videos: string[] = [];
    parts.forEach((part: ThreadPart) => {
      (part.photoKeys ?? []).forEach((key: string) => { if (!photos.includes(key)) { photos.push(key); } });
      const movie = part.video?.key;
      if (movie !== undefined && !videos.includes(movie)) { videos.push(movie); }
    });
    this.releasePostPhotos(photos);
    videos.forEach((key: string) => { this.releasePostVideo(key); });
  }

  private openComposer(): void {
    if (this.detailPaths.size() > 0) {
      return;
    }
    this.rememberReadingPosition();
    this.timelineVisible = false;
    this.restoreSavedParts();
    this.postDraftMessage = '';
    this.draftDecision = DraftDecision.None;
    this.previewReturnOffset = -1;
    this.detailPaths.pushPath({ name: POST_COMPOSER, onPop: () => {
      this.previewReturnOffset = -1;
      const abandoned = this.composerParts();
      this.restoreSavedParts();
      this.postDraftLoadId += 1;
      this.postDraftBusy = false;
      this.closePostPreview();
      this.releaseParts(abandoned);
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
      const draft = await this.readStoredDraft(store);
      if (loadId !== this.postDraftLoadId) { return; }
      this.savedPostDraft = draft.body;
      this.savedDraftPhotoKeys = draft.photoKeys ?? [];
      this.savedDraftVideo = draft.video;
      this.savedContinuation = draft.continuation ?? [];
      this.restoreSavedParts();
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

  private async readStoredDraft(store: preferences.Preferences): Promise<PostDraft> {
    const raw = await store.get(POST_DRAFT_CONTENT_KEY, '');
    if (typeof raw !== 'string') { throw new Error('Invalid local draft'); }
    if (raw) { return decodePostDraft(raw); }
    const body = await store.get(POST_DRAFT_KEY, '');
    if (typeof body !== 'string' || body.length > POST_DRAFT_LIMIT) { throw new Error('Invalid local draft'); }
    return { body: body };
  }

  private savedParts(): ThreadPart[] {
    return [this.makePart(this.savedPostDraft, this.savedDraftPhotoKeys, this.savedDraftVideo), ...this.savedContinuation];
  }

  private async storedAttachmentParts(): Promise<ThreadPart[]> {
    const draft = await this.readStoredDraft(await this.postDraftPreferences());
    return [draft, ...(draft.continuation ?? [])];
  }

  private attachmentInUse(key: string, video: boolean, persisted: ThreadPart[]): boolean {
    const used = (part: ThreadPart): boolean => video ? part.video?.key === key : part.photoKeys?.includes(key) === true;
    return this.libraryBusy || this.postDraftBusy || persisted.some(used) || this.savedParts().some(used) ||
      this.composerParts().some(used) || this.previewContinuation.some(used) ||
      (video ? this.previewVideo?.key === key || this.playerVideo?.key === key :
        this.previewPhotoKeys.includes(key) || this.viewerPhotoKeys.includes(key)) ||
      this.library.posts.some((post: LibraryPost) => used(post) || (post.continuation ?? []).some(used));
  }

  private async releasePostPhoto(key: string): Promise<void> {
    if (!isPostPhotoKey(key) || !this.libraryReady) { return; }
    try {
      const persisted = this.postDraftReady ? this.savedParts() : await this.storedAttachmentParts();
      if (this.attachmentInUse(key, false, persisted)) { return; }
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
      if (context !== undefined) { discardPostPhoto(context, key); }
    } catch (_error) {
      // An unknown reference is safer to retain than to delete.
    }
  }

  private releasePostPhotos(keys: string[]): void {
    keys.forEach((key: string) => { this.releasePostPhoto(key); });
  }

  private async releasePostVideo(key: string): Promise<void> {
    if (!isPostVideoKey(key) || !this.libraryReady) { return; }
    try {
      const persisted = this.postDraftReady ? this.savedParts() : await this.storedAttachmentParts();
      if (this.attachmentInUse(key, true, persisted)) { return; }
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
      if (context !== undefined) { discardPostVideo(context, key); }
    } catch (_error) {
      // Preserve the video if stored references could not be read.
    }
  }

  private async selectDraftVideo(fromFiles: boolean = false): Promise<void> {
    if (!this.libraryReady || !this.canChangeDraftPhotos() || this.draftPhotoKeys.length > 0 ||
      this.draftVideo !== undefined) { return; }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (context === undefined) { return; }
    const loadId = this.postDraftLoadId;
    this.photoPicking = true;
    this.postDraftMessage = '';
    try {
      const video = await pickPostVideo(context, fromFiles);
      if (video === undefined) { return; }
      if (loadId !== this.postDraftLoadId) {
        discardPostVideo(context, video.key);
        return;
      }
      this.draftVideo = video;
    } catch (error) {
      if (loadId === this.postDraftLoadId) {
        this.postDraftMessage = error instanceof Error ? error.message : '无法添加视频，请重试。';
      }
    } finally {
      this.photoPicking = false;
    }
  }

  private removeDraftVideo(): void {
    if (!this.canChangeDraftPhotos() || this.draftVideo === undefined) { return; }
    const key = this.draftVideo.key;
    this.draftVideo = undefined;
    this.postDraftMessage = '';
    this.releasePostVideo(key);
  }

  private canChangeDraftPhotos(): boolean {
    return this.postDraftReady && !this.postDraftBusy && !this.photoPicking &&
      !this.showingPostPreview && this.draftDecision === DraftDecision.None;
  }

  private async selectDraftPhotos(): Promise<void> {
    const remaining = MAX_POST_PHOTOS - this.draftPhotoKeys.length;
    if (!this.libraryReady || !this.canChangeDraftPhotos() || this.draftVideo !== undefined || remaining <= 0) { return; }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (context === undefined) { return; }
    const loadId = this.postDraftLoadId;
    this.photoPicking = true;
    this.postDraftMessage = '';
    try {
      const keys = await pickPostPhotos(context, remaining);
      if (keys.length === 0) { return; }
      if (loadId !== this.postDraftLoadId) {
        this.releasePostPhotos(keys);
        return;
      }
      this.draftPhotoKeys = [...this.draftPhotoKeys, ...keys];
    } catch (error) {
      if (loadId === this.postDraftLoadId) {
        this.postDraftMessage = error instanceof Error ? error.message : '无法添加图片，请重试。';
      }
    } finally {
      this.photoPicking = false;
    }
  }

  private removeDraftPhoto(key: string): void {
    if (!this.canChangeDraftPhotos() || !this.draftPhotoKeys.includes(key)) { return; }
    this.draftPhotoKeys = this.draftPhotoKeys.filter((item: string) => item !== key);
    this.postDraftMessage = '';
    this.releasePostPhoto(key);
  }

  private moveDraftPhoto(key: string, offset: number): void {
    if (!this.canChangeDraftPhotos() || (offset !== -1 && offset !== 1)) { return; }
    const index = this.draftPhotoKeys.indexOf(key);
    const next = index + offset;
    if (index < 0 || next < 0 || next >= this.draftPhotoKeys.length) { return; }
    const keys = this.draftPhotoKeys.slice();
    keys[index] = keys[next];
    keys[next] = key;
    this.draftPhotoKeys = keys;
    this.postDraftMessage = '';
  }

  private draftChanged(): boolean {
    return !this.sameParts(this.composerParts(), this.savedParts());
  }

  private canSavePostDraft(): boolean {
    return this.postDraftReady && !this.postDraftBusy && !this.photoPicking && this.draftDecision === DraftDecision.None &&
      this.composerParts().some((part: ThreadPart) => canPublishThread(part, [])) &&
      this.composerParts().every((part: ThreadPart) => part.body.length <= POST_DRAFT_LIMIT) && this.draftChanged();
  }

  private canPreviewPostDraft(): boolean {
    if (!this.canChangeDraftPhotos()) { return false; }
    const parts = this.composerParts();
    return canPublishThread(parts[0], parts.slice(1));
  }

  private openPostPreview(): void {
    if (!this.canPreviewPostDraft()) {
      return;
    }
    const offset = this.composerScroller.currentOffset()?.yOffset ?? 0;
    this.previewReturnOffset = Number.isFinite(offset) ? Math.max(0, offset) : 0;
    this.stopComposerInput();
    const parts = this.composerParts();
    this.previewBody = parts[0].body;
    this.previewPhotoKeys = parts[0].photoKeys ?? [];
    this.previewVideo = parts[0].video;
    this.previewContinuation = parts.slice(1);
    this.showingPostPreview = true;
  }

  private closePostPreview(): void {
    this.showingPostPreview = false;
    this.previewBody = '';
    this.previewPhotoKeys = [];
    this.previewVideo = undefined;
    this.previewContinuation = [];
  }

  private async addPreviewToTimeline(): Promise<void> {
    if (!this.showingPostPreview || !canPublishThread(this.makePart(this.previewBody, this.previewPhotoKeys,
      this.previewVideo), this.previewContinuation) || this.libraryBusy || !this.libraryReady) {
      return;
    }
    if (this.library.posts.length >= LIBRARY_POST_LIMIT) {
      this.inform('本机帖子已满，请在「我的」中删除不再需要的帖子。');
      return;
    }
    const body = this.previewBody;
    this.postSequence = Math.max(this.postSequence + 1, Date.now());
    const post: LibraryPost = { id: `local-post-${this.postSequence}`, body: body,
      photoKeys: this.previewPhotoKeys.length > 0 ? this.previewPhotoKeys.slice() : undefined, video: this.previewVideo,
      continuation: this.previewContinuation.length > 0 ? this.previewContinuation.slice() : undefined };
    const saved = await this.saveLibrary(updateLibrary(this.library, { posts: [post, ...this.library.posts] }));
    if (saved) {
      this.selectedTab = ShellTab.Home;
      this.followingOnly = false;
      this.closePostPreview();
      this.readingAnchor = { postId: '', clipped: 0 };
      this.restorePending = true;
      this.leaveComposer();
    }
  }

  private leaveComposer(): void {
    this.detailPaths.pop({ closed: true }, this.allowsMotionFeedback());
  }

  private requestComposerExit(): void {
    if (this.photoPicking || (this.postDraftReady && this.postDraftBusy) || (this.showingPostPreview && this.libraryBusy)) {
      return;
    }
    if (this.showingPostPreview) {
      this.closePostPreview();
    } else if (this.draftDecision !== DraftDecision.None) {
      this.draftDecision = DraftDecision.None;
    } else {
      this.stopComposerInput();
      if (this.draftChanged()) {
        this.draftDecision = DraftDecision.Leave;
      } else {
        this.leaveComposer();
      }
    }
  }

  private discardPostEdits(): void {
    if (this.draftDecision === DraftDecision.Leave && !this.postDraftBusy && !this.photoPicking) {
      this.leaveComposer();
    }
  }

  private async savePostDraft(clear: boolean): Promise<void> {
    if (clear ? (!this.postDraftReady || this.postDraftBusy || this.photoPicking || this.draftDecision !== DraftDecision.Clear)
      : !this.canSavePostDraft()) {
      return;
    }
    this.stopComposerInput();
    const old = [...this.savedParts(), ...this.composerParts()];
    const parts: ThreadPart[] = clear ? [{ body: '' }] : this.composerParts();
    const root = parts[0];
    const remaining = parts.slice(1);
    const index = clear ? 0 : this.activeDraftPart;
    let written = false;
    this.postDraftBusy = true;
    this.postDraftMessage = '';
    this.draftDecision = DraftDecision.None;
    try {
      const store = await this.postDraftPreferences();
      const draft: PostDraft = { body: root.body, photoKeys: root.photoKeys, video: root.video,
        continuation: remaining.length > 0 ? remaining : undefined };
      await store.put(POST_DRAFT_CONTENT_KEY, JSON.stringify(draft));
      await store.flush();
      this.savedPostDraft = root.body;
      this.savedDraftPhotoKeys = root.photoKeys ?? [];
      this.savedDraftVideo = root.video;
      this.savedContinuation = remaining;
      this.setComposerParts(parts, index);
      written = true;
      this.postDraftMessage = clear ? '本机草稿已清空。' : '草稿已保存到本机。';
    } catch (_error) {
      this.postDraftMessage = '未能写入本机，当前内容仍保留。';
    } finally {
      this.postDraftBusy = false;
    }
    if (written) { this.releaseParts(old); }
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
  PostActions(post: MockPost, inDetail: boolean, surface: string) {
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
        }.id(this.discussionControlId(surface, 'replies', post.id))
          .constraintSize({ minWidth: 48, minHeight: 44 }).buttonStyle(ButtonStyleMode.TEXTUAL)
          .padding({ left: 8, right: 10 }).accessibilityText('查看' + post.name + '的帖子详情，' + this.replyCount(post) + ' 条回复')
          .onClick(() => this.openPost(post, '', this.discussionControlId(surface, 'replies', post.id)))
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
  SummaryEntry(post: MockPost, surface: string, reply?: DemoReply) {
    if (reply !== undefined) {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 12 }) {
          Column({ space: 3 }) {
            Divider().vertical(true).height(8).strokeWidth(1).color($r('app.color.timeline_border'))
            Text(reply.author.substring(0, 1)).width(22).height(22).fontSize('11vp')
              .backgroundColor($r('app.color.timeline_surface_muted')).fontColor($r('app.color.timeline_text_secondary'))
              .borderRadius(11).textAlign(TextAlign.Center).accessibilityLevel('no')
          }.width(36)
          Text(reply.author + '：' + reply.body)
            .fontSize(13).fontColor($r('app.color.timeline_text_secondary')).layoutWeight(1)
            .maxLines(this.toolbarInList() ? 3 : 2).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.width('100%')
      }.width('100%').constraintSize({ minHeight: 48 }).padding({ top: 4, bottom: 4, left: 0, right: 0 })
        .buttonStyle(ButtonStyleMode.TEXTUAL).accessibilityGroup(true)
        .id(this.discussionControlId(surface, 'summary', post.id))
        .accessibilityText('查看 ' + reply.author + ' 的回复：' + reply.body)
        .onClick(() => this.openPost(post, reply.id, this.discussionControlId(surface, 'summary', post.id)))
    }
  }

  @Builder
  PostCard(post: MockPost, inDetail: boolean, authorLink: boolean = true, completeThread: boolean = false,
    surface: string = 'home') {
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
                  .focusable(true).accessibilityRole(AccessibilityRoleType.BUTTON)
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
          if (inDetail && !completeThread) {
            if (this.currentPostBody(post).trim().length > 0) {
              Text(this.currentPostBody(post)).fontSize(16).fontColor($r('app.color.timeline_text_body')).width('100%')
                .textAlign(TextAlign.Start).copyOption(CopyOptions.InApp)
            }
          } else if (!inDetail) {
            Text(post.body.trim() ? post.body : (post.video !== undefined ? '视频帖子' : '图片帖子'))
              .id(this.discussionControlId(surface, 'body', post.id))
              .fontSize(16).fontColor($r('app.color.timeline_text_body')).width('100%')
              .textAlign(TextAlign.Start).accessibilityText('打开原帖：' + (post.body.trim() || (post.video !== undefined ? '视频帖子' : '图片帖子')))
              .focusable(true).accessibilityRole(AccessibilityRoleType.BUTTON)
              .onClick(() => this.openPost(post, '', this.discussionControlId(surface, 'body', post.id)))
          }
          if (completeThread) {
            Column() {
              this.ThreadPartContent(this.makePart(this.currentPostBody(post), this.currentPhotoKeys(post),
                this.currentVideo(post)), 1, this.currentContinuation(post).length + 1, 'thread-reading-part-')
              ForEach(this.currentContinuation(post), (part: ThreadPart, index: number) => {
                this.ThreadPartContent(part, index + 2, this.currentContinuation(post).length + 1, 'thread-reading-part-')
              }, (_part: ThreadPart, index: number) => index.toString())
            }.id('thread-reading-heading').width('100%').margin({ top: 6 })
          } else {
            if (this.currentPhotoKeys(post).length > 0) {
              PostGallery({ uris: this.photoUris(this.currentPhotoKeys(post)), motionEnabled: this.allowsMotionFeedback(),
                onOpen: (index: number) => this.openPhoto(this.currentPhotoKeys(post), index) })
            }
            if (this.currentVideo(post) !== undefined) {
              PostVideo({ posterUri: this.videoUri(this.currentVideo(post)?.key ?? '', true),
                durationMs: this.currentVideo(post)?.durationMs ?? 0, onOpen: () => this.openVideo(this.currentVideo(post)) })
            }
          }
          if (!inDetail && this.currentContinuation(post).length > 0) {
            Button('阅读全文 · ' + (this.currentContinuation(post).length + 1) + ' 段')
              .id(this.discussionControlId(surface, 'open-thread', post.id))
              .buttonStyle(ButtonStyleMode.TEXTUAL).constraintSize({ minHeight: 44 })
              .fontColor($r('app.color.timeline_text_primary'))
              .onClick(() => this.openPost(post, '', this.discussionControlId(surface, 'open-thread', post.id)))
          }
          this.PostActions(post, inDetail, surface)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%').alignItems(VerticalAlign.Top)
      if (!inDetail) {
        ForEach(this.previewRows(post.id), (reply: DemoReply) => {
          this.SummaryEntry(post, surface, reply)
        }, (reply: DemoReply) => reply.id)
      }
      Divider().strokeWidth(0.5).color($r('app.color.timeline_border')).margin({ top: 6 })
    }.width('100%').constraintSize({ maxWidth: 600 }).padding({ top: 14 })
  }

  @Builder
  ThreadPartContent(part: ThreadPart, number: number, total: number, idPrefix: string) {
    Column({ space: 8 }) {
      if (number > 1) {
        Divider().strokeWidth(0.5).color($r('app.color.timeline_border')).margin({ bottom: 4 })
      }
      if (total > 1) {
        Text('第 ' + number + ' / ' + total + ' 段').fontSize(13).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.timeline_text_secondary')).accessibilityLevel('yes')
      }
      if (part.body.trim().length > 0) {
        Text(part.body).width('100%').fontSize(16).textAlign(TextAlign.Start).wordBreak(WordBreak.BREAK_WORD)
          .fontColor($r('app.color.timeline_text_body')).copyOption(CopyOptions.InApp)
      }
      if ((part.photoKeys?.length ?? 0) > 0) {
        PostGallery({ uris: this.photoUris(part.photoKeys ?? []), motionEnabled: this.allowsMotionFeedback(),
          onOpen: (index: number) => this.openPhoto(part.photoKeys ?? [], index) })
      } else if (part.video !== undefined) {
        PostVideo({ posterUri: this.videoUri(part.video.key, true), durationMs: part.video.durationMs,
          onOpen: () => this.openVideo(part.video) })
      }
    }.id(idPrefix + number).width('100%').alignItems(HorizontalAlign.Start)
      .padding({ top: number > 1 ? 14 : 0, bottom: total > 1 ? 16 : 0 })
  }

  @Builder
  DiscussionRoot(post: MockPost) {
    Column({ space: 6 }) {
      this.PostCard(post, true, false, this.currentContinuation(post).length > 0)
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
      busy: this.libraryBusy, shown: this.discussionShown && this.appForeground,
      onBack: () => this.requestDetailBack(), onEdit: (id: string) => this.beginReply(post.id, id),
      onExpand: () => this.expandCurrentReply(post.id), onDraft: (value: string) => { this.replyDraft = value; },
      onSend: () => this.submitReply(post.id), onDiscard: () => this.discardReplyAndClose(), onKeep: () => this.keepReplyDraft() })
  }

  @Builder
  ComposerHeading(preview: boolean) {
    Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center, space: { main: LengthMetrics.vp(8) } }) {
      Button(preview ? '返回编辑' : '返回').id(preview ? 'composer-preview-back' : 'composer-back')
        .buttonStyle(ButtonStyleMode.TEXTUAL).constraintSize({ minWidth: 48, minHeight: 48 })
        .padding({ left: 4, right: 8 }).fontColor($r('app.color.timeline_text_secondary'))
        .enabled(preview ? !this.libraryBusy : !this.photoPicking && (!this.postDraftReady || !this.postDraftBusy))
        .onClick(() => this.requestComposerExit())
      Text(preview ? (this.previewContinuation.length > 0 ? '串帖预览' : '帖子预览') : '写帖草稿')
        .fontSize(21).fontWeight(FontWeight.Bold).fontColor($r('app.color.timeline_text_primary'))
        .constraintSize({ maxWidth: '100%' }).wordBreak(WordBreak.BREAK_WORD).accessibilityLevel('yes')
    }.width('100%').padding({ left: 18, right: 18, top: 4, bottom: 4 })
    Divider().strokeWidth(0.5).color($r('app.color.timeline_border'))
  }

  @Builder
  PostPreviewContent() {
    Column() {
      this.ComposerHeading(true)
      Scroll() {
        Column({ space: 14 }) {
          Text('只保存在本机，不会发送到 Threads，也不会更改已保存的草稿。')
            .fontSize(13).fontColor($r('app.color.timeline_text_secondary'))
          Row({ space: 10 }) {
            Text(this.identity.name.substring(0, 1)).width(36).height(36).fontSize('15vp')
              .fontWeight(FontWeight.Medium).textAlign(TextAlign.Center).borderRadius(18)
              .backgroundColor($r('app.color.timeline_surface_muted')).fontColor($r('app.color.timeline_text_primary'))
              .accessibilityLevel('no')
            Text(this.identity.name).fontSize(16).fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.timeline_text_primary')).layoutWeight(1)
          }.width('100%')
          this.ThreadPartContent(this.makePart(this.previewBody, this.previewPhotoKeys, this.previewVideo),
            1, this.previewContinuation.length + 1, 'thread-preview-part-')
          ForEach(this.previewContinuation, (part: ThreadPart, index: number) => {
            this.ThreadPartContent(part, index + 2, this.previewContinuation.length + 1, 'thread-preview-part-')
          }, (_part: ThreadPart, index: number) => index.toString())
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 18, right: 18, top: 12, bottom: 12 })
      }.width('100%').layoutWeight(1).align(Alignment.Top).scrollBar(BarState.Auto)
      Divider().strokeWidth(0.5).color($r('app.color.timeline_border'))
      Scroll() {
        Column({ space: 4 }) {
          this.LibraryStatus()
          Button(this.libraryBusy ? '正在保存…' : '加入本机时间线')
            .id('composer-preview-confirm').width('100%').constraintSize({ minHeight: 48 })
            .padding({ left: 14, right: 14, top: 8, bottom: 8 })
            .backgroundColor($r('app.color.timeline_action')).fontColor($r('app.color.timeline_on_action'))
            .enabled(this.libraryReady && !this.libraryBusy).onClick(() => { this.addPreviewToTimeline(); })
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 18, right: 18, top: 8, bottom: 8 })
      }.width('100%').constraintSize({ maxHeight: this.composerActionHeight() }).scrollBar(BarState.Auto)
    }.width('100%').height('100%').constraintSize({ maxWidth: 640 })
  }

  @Builder
  DraftPhotoRow(key: string) {
    Row({ space: 10 }) {
      Column() {
        PostPhoto({ uri: this.photoUri(key), compact: true, compactHeight: 76, elementId: 'draft-photo-thumb-' + key })
      }.width(72).height(76).clip(true).borderRadius(10)
      Column({ space: 3 }) {
        Text('第 ' + (this.draftPhotoKeys.indexOf(key) + 1) + ' 张')
          .fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.timeline_text_primary'))
        Flex({ wrap: FlexWrap.Wrap }) {
          Button('前移').buttonStyle(ButtonStyleMode.TEXTUAL).constraintSize({ minHeight: 44, minWidth: 44 })
            .id('draft-photo-earlier-' + key)
            .enabled(this.canChangeDraftPhotos() && this.draftPhotoKeys.indexOf(key) > 0)
            .onClick(() => this.moveDraftPhoto(key, -1))
          Button('后移').buttonStyle(ButtonStyleMode.TEXTUAL).constraintSize({ minHeight: 44, minWidth: 44 })
            .id('draft-photo-later-' + key)
            .enabled(this.canChangeDraftPhotos() && this.draftPhotoKeys.indexOf(key) < this.draftPhotoKeys.length - 1)
            .onClick(() => this.moveDraftPhoto(key, 1))
          Button('移除').buttonStyle(ButtonStyleMode.TEXTUAL).constraintSize({ minHeight: 44, minWidth: 44 })
            .id('draft-photo-remove-' + key).fontColor($r('app.color.timeline_text_secondary'))
            .enabled(this.canChangeDraftPhotos()).onClick(() => this.removeDraftPhoto(key))
        }.width('100%')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }.width('100%').padding({ left: 8, right: 8, top: 8, bottom: 8 })
      .backgroundColor($r('app.color.timeline_surface_muted')).borderRadius(12)
  }

  @Builder
  ComposerAttachments() {
    Column({ space: 6 }) {
      Divider().strokeWidth(0.5).color($r('app.color.timeline_border'))
      Text('本段附件').fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.timeline_text_primary'))
      if (this.draftVideo !== undefined) {
        PostVideo({ posterUri: this.videoUri(this.draftVideo.key, true), durationMs: this.draftVideo.durationMs, compact: true })
        Button('移除视频').id('draft-video-remove').buttonStyle(ButtonStyleMode.TEXTUAL)
          .constraintSize({ minHeight: 48 }).fontColor($r('app.color.timeline_text_body'))
          .enabled(this.canChangeDraftPhotos()).onClick(() => this.removeDraftVideo())
      } else {
        Text(this.draftPhotoKeys.length > 0 ? '图片 ' + this.draftPhotoKeys.length + ' / ' + MAX_POST_PHOTOS :
          '最多四张图片，或一段本机 MP4（60 秒、64 MiB 以内）。')
          .id('draft-photo-count').fontSize(13).fontColor($r('app.color.timeline_text_secondary'))
        Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(6) } }) {
          Button(this.photoPicking ? '正在导入…' : this.draftPhotoKeys.length > 0 ? '添加图片' : '从相册选图')
            .id('draft-photo-pick').buttonStyle(ButtonStyleMode.TEXTUAL).constraintSize({ minHeight: 48 })
            .padding({ left: 4, right: 8 }).fontColor($r('app.color.timeline_text_body'))
            .enabled(this.libraryReady && this.canChangeDraftPhotos() && this.draftPhotoKeys.length < MAX_POST_PHOTOS)
            .onClick(() => { this.selectDraftPhotos(); })
          if (this.draftPhotoKeys.length === 0) {
            Button('从相册选视频').id('draft-video-pick')
              .buttonStyle(ButtonStyleMode.TEXTUAL).constraintSize({ minHeight: 48 })
              .padding({ left: 4, right: 8 }).fontColor($r('app.color.timeline_text_body'))
              .enabled(this.libraryReady && this.canChangeDraftPhotos()).onClick(() => { this.selectDraftVideo(); })
            Button('从文件选视频').id('draft-video-file-pick')
              .buttonStyle(ButtonStyleMode.TEXTUAL).constraintSize({ minHeight: 48 })
              .padding({ left: 4, right: 8 }).fontColor($r('app.color.timeline_text_body'))
              .enabled(this.libraryReady && this.canChangeDraftPhotos()).onClick(() => { this.selectDraftVideo(true); })
          }
        }.width('100%')
        ForEach(this.draftPhotoKeys, (key: string) => { this.DraftPhotoRow(key) }, (key: string) => key)
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  ComposerDecision() {
    Column({ space: 6 }) {
      Text(this.draftDecision === DraftDecision.Clear ? '清空已经保存的草稿？' :
        this.draftDecision === DraftDecision.RemovePart ? '删除这一段？' : '放弃未保存的修改？')
        .id('composer-decision-title').fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('app.color.timeline_text_primary'))
      Text(this.draftDecision === DraftDecision.Clear ? '已保存的内容与当前修改都会清空。' :
        this.draftDecision === DraftDecision.RemovePart ? '仅移除当前草稿的这一段。保存草稿后才覆盖原稿。' :
          '之前保存到本机的内容会保留。')
        .fontSize(13).fontColor($r('app.color.timeline_text_secondary'))
      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(4) } }) {
        Button('继续编辑').id('composer-keep').constraintSize({ minHeight: 48, maxWidth: '100%' })
          .width(this.stackedComposerActions() ? '100%' : 'auto').padding({ left: 14, right: 14 })
          .backgroundColor($r('app.color.timeline_action')).fontColor($r('app.color.timeline_on_action'))
          .onClick(() => { this.draftDecision = DraftDecision.None; })
        Button(this.draftDecision === DraftDecision.Clear ? '确认清空' :
          this.draftDecision === DraftDecision.RemovePart ? '确认删除此段' : '放弃修改并返回')
          .id('composer-discard').constraintSize({ minHeight: 48, maxWidth: '100%' })
          .width(this.stackedComposerActions() ? '100%' : 'auto').buttonStyle(ButtonStyleMode.TEXTUAL)
          .fontColor($r('app.color.timeline_text_body'))
          .onClick(() => {
            if (this.draftDecision === DraftDecision.Clear) {
              this.savePostDraft(true);
            } else if (this.draftDecision === DraftDecision.RemovePart) {
              this.removeDraftPart();
            } else {
              this.discardPostEdits();
            }
          })
      }.width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 18, right: 18, top: 8, bottom: 8 })
  }

  @Builder
  ComposerFooter() {
    Divider().strokeWidth(0.5).color($r('app.color.timeline_border'))
    Scroll() {
      if (this.draftDecision !== DraftDecision.None) {
        this.ComposerDecision()
      } else {
        this.ComposerActions()
      }
    }.width('100%').constraintSize({ maxHeight: this.composerActionHeight() }).scrollBar(BarState.Auto)
  }

  @Builder
  ComposerActions() {
    Column({ space: 4 }) {
        if (this.postDraftMessage.length > 0) {
          Text(this.postDraftMessage).fontSize(13).fontColor($r('app.color.timeline_text_secondary'))
        }
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.End, space: { main: LengthMetrics.vp(10), cross: LengthMetrics.vp(4) } }) {
          Button(this.postDraftBusy ? '正在写入…' : '保存草稿').id('composer-save')
            .buttonStyle(ButtonStyleMode.TEXTUAL).constraintSize({ minHeight: 48, maxWidth: '100%' })
            .width(this.stackedComposerActions() ? '100%' : 'auto').padding({ left: 12, right: 12 })
            .fontColor($r('app.color.timeline_text_body'))
            .enabled(this.canSavePostDraft()).onClick(() => { this.savePostDraft(false); })
          Button(this.draftParts.length > 1 ? '预览整串' : '预览帖子').id('thread-preview')
            .constraintSize({ minHeight: 48, maxWidth: '100%' })
            .width(this.stackedComposerActions() ? '100%' : 'auto')
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .backgroundColor($r('app.color.timeline_action')).fontColor($r('app.color.timeline_on_action'))
            .enabled(this.canPreviewPostDraft()).onClick(() => this.openPostPreview())
        }.width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 18, right: 18, top: 8, bottom: 8 })
  }

  @Builder
  ComposerContent() {
    Column() {
      this.ComposerHeading(false)
      Scroll(this.composerScroller) {
        Column({ space: 10 }) {
          Text('只保存在这台设备，不会发布到 Threads。').fontSize(13).fontColor($r('app.color.timeline_text_secondary'))
          if (this.postDraftReady) {
            ThreadPartPicker({ count: this.draftParts.length, activeIndex: this.activeDraftPart,
              maxParts: MAX_THREAD_PARTS, editable: this.canChangeDraftPhotos(),
              onSelect: (index: number) => this.selectDraftPart(index), onAdd: () => this.addDraftPart(),
              onMove: (direction: number) => this.moveDraftPart(direction),
              onRemove: () => { if (this.canChangeDraftPhotos() && this.draftParts.length > 1) {
                this.stopComposerInput();
                this.draftDecision = DraftDecision.RemovePart;
              } } })
            ForEach([this.composerInputVersion], (version: number) => {
              TextArea({ text: this.postDraft, controller: this.composerInput, placeholder: '此刻，想写点什么？' })
                .id('draft-part-body').width('100%').constraintSize({ minHeight: 132, maxHeight: 260 }).maxLength(POST_DRAFT_LIMIT)
                .padding({ top: 10, bottom: 10, left: 0, right: 0 }).fontSize(16)
                .fontColor($r('app.color.timeline_text_body')).placeholderColor($r('app.color.timeline_text_muted'))
                .backgroundColor(Color.Transparent).borderRadius(0)
                .accessibilityText('写帖草稿正文')
                .enabled(!this.postDraftBusy && !this.photoPicking && this.draftDecision === DraftDecision.None)
                .onChange((value: string) => this.updateComposerInput(version, value))
            }, (version: number) => version.toString())
            Text(`${this.postDraft.length} / ${POST_DRAFT_LIMIT}`).fontSize(12)
              .width('100%').textAlign(TextAlign.End).fontColor($r('app.color.timeline_text_secondary'))
            this.ComposerAttachments()
            if (this.draftParts.length > 1 && !this.canPreviewPostDraft() && this.draftDecision === DraftDecision.None) {
              Text('未写完也可存草稿；预览前每段需有文字或附件。').fontSize(13)
                .fontColor($r('app.color.timeline_text_secondary'))
            }
            if (this.savedPostDraft.length > 0 || this.savedDraftPhotoKeys.length > 0 ||
              this.savedDraftVideo !== undefined || this.savedContinuation.length > 0) {
              Button('清空本机草稿').id('composer-clear').constraintSize({ minHeight: 48 })
                .buttonStyle(ButtonStyleMode.TEXTUAL).fontColor($r('app.color.timeline_text_secondary'))
                .enabled(this.canChangeDraftPhotos()).onClick(() => {
                  this.stopComposerInput();
                  this.draftDecision = DraftDecision.Clear;
                })
            }
          } else if (this.postDraftBusy) {
            Text('正在读取本机草稿…').fontSize(14).fontColor($r('app.color.timeline_text_secondary'))
          } else {
            Text(this.postDraftMessage).fontSize(13).fontColor($r('app.color.timeline_text_secondary'))
            Button('重新读取草稿').constraintSize({ minHeight: 48 }).onClick(() => { this.loadPostDraft(); })
          }
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 18, right: 18, top: 12, bottom: 16 })
      }.width('100%').layoutWeight(1).align(Alignment.Top).scrollBar(BarState.Auto)
        .onAppear(() => this.restoreComposerOffset())
      if (this.postDraftReady) { this.ComposerFooter() }
    }.width('100%').height('100%').constraintSize({ maxWidth: 640 })
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
      ListItem() { this.PostCard(post, false, true, false, 'search') }
    }, (post: MockPost) => post.id + ':' + post.body)
  }

  @Builder
  AuthorPostRows(post: MockPost) {
    if (!this.hiddenIds.includes(post.id)) {
      ListItem() { this.PostCard(post, false, false, false, 'author') }
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
              author: reply.author, body: reply.body, kind: 'reply' }, 'profile-reply-' + reply.id))
          Button('删除回复').buttonStyle(ButtonStyleMode.TEXTUAL).constraintSize({ minHeight: 44 })
            .enabled(this.libraryReady && !this.libraryBusy).fontColor($r('app.color.timeline_text_secondary'))
            .onClick(() => { this.removeReply(reply); })
          Divider().strokeWidth(0.5).color($r('app.color.timeline_border'))
        }.width('100%').alignItems(HorizontalAlign.Start)
      }, (reply: DemoReply) => reply.id)
    } else {
      ForEach(this.profilePosts(), (post: MockPost) => { this.PostCard(post, false, true, false, 'profile') },
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
        Text('只修改首段正文；后续段落、附件、讨论和互动会保留。')
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
            .enabled(!this.libraryBusy && this.canSavePostEdit()).onClick(() => { this.savePostEdit(); })
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
        Column() {
          if (this.showingPostPreview) {
            this.PostPreviewContent()
          } else {
            this.ComposerContent()
          }
        }.width('100%').height('100%').alignItems(HorizontalAlign.Center)
          .onAreaChange((_previous: Area, current: Area) => {
            const height = Number(current.height);
            if (Number.isFinite(height) && height > 0) { this.composerHeight = height; }
          })
      }.hideTitleBar(true).backgroundColor($r('app.color.timeline_surface'))
        .onWillShow(() => this.setComposerKeyboard(true))
        .onWillHide(() => this.setComposerKeyboard(false))
        .onBackPressed(() => {
          this.requestComposerExit();
          return true;
        })
    } else if (name === PHOTO_VIEWER) {
      NavDestination() {
        if (this.viewerPhotoKeys.length > 0) {
          PhotoViewer({ uris: this.photoUris(this.viewerPhotoKeys), initialIndex: this.viewerPhotoIndex,
            motionEnabled: this.allowsMotionFeedback(), onClose: () => this.closePost() })
        }
      }.hideTitleBar(true).backgroundColor($r('app.color.timeline_surface'))
        .onBackPressed(() => { this.closePost(); return true; })
    } else if (name === VIDEO_PLAYER) {
      NavDestination() {
        if (this.playerVideo !== undefined) {
          PostVideoPlayer({ uri: this.videoUri(this.playerVideo.key), posterUri: this.videoUri(this.playerVideo.key, true),
            durationMs: this.playerVideo.durationMs, active: this.appForeground && this.videoDestinationVisible,
            onClose: () => this.closeVideo() })
        }
      }.hideTitleBar(true).backgroundColor($r('app.color.timeline_surface'))
        .onShown(() => { this.videoDestinationVisible = true; })
        .onWillHide(() => { this.videoDestinationVisible = false; })
        .onBackPressed(() => { this.closeVideo(); return true; })
    } else if (name === PUBLIC_THREADS) {
      NavDestination() {
        ThreadsPublicPane({ onClose: () => this.closePost() })
      }.hideTitleBar(true).backgroundColor($r('app.color.timeline_surface'))
        .onBackPressed(() => { this.closePost(); return true; })
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
        .onShown(() => { this.authorShown = true; this.restoreDiscussionFocus(); })
        .onWillHide(() => { this.authorShown = false; })
        .onBackPressed(() => { this.closePost(); return true; })
    } else if (name === POST_DETAIL && post !== undefined) {
      NavDestination() {
        this.DetailContent(post)
      }.hideTitleBar(true).backgroundColor($r('app.color.timeline_surface'))
        .onShown(() => { this.discussionShown = this.activeDetailId === post.id; })
        .onWillHide(() => { this.discussionShown = false; })
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
      onTopic: (topic: string) => { this.searchQuery = topic; this.discoveryMode = 0; },
      onPublicThreads: () => this.openPublicThreads() })
  }

  @Builder
  ProfileRoot() {
    LibraryHub({ identity: this.identity, mode: this.libraryMode, mediaMode: this.profileMediaMode,
      onMediaMode: (value: number) => { this.profileMediaMode = value; },
      hasItems: this.libraryMode === 3 ? this.localReplies.length > 0 : this.profilePosts().length > 0,
      busy: this.libraryLoading || this.libraryBusy || this.identityBusy,
      message: this.libraryReady ? (this.identityMessage || this.libraryMessage) : (this.libraryMessage || this.identityMessage),
      onRetryRead: !this.libraryReady && !this.libraryLoading ? () => { this.loadLibrary(); } : undefined,
      onBrowse: () => this.selectTab(ShellTab.Home),
      items: () => { this.ProfileItems() }, onMode: (value: number) => { this.libraryMode = value; },
      onEdit: () => { this.openIdentity(); }, onCompose: () => this.openComposer(), onSettings: () => this.openSettings(),
      onWeb: () => { this.openWeb(); } })
  }

  @Builder
  ActivityRoot() {
    ActivityPane({ entries: this.activityEntries(),
      onOpen: (entry: ActivityEntry) => this.openActivityPost(entry, 'activity-entry-' + entry.id) })
  }

  @Builder
  Shell() {
    ReadingTabs({ activeIndex: this.selectedTab, wide: this.sideNavigation,
      home: () => { this.Feed() }, search: () => { this.SearchRoot() },
      activity: () => { this.ActivityRoot() }, profile: () => { this.ProfileRoot() },
      onSelectTab: (index: number) => this.selectTab(index as ShellTab), onCompose: () => this.openComposer() })
      .width('100%').height('100%').backgroundColor($r('app.color.timeline_surface'))
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        const width = Number(newArea.width);
        this.updateViewportWidth(width);
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
      .padding({ left: FEED_INLINE_PADDING, right: FEED_INLINE_PADDING, bottom: 12 })
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
        this.updateFeedWidth(Number(newArea.width));
      })
  }

  build() {
    Navigation(this.detailPaths) {
      this.Shell()
    }
    .width('100%').height('100%').mode(NavigationMode.Stack).hideTitleBar(true)
    .navDestination(this.DetailDestination)
    .onNavBarStateChange((shown: boolean) => {
      this.shellShown = shown;
      if (shown) { this.restoreDiscussionFocus(); }
    })
  }
}
