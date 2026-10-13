import type { AgentRowStatus, TodoStatus } from '../types'

export type Lang = 'en' | 'ko'

/**
 * Everything the person reads. Text the model reads (the step guide, the title prompt, tool results) stays English
 * in every language — it is instructions, not interface.
 */
export type Messages = {
  paneTitle: string
  commandDescription: string
  commandOpened: string
  emptyRequest: string
  seconds: (s: number) => string
  minutes: (m: number, s: number) => string
  hours: (h: number, m: number) => string
  ago: (time: string) => string
  stepStatus: Record<TodoStatus, string>
  agentStatus: Record<AgentRowStatus, string>
  phase: Record<string, string>
  running: (time: string) => string
  interrupted: (time: string) => string
  // Banner above the prompt
  agentsLabel: string
  agentsDone: (done: number, total: number) => string
  runLabel: string
  runSummary: (percent: number, workers: number) => string
  gates: (passed: number, total: number) => string
  moreWorkers: (n: number) => string
  // Pane
  planHeader: string
  noSteps: string
  runHeader: (root: string) => string
  runIdle: string
  runOverall: (percent: number, workers: number) => string
  attempt: (n: number) => string
  session: (name: string) => string
  error: (text: string) => string
  noGates: string
  historyHeader: (n: number) => string
  historyHint: string
  noHistory: string
  latest: string
  scrollInfo: (from: number, to: number, total: number) => string
  collapseHistory: string
  collapseWorkers: string
  expandWorkers: string
  // Context and the dragon
  dragonName: string
  dragonFlavor: readonly string[]
  measuring: string
  context: (percent: string) => string
  regrow: string
  regrowQueued: string
  regrowRunning: string
  evolving: string
  devolving: string
  evolvingShort: string
  devolvingShort: string
  maxed: string
  toastQueued: string
  toastSkipped: (reason: string) => string
  toastCompacted: string
  toastFailed: string
}

const en: Messages = {
  paneTitle: 'Session progress',
  commandDescription: 'Open the pane with this session’s plan, task history and dev-loop run',
  commandOpened: 'Opened session progress.',
  emptyRequest: '(empty request)',
  seconds: s => `${s}s`,
  minutes: (m, s) => `${m}m ${s}s`,
  hours: (h, m) => `${h}h ${m}m`,
  ago: time => `${time} ago`,
  stepStatus: { completed: 'done', in_progress: 'in progress', pending: 'pending' },
  agentStatus: {
    pending: 'pending',
    running: 'running',
    waiting: 'waiting',
    idle: 'idle',
    completed: 'done',
    failed: 'failed',
    killed: 'stopped',
    gone: 'gone',
  },
  phase: {
    pending: 'pending',
    planning: 'planning',
    plan_ready: 'planned',
    implementing: 'implementing',
    rework: 'rework',
    impl_done: 'implemented',
    approved: 'approved',
    merged: 'merged',
    done: 'done',
    failed: 'failed',
  },
  running: time => `running ${time}`,
  interrupted: time => `${time} · interrupted`,
  agentsLabel: 'Agents ',
  agentsDone: (done, total) => `${done}/${total} done`,
  runLabel: 'dev-loop ',
  runSummary: (percent, workers) => `${percent}% · ${workers} worker${workers === 1 ? '' : 's'}`,
  gates: (passed, total) => `gates ${passed}/${total}`,
  moreWorkers: n => `… ${n} more worker${n === 1 ? '' : 's'} — see the pane`,
  planHeader: 'Plan (this task)',
  noSteps: 'No steps reported yet.',
  runHeader: root => `dev-loop run · ${root}`,
  runIdle: ' (no recent activity)',
  runOverall: (percent, workers) => `${percent}% overall · ${workers} worker${workers === 1 ? '' : 's'}`,
  attempt: n => `try ${n}`,
  session: name => `session ${name}`,
  error: text => `error: ${text}`,
  noGates: 'no checklist (no gates ledger yet)',
  historyHeader: n => `History (${n})`,
  historyHint: ' · press a task to unfold its plan',
  noHistory: 'No tasks yet.',
  latest: 'Latest',
  scrollInfo: (from, to, total) => `${from}–${to} / ${total} lines · scroll with the wheel over the list`,
  collapseHistory: 'Collapse history',
  collapseWorkers: 'Collapse workers',
  expandWorkers: 'Expand workers',
  dragonName: 'Context Dragon',
  dragonFlavor: [
    'Warm. Something stirs inside.',
    'Peep… no, ROAR?',
    'It has started spitting embers.',
    'Its eyes have changed.',
    'The shadow of its wings covers the screen.',
    'Red light leaks between its scales. Something is wrong.',
    'Too many eyes. Compact now.',
  ],
  measuring: 'not measured',
  context: percent => `context ${percent}`,
  regrow: 'Regrow',
  regrowQueued: '⏳ regrows when this task ends',
  regrowRunning: '⟳ regrowing…',
  evolving: '✦ evolving ✦',
  devolving: '✧ devolving ✧',
  evolvingShort: ' · evolving',
  devolvingShort: ' · devolving',
  maxed: 'Nowhere left to grow',
  toastQueued: 'When this task ends, the context is compacted and the dragon regrows.',
  toastSkipped: reason => `Regrow skipped: ${reason}`,
  toastCompacted: 'Context compacted. Carry on.',
  toastFailed: 'Could not compact the context. Run /compact yourself.',
}

const ko: Messages = {
  paneTitle: '세션 진행 현황',
  commandDescription: '세션 작업 진행률·오케스트레이션 워커 진행률·작업 이력을 pane 으로 연다',
  commandOpened: '세션 진행 현황을 열었습니다.',
  emptyRequest: '(빈 요청)',
  seconds: s => `${s}초`,
  minutes: (m, s) => `${m}분 ${s}초`,
  hours: (h, m) => `${h}시간 ${m}분`,
  ago: time => `${time} 전`,
  stepStatus: { completed: '완료', in_progress: '진행 중', pending: '대기' },
  agentStatus: {
    pending: '대기',
    running: '진행 중',
    waiting: '대기',
    idle: '유휴',
    completed: '완료',
    failed: '실패',
    killed: '중지',
    gone: '종료',
  },
  phase: {
    pending: '대기',
    planning: '계획 중',
    plan_ready: '계획 완료',
    implementing: '구현 중',
    rework: '재작업',
    impl_done: '구현 완료',
    approved: '승인',
    merged: '머지됨',
    done: '완료',
    failed: '실패',
  },
  running: time => `진행 중 ${time}`,
  interrupted: time => `${time} · 중단`,
  agentsLabel: '에이전트 ',
  agentsDone: (done, total) => `${done}/${total} 완료`,
  runLabel: '오케스트레이션 ',
  runSummary: (percent, workers) => `${percent}% · 워커 ${workers}개`,
  gates: (passed, total) => `게이트 ${passed}/${total}`,
  moreWorkers: n => `… 워커 ${n}개 더 — 목록에서 보기`,
  planHeader: '할 일 진행률 (지금 작업)',
  noSteps: '아직 보고된 단계가 없습니다.',
  runHeader: root => `오케스트레이션 · ${root}`,
  runIdle: ' (최근 활동 없음)',
  runOverall: (percent, workers) => `전체 ${percent}% · 워커 ${workers}개`,
  attempt: n => `시도 ${n}`,
  session: name => `세션 ${name}`,
  error: text => `오류: ${text}`,
  noGates: '체크리스트 없음 (게이트 원장이 아직 없습니다)',
  historyHeader: n => `작업 이력 (${n}건)`,
  historyHint: ' · 작업을 누르면 계획 단계가 펼쳐집니다',
  noHistory: '아직 진행된 작업이 없습니다.',
  latest: '최신으로',
  scrollInfo: (from, to, total) => `${from}–${to} / ${total}줄 · 목록 위에서 휠로 스크롤`,
  collapseHistory: '이력 모두 접기',
  collapseWorkers: '워커 모두 접기',
  expandWorkers: '워커 모두 펼치기',
  dragonName: '컨텍스트 드래곤',
  dragonFlavor: [
    '따뜻하다. 안에서 무언가 꿈틀거린다.',
    '삐약… 아니, 크앙?',
    '작은 불씨를 뱉기 시작했다.',
    '눈빛이 달라졌다.',
    '날개 그림자가 화면을 덮는다.',
    '비늘 틈으로 붉은 빛이 샌다. 무언가 잘못됐다.',
    '눈이 너무 많다. 지금 압축하라.',
  ],
  measuring: '측정 전',
  context: percent => `컨텍스트 ${percent}`,
  regrow: '다시 키우기',
  regrowQueued: '⏳ 작업이 끝나면 다시 키웁니다',
  regrowRunning: '⟳ 다시 키우는 중…',
  evolving: '✦ 변신 중 ✦',
  devolving: '✧ 퇴화 중 ✧',
  evolvingShort: ' · 변신 중',
  devolvingShort: ' · 퇴화 중',
  maxed: '더는 자랄 곳이 없다',
  toastQueued: '지금 작업이 끝나면 컨텍스트를 압축하고 용을 다시 키웁니다.',
  toastSkipped: reason => `다시 키우기를 건너뛰었습니다: ${reason}`,
  toastCompacted: '컨텍스트를 압축했습니다. 이어서 작업하면 됩니다.',
  toastFailed: '컨텍스트를 압축하지 못했습니다. /compact 로 직접 압축해 주세요.',
}

export const MESSAGES: Readonly<Record<Lang, Messages>> = { en, ko }

/**
 * The interface language. A pinned option wins; `auto` follows Claude Code's own `language` setting (free text such
 * as "Korean", "한국어", "ko"), then the locale (`LC_ALL`, else `LANG`, as the C library reads them). Anything else
 * is English.
 */
export function pickLanguage(option: unknown, settingsLanguage: unknown, envLang: unknown): Lang {
  if (option === 'en' || option === 'ko') return option
  if (typeof settingsLanguage === 'string' && settingsLanguage.trim() !== '') {
    return /^\s*(ko\b|ko[-_]|kor|한국)/i.test(settingsLanguage) ? 'ko' : 'en'
  }
  if (typeof envLang === 'string' && /^ko([-_.]|$)/i.test(envLang)) return 'ko'

  return 'en'
}
