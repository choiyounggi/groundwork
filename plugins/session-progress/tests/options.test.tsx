import type { On } from 'claude-code'
import { describe, expect, mock, test } from 'claude-code/testing'

import { MESSAGES, pickLanguage } from '../hooks/i18n'
import { DEV_LOOP_RUN } from './fixtures/dev-loop-run'

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

const COMPOSE = {
  model: 'claude-test',
  promptModel: 'claude-test',
  surfaces: ['terminal'],
  outputStyle: null,
  traits: [],
} as const

const START = { cwd: '/nowhere', surface: 'terminal', isInteractive: true } as const

type Seen = {
  opened: string[]
  registered: string[]
  contexts: (readonly string[] | undefined)[]
  titled: string[]
  descriptions: string[]
}

/**
 * The engine beneath the plugin. `settings` and `env` answer `$.settings.read` and `$.env.get` when given; `files`
 * is a checkout rooted at `/run`.
 */
const boot = (
  on: On,
  opts: { settings?: Record<string, unknown>; env?: Record<string, string>; files?: Readonly<Record<string, string>> } = {},
): Seen => {
  const files = opts.files ?? {}
  const root = opts.files === undefined ? '/nowhere' : '/run'
  const seen: Seen = { opened: [], registered: [], contexts: [], titled: [], descriptions: [] }
  on('session.start', (_$, e) => ({ cwd: e.cwd }))
  on('command.register', (_$, e) => {
    seen.descriptions.push(e.description)
    return { value: { command: 'progress' } }
  })
  on('tool.list', () => ({ value: [] }))
  on('tool.register', (_$, e) => {
    seen.registered.push(e.name)
    return { value: { tool: 'mcp__session-progress__steps' } }
  })
  on('session.cwd', () => ({ value: root }))
  on('session.root', () => ({ value: root }))
  on('fs.exists', (_$, e) => ({ value: e.path in files }))
  on('fs.read', (_$, e) => {
    const text = files[e.path]
    if (text === undefined) throw new Error(`ENOENT ${e.path}`)
    return { value: text }
  })
  on('fs.list', (_$, e) => ({
    value: Object.keys(files)
      .filter(path => path.startsWith(`${e.path}/`))
      .map(path => ({ name: path.slice(e.path.length + 1), kind: 'file' as const, size: 0, mtimeMs: 0, isLink: false })),
  }))
  on('agent.list', () => ({ value: [] }))
  on('ui.blit', () => ({ value: {} }))
  on('ui.invalidate', () => ({ value: undefined }))
  on('ui.panes', () => ({ value: [] }))
  on('session.measure', (_$, e) => ({ changed: e.changed }))
  on('ui.open', (_$, e) => {
    seen.opened.push(e.id)
    return { value: { isPlaced: true as const } }
  })
  on('prompt.submit', (_$, e) => {
    seen.contexts.push(e.context)
    return { text: e.text, origin: { kind: 'composer' as const } }
  })
  on('turn.start', (_$, e) => ({ turnId: e.turnId }))
  on('turn.complete', (_$, e) => ({ text: e.answer }))
  on('model.complete', (_$, e) => {
    seen.titled.push(e.prompt)
    return { value: { isAnswered: true as const, text: 'Short title', usage: {} as never } }
  })
  if (opts.settings !== undefined) {
    const settings = opts.settings
    on('settings.read', () => ({ value: settings as never }))
  }
  if (opts.env !== undefined) {
    const env = opts.env
    on('env.get', (_$, e) => ({ value: env[e.name] }))
  }

  return seen
}

const LONG = 'Fix the login button colour. It should use the brand colour, and check the screen after.'

describe('language', () => {
  test('a pinned option wins; auto reads the language setting, then the locale; anything else is English', () => {
    expect(pickLanguage('ko', 'English', 'en_US.UTF-8')).toBe('ko')
    expect(pickLanguage('en', 'Korean', 'ko_KR.UTF-8')).toBe('en')
    expect(pickLanguage('auto', 'Korean', undefined)).toBe('ko')
    expect(pickLanguage('auto', '한국어', undefined)).toBe('ko')
    expect(pickLanguage('auto', 'ko-KR', undefined)).toBe('ko')
    expect(pickLanguage('auto', 'Korea', undefined)).toBe('ko')
    // A language setting that is not Korean decides on its own, even over a Korean locale.
    expect(pickLanguage('auto', 'Japanese', 'ko_KR.UTF-8')).toBe('en')
    expect(pickLanguage('auto', 'kotlin', undefined)).toBe('en')
    expect(pickLanguage('auto', undefined, 'ko_KR.UTF-8')).toBe('ko')
    expect(pickLanguage('auto', '  ', 'ko')).toBe('ko')
    expect(pickLanguage('auto', undefined, 'C')).toBe('en')
    expect(pickLanguage(undefined, undefined, undefined)).toBe('en')
    expect(pickLanguage('fr', 42, '')).toBe('en')
  })

  test('the two tables carry the same keys', () => {
    expect(Object.keys(MESSAGES.ko).sort()).toEqual(Object.keys(MESSAGES.en).sort())
    expect(Object.keys(MESSAGES.ko.phase).sort()).toEqual(Object.keys(MESSAGES.en.phase).sort())
  })

  test('with nothing to read the pane is English', async ($, on) => {
    mock.clock(on, { now: 1_000 })
    const seen = boot(on)
    await $.session.start(START)
    const ui = await $.ui.mount({ plugin: 'session-progress', surface: 'terminal', ...PANE_VIEW })
    expect(await ui.find({ type: 'Text', text: 'Plan (this task)' })).toBeDefined()
    expect(seen.descriptions[0]).toBe(MESSAGES.en.commandDescription)
    await ui.unmount()
  })

  test('auto follows a Korean language setting', async ($, on) => {
    mock.clock(on, { now: 1_000 })
    const seen = boot(on, { settings: { language: 'Korean' }, env: { LANG: 'en_US.UTF-8' } })
    await $.session.start(START)
    const ui = await $.ui.mount({ plugin: 'session-progress', surface: 'terminal', ...PANE_VIEW })
    expect(await ui.find({ type: 'Text', text: '할 일 진행률 (지금 작업)' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /컨텍스트 드래곤 Lv\.1/ })).toBeDefined()
    expect(seen.descriptions[0]).toBe(MESSAGES.ko.commandDescription)
    await ui.unmount()
  })

  test('the whole pane follows: history times and a dev-loop run are Korean too', async ($, on) => {
    const clock = mock.clock(on, { now: Date.parse('2026-01-01T00:01:00Z') })
    // A dev-loop run in the checkout, as dev-loop wrote it (see dev-loop-contract.test.tsx).
    boot(on, { settings: { language: '한국어' }, files: DEV_LOOP_RUN })
    await $.session.start(START)
    await $.turn.start({ text: '첫 작업', turnId: 'T1' })
    await clock.advance(5_000)
    await $.turn.complete({ turnId: 'T1', reason: 'answer', answer: '', durationMs: 1, isAborted: false })
    const ui = await $.ui.mount({ plugin: 'session-progress', surface: 'terminal', ...PANE_VIEW })
    expect(await ui.find({ type: 'Text', text: /5초\s*$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /오케스트레이션 · \/run/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /구현 중 · 게이트 1\/2/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /재작업 · 시도 2/ })).toBeDefined()
    await ui.unmount()
  })

  test('LC_ALL wins over LANG, as the C library reads them', async ($, on) => {
    mock.clock(on, { now: 1_000 })
    boot(on, { settings: {}, env: { LC_ALL: 'C.UTF-8', LANG: 'ko_KR.UTF-8' } })
    await $.session.start(START)
    const ui = await $.ui.mount({ plugin: 'session-progress', surface: 'terminal', ...PANE_VIEW })
    expect(await ui.find({ type: 'Text', text: 'Plan (this task)' })).toBeDefined()
    await ui.unmount()
  })

  test('auto falls back to a Korean locale', async ($, on) => {
    mock.clock(on, { now: 1_000 })
    boot(on, { settings: {}, env: { LANG: 'ko_KR.UTF-8' } })
    await $.session.start(START)
    const ui = await $.ui.mount({ plugin: 'session-progress', surface: 'terminal', ...PANE_VIEW })
    expect(await ui.find({ type: 'Text', text: '할 일 진행률 (지금 작업)' })).toBeDefined()
    await ui.unmount()
  })

  test('a pinned language ignores the setting', { options: { language: 'en' } }, async ($, on) => {
    mock.clock(on, { now: 1_000 })
    boot(on, { settings: { language: 'Korean' }, env: { LANG: 'ko_KR.UTF-8' } })
    await $.session.start(START)
    const ui = await $.ui.mount({ plugin: 'session-progress', surface: 'terminal', ...PANE_VIEW })
    expect(await ui.find({ type: 'Text', text: 'Plan (this task)' })).toBeDefined()
    await ui.unmount()
  })
})

describe('options', () => {
  test('by default the pane opens on start and the steps tool is offered', async ($, on) => {
    const clock = mock.clock(on, { now: 1_000 })
    const seen = boot(on)
    await $.session.start(START)
    await clock.settle()
    expect(seen.opened).toEqual(['session-progress'])
    expect(seen.registered).toEqual(['steps'])
  })

  test('openPaneOnStart off: neither the start nor a prompt opens it; /progress still does', { options: { openPaneOnStart: false } }, async ($, on) => {
    const clock = mock.clock(on, { now: 1_000 })
    const seen = boot(on)
    await $.session.start(START)
    await clock.settle()
    await $.prompt.submit({ text: 'hello', wait: false, origin: { kind: 'composer' } })
    await clock.settle()
    expect(seen.opened).toEqual([])
    await $.command.run({ command: 'progress', args: '' } as never)
    expect(seen.opened).toEqual(['session-progress'])
  })

  test('reportSteps off: no steps tool and no guide on the prompt', { options: { reportSteps: false } }, async ($, on) => {
    mock.clock(on, { now: 1_000 })
    const seen = boot(on)
    await $.session.start(START)
    await $.prompt.submit({ text: 'hello', wait: false, origin: { kind: 'composer' } })
    expect(seen.registered).toEqual([])
    expect(seen.contexts[0]?.some(c => c.includes('mcp__session-progress__steps')) ?? false).toBe(false)
  })

  // Two gates hold this off (no title queue, no title timer), so removing either one alone still passes; removing
  // both fails here.
  test('summarizeTitles off: a long request keeps its first sentence and no model call is made', { options: { summarizeTitles: false } }, async ($, on) => {
    const clock = mock.clock(on, { now: 1_000 })
    const seen = boot(on)
    await $.session.start(START)
    await $.turn.start({ text: LONG, turnId: 'T1' })
    await clock.advance(3_200)
    expect(seen.titled).toEqual([])
  })

  test('summarizeTitles on: the same long request is sent for a title', async ($, on) => {
    const clock = mock.clock(on, { now: 1_000 })
    const seen = boot(on)
    await $.session.start(START)
    await $.turn.start({ text: LONG, turnId: 'T1' })
    await clock.advance(3_200)
    expect(seen.titled).toEqual([LONG])
  })

  test('showDragon off: a one-line gauge, no raster, and the dragon timer never runs', { options: { showDragon: false } }, async ($, on) => {
    const clock = mock.clock(on, { now: 1_000 })
    const reads: Record<string, number> = {}
    on('state.get', (_$, e, next) => {
      reads[e.key] = (reads[e.key] ?? 0) + 1
      return next(e)
    })
    boot(on)
    await $.session.start(START)
    await $.session.measure({ context: { percent: 47, tokens: 94_000, window: 200_000 }, rateLimits: [], changed: ['context' as const] })
    const ui = await $.ui.mount({ plugin: 'session-progress', surface: 'terminal', ...PANE_VIEW })
    expect(await ui.find({ type: 'Raster' })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: /^context 47%/ })).toBeDefined()
    expect(await ui.find({ key: 'dragon-regrow' })).toBeUndefined()
    await ui.unmount()
    for (const k of Object.keys(reads)) delete reads[k]
    await clock.advance(3_000)
    expect(reads.dragonMorph).toBeUndefined()
  })
})

describe('step guide', () => {
  test('rides on the prompt until the system prompt carries it, then only there', async ($, on) => {
    mock.clock(on, { now: 1_000 })
    const seen = boot(on)
    on('prompt.compose', () => ({ sections: [{ id: 'intro', text: 'engine', scope: 'shared' as const }] }))
    await $.session.start(START)
    await $.prompt.submit({ text: 'first', wait: false, origin: { kind: 'composer' } })
    expect(seen.contexts[0]?.some(c => c.includes('mcp__session-progress__steps'))).toBe(true)

    const composed = await $.prompt.compose({ ...COMPOSE, tools: ['Bash', 'mcp__session-progress__steps'] })
    expect(composed.sections.map(s => s.id)).toEqual(['intro', 'session-progress:steps'])
    expect(composed.sections[1]?.text).toContain('mcp__session-progress__steps')
    expect(composed.sections[1]?.scope).toBe('session')

    await $.prompt.submit({ text: 'second', wait: false, origin: { kind: 'composer' } })
    expect(seen.contexts[1]?.some(c => c.includes('mcp__session-progress__steps')) ?? false).toBe(false)
  })

  test('a teammate prompt gets no guide; a /context render shows it but leaves the prompt fallback on', async ($, on) => {
    mock.clock(on, { now: 1_000 })
    const seen = boot(on)
    on('prompt.compose', () => ({ sections: [{ id: 'intro', text: 'engine', scope: 'shared' as const }] }))
    await $.session.start(START)
    const tools = ['Bash', 'mcp__session-progress__steps']
    const teammate = await $.prompt.compose({ ...COMPOSE, tools, traits: ['teammate'] })
    expect(teammate.sections.map(s => s.id)).toEqual(['intro'])
    const analysis = await $.prompt.compose({ ...COMPOSE, tools, traits: ['analysis'] })
    expect(analysis.sections.map(s => s.id)).toEqual(['intro', 'session-progress:steps'])
    await $.prompt.submit({ text: 'after /context', wait: false, origin: { kind: 'composer' } })
    expect(seen.contexts[0]?.some(c => c.includes('mcp__session-progress__steps'))).toBe(true)
  })

  test('a request that does not offer the tool gets no guide section', async ($, on) => {
    mock.clock(on, { now: 1_000 })
    boot(on)
    on('prompt.compose', () => ({ sections: [{ id: 'intro', text: 'engine', scope: 'shared' as const }] }))
    await $.session.start(START)
    const composed = await $.prompt.compose({ ...COMPOSE, tools: ['Bash'] })
    expect(composed.sections.map(s => s.id)).toEqual(['intro'])
  })
})
