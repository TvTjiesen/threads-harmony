import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';
import vm from 'node:vm';

const readSource = (relative) => readFileSync(new URL(`../app/entry/src/main/ets/${relative}.ets`, import.meta.url), 'utf8');
const loadModel = (name) => import(`data:text/javascript,${encodeURIComponent(stripTypeScriptTypes(readSource(`model/${name}`)))}`);
const library = await loadModel('LocalLibrary');
const identity = await loadModel('LocalIdentity');
const source = readSource('pages/Timeline');
const paneSource = readSource('components/ConversationPane');

// Run the production state, fixtures and methods together; replace only the native platform boundary.
function stateClass(source) {
  const end = source.search(/^  @Builder\s*$/m);
  assert.ok(end > 0, 'missing ArkUI builder boundary');
  return source.slice(0, end).replace(/^import\s+[^;]+;\r?$/gm, '').replace(/^export /gm, '')
    .replace(/^@(Entry|Component)\s*$/gm, '').replace(/^struct /m, 'class ')
    .replace(/@(State|StorageProp|Watch|Prop|BuilderParam)\b(?:\('[^']*'\))?\s+/g, '') + '\n}';
}
class NavPathStack {
  entries = [];
  animations = [];
  size() { return this.entries.length; }
  getAllPathName() { return this.entries.map(({ name }) => name); }
  pushPath(entry, animate) { this.entries.push(entry); this.animations.push(animate); }
  pop(result, animate) { this.animations.push(animate); this.entries.pop()?.onPop?.(result); }
}
const platform = { FrameCallback: class {}, Scroller: class {}, TextAreaController: class {},
  ScrollAlign: { START: 'start' } };
const { Timeline, ShellTab } = vm.runInNewContext(stripTypeScriptTypes(`${stateClass(source)}\n({ Timeline, ShellTab });`,
  { mode: 'transform' }), {
  ...library, ...identity, ...platform, NavPathStack, SegmentButtonV2Items: class {}, LengthMetrics: { vp: n => n }
});
const Pane = vm.runInNewContext(stripTypeScriptTypes(`${stateClass(paneSource)}\nConversationPane;`), {
  ...platform, KeyboardAvoidMode: { RESIZE: 'resize' }
});

function session() {
  const page = new Timeline();
  const messages = [], frames = [], scrolls = [];
  page.getUIContext = () => ({
    postFrameCallback: frame => frames.push(frame),
    getPromptAction: () => ({ showToast: ({ message }) => messages.push(message) })
  });
  page.timelineScroller = {
    offset: () => ({ yOffset: 160 }), getItemRect: () => ({ height: 80, y: -13 }),
    scrollToIndex: (...args) => scrolls.push(args)
  };
  page.onPageShow();
  page.libraryReady = true;
  page.saveLibrary = async value => {
    page.applyLibrary(value);
    return true;
  };
  const [post, other] = page.timelinePosts;
  const [first, second] = page.repliesFor(post.id);
  const [foreign] = page.repliesFor(other.id);
  return { page, post, other, first, second, foreign, stack: page.detailPaths, messages, frames, scrolls };
}

function assertRecipient(page, focusId, targetId, expanded) {
  assert.equal(page.focusedReplyId, focusId, 'highlight/scroll destination');
  assert.equal(page.replyTargetId, targetId, 'reply recipient');
  assert.equal(page.replyExpanded, expanded, 'explicit composer expansion');
}

test('body, valid exact reply, unknown and foreign reply open only one detail with the correct context', () => {
  const { page, post, other, second, foreign, stack } = session();
  page.firstVisibleIndex = 1;
  page.replyDraft = '上一条的残留内容';
  for (const [requested, expected] of [[undefined, ''], [second.id, second.id], ['missing-id', ''], [foreign.id, '']]) {
    page.openPost(post, requested);
    page.openPost(other, foreign.id);
    assert.equal(stack.size(), 1);
    assert.equal(stack.entries[0].param.id, post.id);
    assert.equal(page.activeDetailId, post.id);
    assert.equal(page.timelineVisible, false);
    assert.equal(page.replyDraft, '');
    assertRecipient(page, expected, expected, false);
    assert.deepEqual({ ...page.readingAnchor }, { postId: other.id, clipped: 13 });
    page.requestDetailBack();
    assert.equal(stack.size(), 0);
    assert.equal(page.activeDetailId, '');
    assert.equal(page.timelineVisible, true);
  }
  page.openSettings();
  page.openPost(post, second.id);
  assert.deepEqual(stack.getAllPathName(), ['Settings'], 'other destinations cannot be bypassed');
});

test('a dirty draft never changes recipients or vanishes when another reply or the original author is tapped', () => {
  const { page, post, first, second, messages, stack } = session();
  page.openPost(post);
  page.expandCurrentReply(post.id);
  assertRecipient(page, '', '', true);
  page.replyDraft = '给原作者的草稿';
  page.beginReply(post.id, first.id);
  assert.equal(page.replyTargetId, '');
  assert.equal(page.replyDraft, '给原作者的草稿');
  assert.ok(messages.length > 0, 'tell the user why the recipient did not change');

  page.replyDraft = '';
  page.beginReply(post.id, first.id);
  assert.equal(page.replyTargetId, first.id);
  page.replyDraft = '  给第一位回复人的内容\n第二行';
  const messageCount = messages.length;
  page.beginReply(post.id, first.id);
  assert.equal(messages.length, messageCount, 'continuing the same recipient needs no warning');
  for (const target of [second.id, '']) {
    const before = messages.length;
    page.beginReply(post.id, target);
    assert.equal(page.replyExpanded, true);
    assert.equal(page.replyTargetId, first.id);
    assert.equal(page.replyDraft, '  给第一位回复人的内容\n第二行');
    assert.ok(messages.length > before);
  }
  assert.equal(stack.size(), 1);
});

test('Back protects text before popping: keep resumes the same draft, discard leaves, empty editor collapses first', async () => {
  const { page, post, second, stack } = session();
  page.openPost(post, second.id);
  page.expandCurrentReply(post.id);
  assertRecipient(page, second.id, second.id, true);
  page.replyDraft = '  还没发的回复\n';
  page.requestDetailBack();
  assert.equal(page.replyExitPending, true);
  assert.equal(stack.size(), 1);
  await page.submitReply(post.id);
  assert.equal(page.localReplies.length, 0, 'old send action cannot commit while confirming an exit');
  page.keepReplyDraft();
  assert.equal(page.replyExitPending, false);
  assert.equal(page.replyDraft, '  还没发的回复\n');
  assertRecipient(page, second.id, second.id, true);
  page.requestDetailBack();
  page.discardReplyAndClose();
  assert.equal(stack.size(), 0);
  assert.equal(page.replyDraft, '');
  assert.equal(page.replyExitPending, false);
  assertRecipient(page, '', '', false);
  assert.equal(page.localReplies.length, 0);

  page.openPost(post);
  page.expandCurrentReply(post.id);
  page.requestDetailBack();
  assert.equal(stack.size(), 1, 'empty editor consumes one Back');
  assert.equal(page.replyExpanded, false);
  assert.equal(page.replyExitPending, false);
  page.requestDetailBack();
  assert.equal(stack.size(), 0);
});

test('submission requires the active post and expanded composer, saves the chosen person once and focuses the new reply', async () => {
  const { page, post, other, second } = session();
  page.openPost(post, second.id);
  page.replyDraft = 'stale callback on a collapsed composer';
  await page.submitReply(post.id);
  assert.equal(page.localReplies.length, 0);
  page.replyDraft = '';
  page.expandCurrentReply(post.id);
  for (const invalid of ['', ' \n\t', 'x'.repeat(281)]) {
    page.replyDraft = invalid;
    await page.submitReply(post.id);
    assert.equal(page.localReplies.length, 0);
    assert.equal(page.replyDraft, invalid);
  }
  const text = '复'.repeat(280);
  page.replyDraft = text;
  for (const wrong of [other.id, 'missing']) {
    await page.submitReply(wrong);
    assert.equal(page.localReplies.length, 0);
    assert.equal(page.replyDraft, text);
    assert.equal(page.replyTargetId, second.id);
  }
  await page.submitReply(post.id);
  const [sent] = page.localReplies;
  assert.deepEqual([sent.postId, sent.parentId, sent.toAuthor, sent.body, sent.local],
    [post.id, second.id, second.author, text, true]);
  assert.equal(page.replyDraft, '');
  assertRecipient(page, sent.id, '', false);
  await page.submitReply(post.id);
  assert.equal(page.localReplies.length, 1, 'double tap cannot publish twice');
  assert.equal(page.replyCount(post), post.replies + 1);
  assert.equal(page.replyCount(other), other.replies);
  const ordered = Array.from(page.repliesFor(post.id), reply => reply.id);
  assert.equal(ordered[ordered.indexOf(second.id) + 1], sent.id, 'read a nested reply immediately after its parent');
  assert.ok(page.repliesFor(other.id).every(reply => reply.postId === other.id));

  page.beginReply(post.id, sent.id);
  page.replyDraft = '  继续回复本机回复  ';
  await page.submitReply(post.id);
  const child = page.localReplies.find(reply => reply.id !== sent.id);
  assert.deepEqual([child.parentId, child.toAuthor, child.body], [sent.id, sent.author, '继续回复本机回复']);
  assertRecipient(page, child.id, '', false);
  page.requestDetailBack();
  page.replyDraft = 'too late';
  await page.submitReply(post.id);
  assert.equal(page.localReplies.length, 2);
  const fresh = new Timeline();
  assert.equal(fresh.replyCount(post), post.replies, 'fresh page does not show local replies before loading the library');
  fresh.applyLibrary(page.library);
  assert.equal(fresh.replyCount(post), post.replies + 2);
  const restored = fresh.repliesFor(post.id).find(reply => reply.id === child.id);
  assert.deepEqual([restored.parentId, restored.toAuthor, restored.body], [sent.id, sent.author, child.body]);
});

test('a failed local write keeps the exact draft and recipient and can be retried without duplicating replies', async () => {
  const { page, post, second, stack } = session();
  page.openPost(post, second.id);
  page.expandCurrentReply(post.id);
  const draft = '  回复原来的收件人\n';
  page.replyDraft = draft;
  const save = page.saveLibrary;
  let rejectWrite;
  page.saveLibrary = () => new Promise(resolve => { rejectWrite = () => resolve(false); });
  const pending = page.submitReply(post.id);
  assert.equal(page.replyDraft, draft, 'only a successful write consumes the draft');
  assertRecipient(page, second.id, second.id, true);
  rejectWrite();
  await pending;
  assert.equal(page.replyDraft, draft);
  assertRecipient(page, second.id, second.id, true);
  assert.equal(page.localReplies.length, 0);
  assert.equal(stack.size(), 1);

  page.saveLibrary = save;
  await page.submitReply(post.id);
  const [sent] = page.localReplies;
  assert.deepEqual([page.localReplies.length, sent.body, sent.parentId, sent.toAuthor],
    [1, draft.trim(), second.id, second.author]);
  assert.equal(page.replyDraft, '');
  assertRecipient(page, sent.id, '', false);
});

test('the feed shows the latest reply to this post even when discussion order nests it under a parent', async () => {
  const { page, post, other, first, second, foreign } = session();
  assert.equal(page.previewReply(post.id).id, first.id);
  assert.equal(page.previewReply(other.id).id, foreign.id);
  assert.equal(page.previewReply('missing-post'), undefined);
  page.openPost(post, second.id);
  page.expandCurrentReply(post.id);
  page.replyDraft = '最新的深层回复';
  await page.submitReply(post.id);
  const latest = page.focusedReplyId;
  assert.equal(page.repliesFor(post.id)[0].id, first.id);
  page.requestDetailBack();
  page.openPost(other);
  page.expandCurrentReply(other.id);
  page.replyDraft = '另一帖中更新的回复';
  await page.submitReply(other.id);
  page.requestDetailBack();
  assert.deepEqual(Array.from(page.previewRows('missing-post')), []);
  const summaries = page.previewRows(post.id);
  assert.equal(summaries.length, 1);
  const preview = summaries[0];
  assert.deepEqual([preview.id, preview.body], [latest, '最新的深层回复']);
  page.openPost(post, preview.id);
  assertRecipient(page, latest, latest, false);
});

test('the detail builder wires root and reply recipients, context, draft protection and send to the current post', async () => {
  const body = source.match(/^  DetailContent\([^\n]*\) \{([\s\S]*?)^  \}/m)?.[1];
  assert.ok(body, 'missing detail builder');
  const optionsFor = vm.runInNewContext(stripTypeScriptTypes(`(function(post) { ${body.trim().replace(/^ConversationPane\(/, 'return (')} })`));
  const { page, post, second, stack } = session();
  page.openPost(post);
  const options = () => optionsFor.call(page, post);
  assert.equal(options().contextLine, post.body);
  assert.equal(options().recipient, post.handle);
  assert.equal(options().expanded, false);
  const rendered = [];
  page.DiscussionRoot = item => rendered.push(item.id);
  options().rootPost();
  assert.deepEqual(rendered, [post.id]);
  page.fontScale = 2;
  assert.equal(options().largeText, true);
  options().onEdit(second.id);
  const author = page.timelinePosts.find(item => item.name === second.author);
  assert.equal(options().recipient, author?.handle ?? '@' + second.author);
  assert.equal(options().contextLine, second.body);
  assert.equal(options().expanded, true);
  options().onDraft('准确保留上下文');
  options().onBack();
  assert.equal(options().confirmLeave, true);
  options().onKeep();
  assert.equal(options().draft, '准确保留上下文');
  await options().onSend();
  const nested = page.localReplies[0];
  assert.equal(options().focusId, nested.id);
  assert.equal(options().expanded, false);
  assert.deepEqual([nested.postId, nested.parentId, nested.toAuthor], [post.id, second.id, second.author]);
  assert.equal(options().contextLine, post.body, 'the next reply does not inherit the old recipient');

  options().onExpand();
  options().onDraft('新的根回复');
  await options().onSend();
  const root = options().rows[0];
  assert.deepEqual([root.parentId, root.toAuthor, root.body, root.id], [undefined, post.name, '新的根回复', options().focusId]);
  options().onExpand();
  options().onDraft('不发送');
  options().onBack();
  options().onDiscard();
  assert.equal(stack.size(), 0);
  assert.equal(page.replyCount(post), post.replies + 2);
});

test('an activity reply reopens by its exact ID, while an activity like opens the post; origin survives both trips', async () => {
  const { page, post, first, stack } = session();
  page.openPost(post, first.id);
  page.expandCurrentReply(post.id);
  page.replyDraft = '用于定位的本机回复';
  await page.submitReply(post.id);
  const sent = page.localReplies[0];
  page.requestDetailBack();
  page.likedIds = [post.id];
  page.selectTab(ShellTab.Activity);
  const entries = page.activityEntries();
  for (const [kind, expected] of [['reply', sent.id], ['like', '']]) {
    page.openActivityPost(entries.find(entry => entry.kind === kind));
    assertRecipient(page, expected, expected, false);
    page.requestDetailBack();
    assert.equal(stack.size(), 0);
    assert.equal(page.selectedTab, ShellTab.Activity);
    assert.equal(page.timelineVisible, false);
  }
});

test('a post detail opened from an author page returns there before returning to the same search', () => {
  const { page, post, other, second, stack } = session();
  page.selectTab(ShellTab.Search);
  page.searchQuery = post.handle;
  page.openAuthor(post.id);
  assert.deepEqual(stack.getAllPathName(), ['AuthorProfile']);
  assert.equal(stack.entries[0].param.id, post.id);
  page.openAuthor(other.id);
  assert.equal(stack.size(), 1, 'opening an author does not stack over an author');
  page.openPost(post, second.id);
  assert.deepEqual(stack.getAllPathName(), ['AuthorProfile', 'PostDetail']);
  assertRecipient(page, second.id, second.id, false);
  page.requestDetailBack();
  assert.deepEqual(stack.getAllPathName(), ['AuthorProfile']);
  assert.equal(page.activeDetailId, '');
  stack.pop(undefined, false);
  assert.equal(page.selectedTab, ShellTab.Search);
  assert.equal(page.searchQuery, post.handle);
});

test('the native list resolves the exact ID after layout and never animates, replays old jumps or scrolls after leaving', () => {
  const pane = new Pane();
  const frames = [], calls = [];
  pane.getUIContext = () => ({ postFrameCallback: frame => frames.push(frame) });
  pane.listScroller.scrollToIndex = (...args) => calls.push(args);
  pane.aboutToAppear();
  pane.rows = [{ id: 'first' }, { id: 'second' }];
  pane.focusId = 'second';
  assert.equal(pane.targetIndex(), 2, 'index zero is the original post');
  pane.targetChanged();
  assert.equal(frames.length, 0, 'do not access list geometry before it mounts');
  pane.listMounted = true;
  pane.scheduleTarget();
  pane.rows = [{ id: 'new' }, ...pane.rows];
  pane.scheduleTarget();
  assert.equal(frames.length, 1);
  frames.shift().onIdle(0);
  assert.deepEqual(calls.splice(0), [[3, false, 'start']], 'resolve after insertion, not by the stale position');
  pane.scheduleTarget();
  assert.equal(frames.length, 0, 'a refresh of the same rows cannot hijack manual reading');
  pane.focusId = 'absent';
  pane.targetChanged();
  frames.shift().onIdle(0);
  assert.deepEqual(calls, [], 'missing target falls back without jumping to an unrelated row');
  pane.focusId = 'first';
  pane.targetChanged();
  pane.focusId = 'new';
  pane.targetChanged();
  frames.shift().onIdle(0);
  assert.deepEqual(calls.splice(0), [[1, false, 'start']], 'a pending frame must honor a newer target');
  pane.focusId = 'second';
  pane.targetChanged();
  pane.aboutToDisappear();
  frames.shift().onIdle(0);
  assert.deepEqual(calls, []);
  assert.match(paneSource, /initialIndex:\s*Math\.max\(0, this\.targetIndex\(\)\)/);
  assert.match(paneSource, /@Watch\('targetChanged'\) focusId/);
  assert.match(paneSource, /@Watch\('scheduleTarget'\) rows/);
  assert.match(paneSource, /\.onAppear\(\(\) => \{\s*this\.listMounted = true;\s*this\.scheduleTarget\(\)/);
});

test('reading never requests input focus; editing requests resize and restores the previous keyboard policy', () => {
  const pane = new Pane(), frames = [], modes = [], focus = [];
  let mode = 'offset';
  pane.getUIContext = () => ({
    getKeyboardAvoidMode: () => mode, setKeyboardAvoidMode: value => { mode = value; modes.push(value); },
    postFrameCallback: frame => frames.push(frame), getFocusController: () => ({ requestFocus: id => focus.push(id) })
  });
  pane.aboutToAppear();
  assert.deepEqual([modes, frames, focus], [[], [], []]);
  pane.expanded = true;
  pane.syncKeyboardMode();
  pane.focusEditor();
  frames.shift().onIdle(0);
  assert.deepEqual(modes, ['resize']);
  assert.deepEqual(focus, ['convo-input']);
  pane.focusEditor();
  pane.confirmLeave = true;
  pane.syncKeyboardMode();
  frames.shift().onIdle(0);
  assert.deepEqual(modes, ['resize', 'offset']);
  assert.deepEqual(focus, ['convo-input'], 'confirmation cancels a pending focus transfer');
  pane.confirmLeave = false;
  pane.syncKeyboardMode();
  pane.aboutToDisappear();
  assert.deepEqual(modes, ['resize', 'offset', 'resize', 'offset']);
  assert.match(paneSource, /if \(this\.confirmLeave\)[\s\S]*?this\.LeaveDecision\(\)[\s\S]*?else if \(this\.expanded\)[\s\S]*?this\.Editor\(\)[\s\S]*?else \{\s*this\.CollapsedEntry\(\)/);
  assert.match(paneSource, /TextArea\(\{ text: this\.draft,[\s\S]*?\.onChange\(\(value: string\) => this\.onDraft\(value\)\)\.onAppear\(\(\) => this\.focusEditor\(\)\)/);
});

test('discussion actions reflow without remounting the text input', () => {
  const pane = new Pane();
  assert.equal(pane.stackReplyActions(), false);
  pane.paneWidth = 320;
  assert.equal(pane.stackReplyActions(), true);
  pane.paneWidth = 410;
  assert.equal(pane.stackReplyActions(), false);
  pane.largeText = true;
  assert.equal(pane.stackReplyActions(), true);
  assert.equal((paneSource.match(/this\.ReplyInput\(\)/g) ?? []).length, 1);
  assert.match(paneSource, /flexBasis\(this\.stackReplyActions\(\) \? '100%' : '50%'\)/);
});

test('window resizing stabilizes the side rail and keeps the same reading anchor', () => {
  const { page, other, frames } = session();
  page.firstVisibleIndex = 1;
  page.updateViewportWidth(839);
  assert.equal(page.sideNavigation, false);
  page.updateViewportWidth(840);
  assert.equal(page.sideNavigation, true);
  assert.equal(page.readingAnchor.postId, other.id);
  for (const width of [838, 822, 816]) page.updateViewportWidth(width);
  assert.equal(page.sideNavigation, true);
  page.updateViewportWidth(815);
  assert.equal(page.sideNavigation, false);
  page.updateViewportWidth(0);
  assert.equal(page.viewportWidth, 815);
  assert.equal(frames.length, 1, 'resize samples in one frame only request one reading restore');
  assert.equal(page.readingAnchor.postId, other.id);
});

test('reply navigation keeps originating filters, reading anchor and motion policy without jumping to Home', () => {
  for (const [tab, localReduce, systemReduce, animate] of [
    [ShellTab.Home, false, false, true], [ShellTab.Search, true, false, false],
    [ShellTab.Profile, false, true, false], [ShellTab.Activity, true, true, false]
  ]) {
    const { page, post, other, second, stack, frames, scrolls } = session();
    page.followedIds = [post.id, other.id];
    page.selectFeed(true);
    frames.shift().onIdle(0);
    page.firstVisibleIndex = 1;
    page.searchQuery = '未清除的搜索';
    page.libraryMode = 1;
    page.rememberReadingPosition();
    page.selectTab(tab);
    page.motionPreferenceReady = true;
    page.setReduceMotion(localReduce);
    page.systemReducesMotion = systemReduce;
    scrolls.length = 0;
    page.openPost(post, second.id);
    assert.equal(stack.size(), 1);
    assert.equal(page.onBackPress(), false, 'the top destination owns Back');
    page.selectTab(ShellTab.Home);
    page.requestDetailBack();
    assert.deepEqual(stack.animations, [animate, animate]);
    assert.equal(page.selectedTab, tab);
    assert.equal(page.followingOnly, true);
    assert.equal(page.searchQuery, '未清除的搜索');
    assert.equal(page.libraryMode, 1);
    assert.deepEqual({ ...page.readingAnchor }, { postId: other.id, clipped: 13 });
    assert.deepEqual(scrolls, [], 'no reflow: do not scroll the feed merely because a detail closed');
  }
});
