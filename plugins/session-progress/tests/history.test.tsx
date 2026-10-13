import type { On } from 'claude-code'
import { describe, expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'

import { briefTitle, cleanTitle, combineTodos, compactText } from '../hooks/format'
import { MESSAGES } from '../hooks/i18n'
import { buildHistoryRows, cellWidth, cutToWidth, layoutHistoryLines, spinnerAt } from '../hooks/tree'
import type { HistoryLine } from '../hooks/tree'
import type { AgentRow, Todo, Turn } from '../types'

const BAND = {
  component: 'AbovePrompt',
  props: {
    hasSurvey: false,
    isWorking: true,
    maxRows: 12,
    bodyColumns: 120,
    scroll: { offset: 0, bodyRows: 11 },
    view: {},
  },
} as const

const T1: Turn = {
  id: 'T1',
  text: '첫 작업',
  startedAt: 0,
  endedAt: 60_000,
  outcome: 'answer',
  tools: 2,
  steps: [
    { title: '분석', status: 'completed' },
    { title: '구현', status: 'in_progress' },
    { title: '배포', status: 'pending' },
  ],
}
const T2: Turn = { id: 'T2', text: '두 번째 작업', startedAt: 70_000, tools: 0 }
const AGENT: AgentRow = { id: 'a1', description: '파일 찾기', type: 'Explore', status: 'completed', turnId: 'T1', tools: 1 }

const PANE_VIEW = {
  component: 'Pane',
  requestId: 'session-progress',
  props: {
    title: 'Session progress',
    isFocused: true,
    bodyColumns: 100,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 40 },
    view: {},
  },
  viewport: { columns: 140, rows: 60 },
} as const

describe('history tree', () => {
  test('collapsed: one row per task, oldest first, with its plan progress', async () => {
    const rows = buildHistoryRows([T1, T2], [AGENT], new Set(), 90_000, '▶', MESSAGES.ko)
    expect(rows.map(r => [r.text, r.isOpenable, r.isOpen, r.meta])).toEqual([
      ['#1 첫 작업', true, false, '1/3 · 1분 0초'],
      ['#2 두 번째 작업', false, false, '진행 중 20초'],
    ])
    expect(buildHistoryRows([], [], new Set(), 0)).toEqual([])
  })

  test('opening a task lists its plan steps with each status, then its parallel agents', async () => {
    const rows = buildHistoryRows([T1, T2], [AGENT], new Set(['t:T1']), 90_000, '▶', MESSAGES.ko)
    expect(rows.map(r => [`${r.guide}${r.mark} ${r.text}`, r.meta])).toEqual([
      ['✔ #1 첫 작업', '1/3 · 1분 0초'],
      ['├─ ✔ 분석', '완료'],
      ['├─ ▶ 구현', '진행 중'],
      ['├─ ○ 배포', '대기'],
      ['└─ ✔ Explore: 파일 찾기', '완료'],
      ['▶ #2 두 번째 작업', '진행 중 20초'],
    ])
    expect(rows.slice(1, 5).every(r => r.depth === 1 && !r.isOpenable)).toBe(true)
  })

  test('a spinner frame replaces ▶ only on what is still running', async () => {
    const running: Turn = { ...T2, steps: [{ title: '수정', status: 'in_progress' }, { title: '확인', status: 'pending' }] }
    const live: AgentRow = { ...AGENT, id: 'a2', turnId: 'T2', status: 'running' }
    const rows = buildHistoryRows([T1, running], [AGENT, live], new Set(['t:T1', 't:T2']), 90_000, '⠙', MESSAGES.ko)
    expect(rows.map(r => `${r.guide}${r.mark} ${r.text}`)).toEqual([
      '✔ #1 첫 작업',
      '├─ ✔ 분석',
      '├─ ▶ 구현',
      '├─ ○ 배포',
      '└─ ✔ Explore: 파일 찾기',
      '⠙ #2 두 번째 작업',
      '├─ ⠙ 수정',
      '├─ ○ 확인',
      '└─ ⠙ Explore: 파일 찾기',
    ])
    expect(spinnerAt(0)).toBe('⠋')
    expect(spinnerAt(11)).toBe('⠙')
    expect(spinnerAt(-1)).toBe('⠏')
  })

  test('history rows carry no bar of their own', async () => {
    const lines = layoutHistoryLines(buildHistoryRows([T1, T2], [], new Set(), 90_000), 100)
    expect(lines.every(l => !('bar' in l))).toBe(true)
    expect(lines[0]?.meta).toBe('1/3 · 1m 0s')
  })

  test('width counts Hangul as two cells', async () => {
    expect(cellWidth('ab한글')).toBe(6)
    expect(cutToWidth('가나다라', 5)).toBe('가나…')
    expect(cutToWidth('abc', 3)).toBe('abc')
    expect(cutToWidth('abc', 0)).toBe('')
  })
})

describe('combining a chained task', () => {
  const todo = (subject: string, status: Todo['status']): Todo => ({ id: subject, subject, status })

  test('new steps go below, a re-reported step updates in place', async () => {
    const carried = [todo('분석', 'completed'), todo('구현', 'in_progress')]
    expect(combineTodos(carried, [todo('구현', 'completed'), todo('배포', 'pending')]).map(t => [t.subject, t.status])).toEqual([
      ['분석', 'completed'],
      ['구현', 'completed'],
      ['배포', 'pending'],
    ])
    expect(combineTodos([], [])).toEqual([])
  })
})

describe('reset per task', () => {
  const setup = (on: On) => {
    on('ui.render', ($, e) => {
      const { Text } = $.ui.resolve(e)
      return <Text>engine-band</Text>
    })
    on('turn.start', (_$, e) => ({ turnId: e.turnId }))
    on('turn.complete', (_$, e) => ({ text: e.answer }))
    on('prompt.submit', (_$, e) => ({ text: e.text, origin: { kind: 'composer' as const } }))
  }
  const steps = (
    $: Engine,
    id: string,
    list: { title: string; status: string }[],
  ) =>
    $.tool.call({ tool: 'mcp__session-progress__steps', tool_use_id: id, steps: list } as unknown as Parameters<
      typeof $.tool.call
    >[0])
  const finish = ($: Engine, turnId: string) =>
    $.turn.complete({ turnId, reason: 'answer', answer: '', durationMs: 1, isAborted: false })

  test('a task started after the last one ended starts from zero', async ($, on) => {
    const clock = mock.clock(on, { now: 1_000 })
    setup(on)
    await $.turn.start({ text: '작업 1', turnId: 'T1' })
    await steps($, 's1', [
      { title: '분석', status: 'completed' },
      { title: '구현', status: 'completed' },
    ])
    await finish($, 'T1')
    await clock.advance(60_000)
    await $.turn.start({ text: '작업 2', turnId: 'T2' })
    const ui = await $.ui.mount({ plugin: 'session-progress', surface: 'terminal', ...PANE_VIEW })
    expect(await ui.find({ type: 'Text', text: 'No steps reported yet.' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /2\/2 \(100%\)/ })).toBeUndefined()
    await ui.unmount()
  })

  test('a request typed while a task ran is appended to it', async ($, on) => {
    const clock = mock.clock(on, { now: 1_000 })
    setup(on)
    await $.turn.start({ text: '작업 1', turnId: 'T1' })
    await steps($, 's1', [
      { title: '분석', status: 'completed' },
      { title: '구현', status: 'in_progress' },
    ])
    await $.prompt.submit({ text: '이것도 해줘', turnId: 'T1', wait: false, origin: { kind: 'composer' } })
    await finish($, 'T1')
    await clock.advance(500)
    await $.turn.start({ text: '이것도 해줘', turnId: 'T2' })
    await steps($, 's2', [
      { title: '구현', status: 'completed' },
      { title: '추가 작업', status: 'in_progress' },
    ])
    const ui = await $.ui.mount({ plugin: 'session-progress', surface: 'terminal', ...PANE_VIEW })
    expect(await ui.find({ type: 'Text', text: /2\/3 \(67%\)/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏] 추가 작업$/ })).toBeDefined()
    await ui.unmount()
  })

  test('finishing an earlier step in the chained task marks it done in the earlier task plan too', async ($, on) => {
    const clock = mock.clock(on, { now: 1_000 })
    setup(on)
    await $.turn.start({ text: '작업 1', turnId: 'T1' })
    await steps($, 's1', [
      { title: '분석', status: 'completed' },
      { title: '구현', status: 'in_progress' },
    ])
    await $.prompt.submit({ text: '이것도', turnId: 'T1', wait: false, origin: { kind: 'composer' } })
    await finish($, 'T1')
    await clock.advance(500)
    await $.turn.start({ text: '이것도', turnId: 'T2' })
    await steps($, 's2', [
      { title: '구현', status: 'completed' },
      { title: '추가', status: 'in_progress' },
    ])
    const ui = await $.ui.mount({ plugin: 'session-progress', surface: 'terminal', ...PANE_VIEW })
    await ui.press({ key: 'h-t:T1' })
    // The first task's plan: both analysis and implementation show as completed (implementation was finished in the
    // follow-up task).
    expect((await ui.findAll({ type: 'Text', text: /^done$/ })).length).toBe(2)
    expect(await ui.find({ type: 'Text', text: /^in progress$/ })).toBeUndefined()
    await ui.unmount()
  })

  test('a mid-task request that never started its own turn does not chain a later task', async ($, on) => {
    const clock = mock.clock(on, { now: 1_000 })
    setup(on)
    await $.turn.start({ text: '작업 1', turnId: 'T1' })
    await steps($, 's1', [{ title: '분석', status: 'completed' }])
    await $.prompt.submit({ text: '접혀 들어간 요청', turnId: 'T1', wait: false, origin: { kind: 'composer' } })
    await finish($, 'T1')
    await clock.advance(120_000)
    await $.turn.start({ text: '나중 작업', turnId: 'T2' })
    const ui = await $.ui.mount({ plugin: 'session-progress', surface: 'terminal', ...PANE_VIEW })
    expect(await ui.find({ type: 'Text', text: 'No steps reported yet.' })).toBeDefined()
    await ui.unmount()
  })
})

describe('history pane', () => {
  const PANE = {
    component: 'Pane',
    requestId: 'session-progress',
    props: {
      title: 'Session progress',
      isFocused: true,
      bodyColumns: 100,
      placement: 'dock',
      scroll: { offset: 0, bodyRows: 40 },
      view: {},
    },
    viewport: { columns: 140, rows: 60 },
  } as const

  const setup = (on: On) => {
    on('turn.start', (_$, e) => ({ turnId: e.turnId }))
    on('turn.complete', (_$, e) => ({ text: e.answer }))
  }
  const task = async ($: Engine, n: number, steps: { title: string; status: string }[] = []) => {
    await $.turn.start({ text: `작업 ${n}`, turnId: `T${n}` })
    if (steps.length > 0) {
      await $.tool.call({ tool: 'mcp__session-progress__steps', tool_use_id: `s${n}`, steps } as never)
    }
    await $.turn.complete({ turnId: `T${n}`, reason: 'answer', answer: '', durationMs: 1, isAborted: false })
  }

  test('pressing a task shows its plan and each step status; pressing again hides it', async ($, on) => {
    mock.clock(on, { now: 1_000 })
    setup(on)
    await task($, 1, [
      { title: '로그인 화면 분석', status: 'completed' },
      { title: '버튼 수정', status: 'in_progress' },
    ])
    const ui = await $.ui.mount({ plugin: 'session-progress', surface: 'terminal', ...PANE })
    // The same step also shows in the todo-progress section at the very top, so on the history side we watch the
    // count go up by one and back down.
    const count = async () => (await ui.findAll({ type: 'Text', text: /버튼 수정/ })).length
    const before = await count()
    await ui.press({ key: 'h-t:T1' })
    expect(await count()).toBe(before + 1)
    expect(await ui.find({ type: 'Text', text: /^in progress$/ })).toBeDefined()
    await ui.press({ key: 'h-t:T1' })
    expect(await count()).toBe(before)
    await ui.unmount()
  })

  test('more rows than the fixed height scroll in place', async ($, on) => {
    mock.clock(on, { now: 1_000 })
    setup(on)
    for (let n = 1; n <= 15; n++) await task($, n, [{ title: `단계 ${n}`, status: 'completed' }])
    const ui = await $.ui.mount({ plugin: 'session-progress', surface: 'terminal', ...PANE })
    // The list is in ascending order, so the bottom (newest) is visible at first.
    expect(await ui.find({ type: 'Text', text: /4–15 \/ 15 lines/ })).toBeDefined()
    expect(await ui.find({ key: 'h-t:T15' })).toBeDefined()
    expect(await ui.find({ key: 'h-t:T1' })).toBeUndefined()
    await ui.press({ key: 'h-up' })
    expect(await ui.find({ type: 'Text', text: /1–12 \/ 15 lines/ })).toBeDefined()
    expect(await ui.find({ key: 'h-t:T1' })).toBeDefined()
    expect(await ui.find({ key: 'h-t:T15' })).toBeUndefined()
    await ui.press({ key: 'h-top' })
    expect(await ui.find({ key: 'h-t:T15' })).toBeDefined()
    expect(await ui.find({ key: 'h-t:T1' })).toBeUndefined()
    await ui.unmount()
  })
})

describe('one-line titles', () => {
  test('a long title is cut to one line; metas still share a column', async () => {
    const long: Turn = { ...T1, text: '아주 긴 제목이 들어간 작업 요청이라서 한 줄에 다 들어가지 않는 경우를 확인한다 정말 길게' }
    const lines = layoutHistoryLines(buildHistoryRows([long, T2], [AGENT], new Set(['t:T1']), 90_000), 60)
    expect(lines.length).toBe(6)
    expect(lines[0]?.text.endsWith('…')).toBe(true)
    const start = (l: HistoryLine) => cellWidth(l.prefix) + cellWidth(l.mark) + 1 + cellWidth(l.text)
    expect(lines.every(l => start(l) <= 60)).toBe(true)
    expect(new Set(lines.filter(l => l.meta !== '').map(l => start(l) + l.pad.length)).size).toBe(1)
  })

  test('a summarized title wins over the raw request', async () => {
    const rows = buildHistoryRows([{ ...T1, text: '긴 원문. 둘째 문장', title: '버튼 색 수정' }], [], new Set(), 90_000)
    expect(rows[0]?.text).toBe('#1 버튼 색 수정')
    const raw = buildHistoryRows([{ ...T1, text: '긴 원문. 둘째 문장' }], [], new Set(), 90_000)
    expect(raw[0]?.text).toBe('#1 긴 원문')
  })

  test('brief and cleaned titles', async () => {
    expect(briefTitle('로그인 버튼 고쳐줘. 그리고 테스트도')).toBe('로그인 버튼 고쳐줘')
    expect(briefTitle('v1.2 배포해줘')).toBe('v1.2 배포해줘')
    expect(briefTitle('')).toBe('')
    expect(cleanTitle('"로그인 버튼 색 수정".\n설명', 40)).toBe('로그인 버튼 색 수정')
    expect(cleanTitle('가'.repeat(50), 10)).toBe(`${'가'.repeat(9)}…`)
  })

  test('long prompts are joined into one line and capped', async () => {
    expect(compactText('첫 줄\n\n  둘째   줄 ', 100)).toBe('첫 줄 둘째 줄')
    expect(compactText('a'.repeat(10), 5)).toBe('aaaa…')
  })
})

describe('session start', () => {
  test('every request carries the step guide, and long requests get a haiku title', async ($, on) => {
    const clock = mock.clock(on, { now: 1_000 })
    const contexts: (readonly string[] | undefined)[] = []
    const prompts: string[] = []
    on('session.start', (_$, e) => ({ cwd: e.cwd }))
    on('command.register', () => ({ value: { command: 'progress' } }))
    on('tool.list', () => ({ value: [] }))
    on('tool.register', () => ({ value: { tool: 'mcp__session-progress__steps' } }))
    on('session.cwd', () => ({ value: '/nowhere' }))
    on('session.root', () => ({ value: '/nowhere' }))
    on('fs.exists', () => ({ value: false }))
    on('agent.list', () => ({ value: [] }))
    const opened: string[] = []
    on('ui.open', (_$, e) => {
      opened.push(e.id)
      return { value: { isPlaced: true as const } }
    })
    on('prompt.submit', (_$, e) => {
      contexts.push(e.context)
      return { text: e.text, origin: { kind: 'composer' as const } }
    })
    on('turn.start', (_$, e) => ({ turnId: e.turnId }))
    on('model.complete', (_$, e) => {
      prompts.push(e.prompt)
      return {
        value: { isAnswered: true as const, text: '"로그인 버튼 색 수정".', usage: {} as never },
      }
    })
    await $.session.start({ cwd: '/nowhere', surface: 'terminal', isInteractive: true })
    await clock.settle()
    expect(opened).toEqual(['session-progress'])
    await $.prompt.submit({ text: '로그인 버튼 색 바꿔줘. 그리고 확인도', wait: false, origin: { kind: 'composer' } })
    expect(contexts[0]?.some(c => c.includes('mcp__session-progress__steps'))).toBe(true)

    await $.turn.start({ text: '로그인 화면에서 버튼 색이 이상해. 브랜드 색으로 바꾸고 화면도 확인해줘', turnId: 'T1' })
    await $.turn.start({ text: '짧은 요청', turnId: 'T2' })
    await clock.advance(1_600)
    await clock.advance(1_600)
    expect(prompts).toEqual(['로그인 화면에서 버튼 색이 이상해. 브랜드 색으로 바꾸고 화면도 확인해줘'])
    const ui = await $.ui.mount({ plugin: 'session-progress', surface: 'terminal', ...PANE_VIEW })
    expect(await ui.find({ type: 'Text', text: /#1 로그인 버튼 색 수정\s*$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /#2 짧은 요청\s*$/ })).toBeDefined()
    await ui.unmount()
  })
})

describe('one bar, not two', () => {
  test('the band never draws a to-do bar — the plan bar lives at the top of the pane', async ($, on) => {
    mock.clock(on, { now: 1_000 })
    on('ui.render', ($$, e) => {
      const { Text } = $$.ui.resolve(e)
      return <Text>engine-band</Text>
    })
    on('turn.start', (_$, e) => ({ turnId: e.turnId }))
    await $.turn.start({ text: '작업', turnId: 'T1' })
    await $.tool.call({
      tool: 'mcp__session-progress__steps',
      tool_use_id: 's1',
      steps: [{ title: '분석', status: 'in_progress' }],
    } as never)
    const band = await $.ui.mount({ plugin: 'session-progress', surface: 'terminal', ...BAND })
    expect(await band.find({ type: 'Text', text: /^(Plan|할 일) $/ })).toBeUndefined()
    expect(await band.find({ type: 'Text', text: 'engine-band' })).toBeDefined()
    await band.unmount()
    const pane = await $.ui.mount({ plugin: 'session-progress', surface: 'terminal', ...PANE_VIEW })
    expect(await pane.find({ type: 'Text', text: /0\/1 \(0%\)/ })).toBeDefined()
    await pane.unmount()
  })
})

describe('opening on session start', () => {
  test('a headless session (-p, SDK) does not open the pane', async ($, on) => {
    const clock = mock.clock(on, { now: 1_000 })
    const opened: string[] = []
    on('session.start', (_$, e) => ({ cwd: e.cwd }))
    on('command.register', () => ({ value: { command: 'progress' } }))
    on('tool.list', () => ({ value: [] }))
    on('tool.register', () => ({ value: { tool: 'mcp__session-progress__steps' } }))
    on('session.cwd', () => ({ value: '/nowhere' }))
    on('session.root', () => ({ value: '/nowhere' }))
    on('fs.exists', () => ({ value: false }))
    on('ui.open', (_$, e) => {
      opened.push(e.id)
      return { value: { isPlaced: true as const } }
    })
    await $.session.start({ cwd: '/nowhere', surface: null, isInteractive: false })
    await clock.settle()
    expect(opened).toEqual([])
  })
})

describe('spinner', () => {
  // "Turn the spinner timer off when there is no task or the pane is closed" gives the same on-screen result, so it
  // cannot be observed here — load.test.tsx locks it by counting timer ticks.
  test('the running task spins while the pane is open, and stops once it ends', async ($, on) => {
    const clock = mock.clock(on, { now: 1_000 })
    on('session.start', (_$, e) => ({ cwd: e.cwd }))
    on('command.register', () => ({ value: { command: 'progress' } }))
    on('tool.list', () => ({ value: [] }))
    on('tool.register', () => ({ value: { tool: 'mcp__session-progress__steps' } }))
    on('session.cwd', () => ({ value: '/nowhere' }))
    on('session.root', () => ({ value: '/nowhere' }))
    on('fs.exists', () => ({ value: false }))
    on('agent.list', () => ({ value: [] }))
    on('ui.open', () => ({ value: { isPlaced: true as const } }))
    on('turn.start', (_$, e) => ({ turnId: e.turnId }))
    on('turn.complete', (_$, e) => ({ text: e.answer }))
    await $.session.start({ cwd: '/nowhere', surface: 'terminal', isInteractive: true })
    await $.turn.start({ text: '작업', turnId: 'T1' })
    const ui = await $.ui.mount({ plugin: 'session-progress', surface: 'terminal', ...PANE_VIEW })
    const frame = async () =>
      (await ui.findAll({ type: 'Text' })).map(t => t.text).find(t => /^[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏▶]$/.test(t))
    const first = await frame()
    await clock.advance(300)
    const second = await frame()
    expect(first).toMatch(/^[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]$/)
    expect(second).toMatch(/^[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]$/)
    expect(second).not.toBe(first)
    await $.turn.complete({ turnId: 'T1', reason: 'answer', answer: '', durationMs: 1, isAborted: false })
    await clock.advance(300)
    expect(await frame()).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: '✔' })).toBeDefined()
    await ui.unmount()
  })
})

describe('redraw after a reload', () => {
  // A reload drops the open pane's state subscription — a redraw must be requested at session.start (it runs again on
  // reload) and at the start and end of every task, or the history looks frozen until the next prompt (symptom
  // observed 2026-10-13).
  test('session start, a task start and a task end each ask for a redraw', async ($, on) => {
    const clock = mock.clock(on, { now: 1_000 })
    const asked: string[] = []
    on('session.start', (_$, e) => ({ cwd: e.cwd }))
    on('command.register', () => ({ value: { command: 'progress' } }))
    on('tool.list', () => ({ value: [] }))
    on('tool.register', () => ({ value: { tool: 'mcp__session-progress__steps' } }))
    on('session.cwd', () => ({ value: '/nowhere' }))
    on('session.root', () => ({ value: '/nowhere' }))
    on('fs.exists', () => ({ value: false }))
    on('agent.list', () => ({ value: [] }))
    on('ui.open', () => ({ value: { isPlaced: true as const } }))
    on('ui.invalidate', (_$, e) => {
      asked.push(e.event)
      return { value: undefined }
    })
    on('turn.start', (_$, e) => ({ turnId: e.turnId }))
    on('turn.complete', (_$, e) => ({ text: e.answer }))

    await $.session.start({ cwd: '/nowhere', surface: 'terminal', isInteractive: true })
    await clock.settle()
    expect(asked).toEqual(['ui.render'])
    await $.turn.start({ text: '작업', turnId: 'T1' })
    await clock.settle()
    expect(asked).toEqual(['ui.render', 'ui.render'])
    await $.turn.complete({ turnId: 'T1', reason: 'answer', answer: '', durationMs: 1, isAborted: false })
    await clock.settle()
    expect(asked).toEqual(['ui.render', 'ui.render', 'ui.render'])
  })
})

describe('narrow terminals', () => {
  // ui.close with origin person (a human closing the pane directly) cannot be triggered from the test kit, so
  // "once closed, it does not reopen" cannot be locked here.
  const boot = (on: On, placed: () => boolean, opened: string[]) => {
    on('session.start', (_$, e) => ({ cwd: e.cwd }))
    on('command.register', () => ({ value: { command: 'progress' } }))
    on('tool.list', () => ({ value: [] }))
    on('tool.register', () => ({ value: { tool: 'mcp__session-progress__steps' } }))
    on('session.cwd', () => ({ value: '/nowhere' }))
    on('session.root', () => ({ value: '/nowhere' }))
    on('fs.exists', () => ({ value: false }))
    on('agent.list', () => ({ value: [] }))
    on('ui.invalidate', () => ({ value: undefined }))
    on('ui.panes', () => ({
      value: [{ id: 'session-progress', title: 'Session progress', isShown: placed(), isFocused: false, isPlaced: placed() }],
    }))
    on('ui.open', (_$, e) => {
      opened.push(e.id)
      return { value: placed() ? { isPlaced: true as const } : { isPlaced: false as const, reason: 'narrow' } }
    })
    on('prompt.submit', (_$, e) => ({ text: e.text, origin: e.origin }))
  }

  test('a pane left waiting at session start is opened again by the person’s first prompt', async ($, on) => {
    const clock = mock.clock(on, { now: 1_000 })
    const opened: string[] = []
    boot(on, () => false, opened)
    await $.session.start({ cwd: '/nowhere', surface: 'terminal', isInteractive: true })
    await clock.settle()
    expect(opened).toEqual(['session-progress'])
    await $.prompt.submit({ text: '작업해줘', wait: false, origin: { kind: 'composer' } })
    await clock.settle()
    expect(opened).toEqual(['session-progress', 'session-progress'])
  })

  test('a placed pane is not reopened, and a notification is not the person asking', async ($, on) => {
    const clock = mock.clock(on, { now: 1_000 })
    const opened: string[] = []
    let placed = true
    boot(on, () => placed, opened)
    await $.session.start({ cwd: '/nowhere', surface: 'terminal', isInteractive: true })
    await clock.settle()
    await $.prompt.submit({ text: '작업해줘', wait: false, origin: { kind: 'composer' } })
    await clock.settle()
    expect(opened).toEqual(['session-progress'])
    placed = false
    await $.prompt.submit({ text: '알림', wait: false, origin: { kind: 'task-notification' } } as never)
    await clock.settle()
    expect(opened).toEqual(['session-progress'])
  })
})

describe('no hide switch', () => {
  test('the pane offers no button to hide the progress bar', async ($, on) => {
    mock.clock(on, { now: 1_000 })
    on('turn.start', (_$, e) => ({ turnId: e.turnId }))
    await $.turn.start({ text: '작업', turnId: 'T1' })
    const ui = await $.ui.mount({ plugin: 'session-progress', surface: 'terminal', ...PANE_VIEW })
    expect(await ui.find({ key: 'band' })).toBeUndefined()
    expect(await ui.find({ type: 'Button', text: /Hide|Show|숨기기|보이기/ })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: /History/ })).toBeDefined()
    await ui.unmount()
  })
})
