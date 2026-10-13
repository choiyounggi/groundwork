import { describe, expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'

import {
  CANVAS_H,
  CANVAS_ROWS,
  CANVAS_W,
  MORPH_MS,
  STAGES,
  encodeCells,
  renderPixels,
  sceneCells,
  stageOf,
  stageProgress,
} from '../hooks/dragon'
import { MESSAGES } from '../hooks/i18n'

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

const SHORT_PANE = { ...PANE_VIEW, props: { ...PANE_VIEW.props, scroll: { offset: 0, bodyRows: 12 } } } as const

function luminance(rgb: number): number {
  return 0.2126 * ((rgb >> 16) & 0xff) + 0.7152 * ((rgb >> 8) & 0xff) + 0.0722 * (rgb & 0xff)
}

/** base64 cells → [codePoint, fg, bg] per cell. */
function decode(cells: string): number[][] {
  const binary = atob(cells)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
  const words = new Uint32Array(bytes.buffer)
  const out: number[][] = []
  for (let i = 0; i < words.length; i += 3) out.push([words[i] ?? 0, words[i + 1] ?? 0, words[i + 2] ?? 0])

  return out
}

describe('dragon stages', () => {
  test('context percent maps to seven stages at their thresholds', async () => {
    const cases: [number, number][] = [
      [0, 0], [9.9, 0], [10, 1], [24, 1], [25, 2], [39, 2], [40, 3], [55, 4], [69, 4], [70, 5], [84, 5], [85, 6], [100, 6],
    ]
    for (const [percent, stage] of cases) expect([percent, stageOf(percent)]).toEqual([percent, stage])
    expect(STAGES.length).toBe(7)
    expect(MESSAGES.en.dragonName).toBe('Context Dragon')
    expect(MESSAGES.ko.dragonName).toBe('컨텍스트 드래곤')
    expect(MESSAGES.en.dragonFlavor.length).toBe(7)
    expect(MESSAGES.ko.dragonFlavor.length).toBe(7)
  })

  test('progress toward the next stage, clamped, full at the last stage', async () => {
    expect(stageProgress(17.5)).toBe(50)
    expect(stageProgress(10)).toBe(0)
    expect(stageProgress(85)).toBe(100)
    expect(stageProgress(-5)).toBe(0)
  })

  test('every sprite is a rectangle of known glyphs that fits the canvas', async () => {
    for (const stage of STAGES) {
      const width = stage.sprite[0]?.length ?? 0
      expect(stage.sprite.every(row => row.length === width)).toBe(true)
      expect(stage.sprite.every(row => /^[.obdlwehtmqzcx]+$/.test(row))).toBe(true)
      expect(width).toBeLessThanOrEqual(CANVAS_W)
      // Leave room for the sprite to bob up by one cell while breathing.
      expect(stage.sprite.length).toBeLessThan(CANVAS_H)
    }
  })

  test('the body grows darker and redder with each stage after the egg', async () => {
    const bodies = STAGES.slice(1).map(s => s.palette.b)
    for (let i = 1; i < bodies.length; i++) {
      expect(luminance(bodies[i] as number)).toBeLessThan(luminance(bodies[i - 1] as number))
    }
    for (const body of bodies) {
      expect((body >> 16) & 0xff).toBeGreaterThan((body >> 8) & 0xff)
      expect((body >> 16) & 0xff).toBeGreaterThan(body & 0xff)
    }
    // The last stage is a dark red.
    expect(luminance(bodies.at(-1) as number)).toBeLessThan(40)
  })
})

describe('dragon frames', () => {
  test('cells are a full canvas of half blocks, empty cells blank', async () => {
    const cells = decode(encodeCells(new Array(CANVAS_W * CANVAS_H).fill(null)))
    expect(cells.length).toBe(CANVAS_W * CANVAS_ROWS)
    expect(cells.every(([glyph]) => glyph === 0x20)).toBe(true)
    const drawn = decode(sceneCells({ stage: 4, morph: null, now: 1_000 }))
    expect(drawn.length).toBe(CANVAS_W * CANVAS_ROWS)
    expect(drawn.some(([glyph]) => glyph === 0x2580 || glyph === 0x2584)).toBe(true)
  })

  test('a growing stage covers more of the canvas', async () => {
    const filled = (stage: number) => renderPixels({ stage, morph: null, now: 1_000 }).filter(c => c !== null).length
    for (let stage = 1; stage < STAGES.length; stage++) expect(filled(stage)).toBeGreaterThan(filled(stage - 1))
  })

  test('the eyes close in a blink, except the ultimate form which never blinks', async () => {
    const eye = (stage: number) => STAGES[stage]?.palette.e as number
    const blink = 4200 * 5 + 20
    const open = 4200 * 5 + 1_000
    expect(renderPixels({ stage: 2, morph: null, now: open }).includes(eye(2))).toBe(true)
    expect(renderPixels({ stage: 2, morph: null, now: blink }).includes(eye(2))).toBe(false)
    const ultimate = renderPixels({ stage: 6, morph: null, now: blink })
    expect(ultimate.includes(eye(6)) || ultimate.includes(STAGES[6]?.palette.h as number)).toBe(true)
  })

  test('a transformation passes through frames unlike either form and ends on the new one', async () => {
    const morph = { from: 2, to: 3, startedAt: 10_000 }
    const same = (a: (number | null)[], b: (number | null)[]) => a.every((c, i) => c === b[i])
    for (const at of [0.1, 0.5, 0.9]) {
      const now = morph.startedAt + MORPH_MS * at
      const frame = renderPixels({ stage: 2, morph, now })
      expect(same(frame, renderPixels({ stage: 2, morph: null, now }))).toBe(false)
      expect(same(frame, renderPixels({ stage: 3, morph: null, now }))).toBe(false)
    }
    const after = morph.startedAt + MORPH_MS + 1
    expect(same(renderPixels({ stage: 3, morph, now: after }), renderPixels({ stage: 3, morph: null, now: after }))).toBe(true)
  })
})

describe('dragon in the pane', () => {
  const measure = (percent: number) => ({
    context: { percent, tokens: percent * 2_000, window: 200_000 },
    rateLimits: [],
    changed: ['context' as const],
  })
  const setup = (on: On) => on('session.measure', (_$, e) => ({ changed: e.changed }))

  test('the stage the context reached is drawn beside its raster', async ($, on) => {
    mock.clock(on, { now: 1_000 })
    setup(on)
    await $.session.measure(measure(47))
    const ui = await $.ui.mount({ plugin: 'session-progress', surface: 'terminal', ...PANE_VIEW })
    expect(await ui.find({ type: 'Text', text: 'Context Dragon Lv.4' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /context 47%/ })).toBeDefined()
    expect(await ui.find({ type: 'Raster' })).toBeDefined()
    await ui.unmount()
  })

  // The test kit does not render layout as text — lock the two things that went wrong in a real terminal via the
  // tree structure.
  test('the info lines sit level with the dragon and the next-stage bar stays on one line', async ($, on) => {
    mock.clock(on, { now: 1_000 })
    setup(on)
    await $.session.measure(measure(30))
    const ui = await $.ui.mount({ plugin: 'session-progress', surface: 'terminal', ...PANE_VIEW })
    type Node = { type?: string; props?: Record<string, unknown>; children?: unknown[] }
    const all: Node[] = []
    const walk = (n: unknown) => {
      if (typeof n !== 'object' || n === null) return
      all.push(n as Node)
      for (const c of (n as Node).children ?? []) walk(c)
    }
    walk(await ui.drawn())
    const kids = (n: Node) => (n.children ?? []) as Node[]
    const text = (n: Node) => kids(n).filter(c => typeof c === 'string').join('')

    // The dragon stands on the canvas floor — align the text column beside it to the floor too (aligned to the top,
    // it floats next to empty sky).
    const side = all.find(n => kids(n).some(c => c.type === 'Raster'))
    expect(side?.props?.alignItems).toBe('flex-end')

    // The filled and empty cells form one row — a fragment was drawn as a column Box, so the empty cells dropped to
    // the next line.
    const filled = all.find(n => n.type === 'Text' && /^█+$/.test(text(n)))
    const holder = all.find(n => kids(n).includes(filled as Node))
    expect(filled).toBeDefined()
    expect(holder?.props?.flexDirection).toBe('row')
    expect(kids(holder as Node).some(c => c.type === 'Text' && /^░+$/.test(text(c)))).toBe(true)
    await ui.unmount()
  })

  test('a later reading in another stage starts a transformation, which settles on the new stage', async ($, on) => {
    const clock = mock.clock(on, { now: 1_000 })
    setup(on)
    on('session.start', (_$, e) => ({ cwd: e.cwd }))
    on('command.register', () => ({ value: { command: 'progress' } }))
    on('tool.list', () => ({ value: [] }))
    on('tool.register', () => ({ value: { tool: 'mcp__session-progress__steps' } }))
    on('session.cwd', () => ({ value: '/nowhere' }))
    on('session.root', () => ({ value: '/nowhere' }))
    on('fs.exists', () => ({ value: false }))
    on('agent.list', () => ({ value: [] }))
    on('ui.open', () => ({ value: { isPlaced: true as const } }))
    on('ui.blit', () => ({ value: {} }))
    await $.session.start({ cwd: '/nowhere', surface: 'terminal', isInteractive: true })
    await $.session.measure(measure(30))
    await $.session.measure(measure(60))
    const ui = await $.ui.mount({ plugin: 'session-progress', surface: 'terminal', ...PANE_VIEW })
    expect(await ui.find({ type: 'Text', text: '✦ evolving ✦' })).toBeDefined()
    await ui.unmount()
    // The stage stays the same until the morph finishes.
    await clock.advance(MORPH_MS / 2)
    const midway = await $.ui.mount({ plugin: 'session-progress', surface: 'terminal', ...PANE_VIEW })
    expect(await midway.find({ type: 'Text', text: 'Context Dragon Lv.5' })).toBeUndefined()
    await midway.unmount()
    await clock.advance(MORPH_MS)
    const after = await $.ui.mount({ plugin: 'session-progress', surface: 'terminal', ...PANE_VIEW })
    expect(await after.find({ type: 'Text', text: 'Context Dragon Lv.5' })).toBeDefined()
    await after.unmount()
  })

  test('without the room for the raster a one-line status is drawn instead', async ($, on) => {
    mock.clock(on, { now: 1_000 })
    setup(on)
    await $.session.measure(measure(90))
    const ui = await $.ui.mount({ plugin: 'session-progress', surface: 'terminal', ...SHORT_PANE })
    expect(await ui.find({ type: 'Raster' })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: /Context Dragon Lv\.7 · context 90%/ })).toBeDefined()
    await ui.unmount()
  })
})

describe('regrow button', () => {
  const measure = (percent: number) => ({
    context: { percent, tokens: percent * 2_000, window: 200_000 },
    rateLimits: [],
    changed: ['context' as const],
  })
  type Compact = { tokensAfter?: number; skip?: string; fails?: boolean }
  const setup = (on: On, compact: Compact) => {
    const calls: string[] = []
    const toasts: string[] = []
    on('session.measure', (_$, e) => ({ changed: e.changed }))
    on('ui.toast', (_$, e) => {
      toasts.push(e.text)

      return { value: undefined }
    })
    on('session.compact', () => {
      calls.push('compact')
      if (compact.fails === true) throw new Error('a turn is running')
      if (compact.skip !== undefined) return { skip: compact.skip }

      return { messages: [{ role: 'user' as const, text: '요약', toolUses: [] }], tokensAfter: compact.tokensAfter }
    })
    on('turn.start', (_$, e) => ({ turnId: e.turnId }))
    on('turn.complete', (_$, e) => ({ text: e.answer }))

    return { calls, toasts }
  }

  test('pressing it compacts the conversation and the dragon falls back to the level the summary left', async ($, on) => {
    const clock = mock.clock(on, { now: 1_000 })
    const { calls, toasts } = setup(on, { tokensAfter: 8_000 })
    await $.session.measure(measure(90))
    const ui = await $.ui.mount({ plugin: 'session-progress', surface: 'terminal', ...PANE_VIEW })
    expect(await ui.find({ type: 'Text', text: 'Context Dragon Lv.7' })).toBeDefined()
    await ui.press({ key: 'dragon-regrow' })
    await clock.settle()
    expect(calls).toEqual(['compact'])
    expect(toasts.some(t => t.includes('compacted'))).toBe(true)
    // 8k / 200k = 4% → the motion regressing back into an egg starts.
    expect(await ui.find({ type: 'Text', text: '✧ devolving ✧' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /context 4%/ })).toBeDefined()
    expect(await ui.find({ key: 'dragon-regrow' })).toBeDefined()
    await ui.unmount()
  })

  test('pressed while a task runs, it waits for the task to end and then compacts once', async ($, on) => {
    const clock = mock.clock(on, { now: 1_000 })
    const { calls } = setup(on, { tokensAfter: 8_000 })
    await $.session.measure(measure(60))
    await $.turn.start({ text: '작업', turnId: 'T1' })
    const ui = await $.ui.mount({ plugin: 'session-progress', surface: 'terminal', ...PANE_VIEW })
    await ui.press({ key: 'dragon-regrow' })
    await clock.settle()
    expect(calls).toEqual([])
    expect(await ui.find({ type: 'Text', text: '⏳ regrows when this task ends' })).toBeDefined()
    expect(await ui.find({ key: 'dragon-regrow' })).toBeUndefined()
    await $.turn.complete({ turnId: 'T1', reason: 'answer', answer: '', durationMs: 1, isAborted: false })
    await clock.advance(1_000)
    expect(calls).toEqual(['compact'])
    expect(await ui.find({ key: 'dragon-regrow' })).toBeDefined()
    await ui.unmount()
  })

  test('a vetoed compaction says why and leaves the dragon as it was', async ($, on) => {
    const clock = mock.clock(on, { now: 1_000 })
    const { calls, toasts } = setup(on, { skip: '요약할 대화가 없습니다' })
    await $.session.measure(measure(60))
    const ui = await $.ui.mount({ plugin: 'session-progress', surface: 'terminal', ...PANE_VIEW })
    await ui.press({ key: 'dragon-regrow' })
    await clock.settle()
    expect(calls).toEqual(['compact'])
    expect(toasts.some(t => t.includes('요약할 대화가 없습니다'))).toBe(true)
    expect(await ui.find({ type: 'Text', text: 'Context Dragon Lv.5' })).toBeDefined()
    expect(await ui.find({ key: 'dragon-regrow' })).toBeDefined()
    await ui.unmount()
  })

  test('a failed compaction with no task running points to /compact and frees the button', async ($, on) => {
    const clock = mock.clock(on, { now: 1_000 })
    const { toasts } = setup(on, { fails: true })
    await $.session.measure(measure(60))
    const ui = await $.ui.mount({ plugin: 'session-progress', surface: 'terminal', ...PANE_VIEW })
    await ui.press({ key: 'dragon-regrow' })
    await clock.settle()
    expect(toasts.some(t => t.includes('/compact'))).toBe(true)
    expect(await ui.find({ key: 'dragon-regrow' })).toBeDefined()
    await ui.unmount()
  })
})
