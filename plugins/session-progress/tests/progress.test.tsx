import { describe, expect, mock, test } from 'claude-code/testing'

import { barCells, elapsed, firstLine, fromTodoWrite, progressOf } from '../hooks/format'

const BAND = { component: 'AbovePrompt', props: {
    hasSurvey: false,
    isWorking: false,
    maxRows: 10,
    bodyColumns: 120,
    scroll: { offset: 0, bodyRows: 9 },
    view: {},
  },
} as const

const PANE_VIEW = {
  component: 'Pane',
  requestId: 'session-progress',
  props: {
    title: '세션 진행 현황',
    isFocused: true,
    bodyColumns: 100,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 40 },
    view: {},
  },
  viewport: { columns: 140, rows: 60 },
} as const

describe('format', () => {
  test('progress and bar split filled and empty cells', async () => {
    const p = progressOf([
      { id: 'a', subject: 'A', status: 'completed' },
      { id: 'b', subject: 'B', status: 'in_progress' },
      { id: 'c', subject: 'C', status: 'pending' },
      { id: 'd', subject: 'D', status: 'completed' },
    ])
    expect(p).toEqual({ done: 2, total: 4, percent: 50 })
    expect(barCells(p, 10)).toEqual({ filled: '█████', empty: '░░░░░' })
  })

  test('empty list is 0% with an all-empty bar', async () => {
    const p = progressOf([])
    expect(p).toEqual({ done: 0, total: 0, percent: 0 })
    expect(barCells(p, 4)).toEqual({ filled: '', empty: '░░░░' })
    expect(barCells(p, 0)).toEqual({ filled: '', empty: '░' })
  })

  test('elapsed and firstLine', async () => {
    expect(elapsed(42_000)).toBe('42초')
    expect(elapsed(125_000)).toBe('2분 5초')
    expect(elapsed(3_660_000)).toBe('1시간 1분')
    expect(elapsed(-5)).toBe('0초')
    expect(firstLine('\n\n  hello world  \nsecond', 100)).toBe('hello world')
    expect(firstLine('abcdefghij', 5)).toBe('abcd…')
  })

  test('TodoWrite keeps doneAt of a task already completed', async () => {
    const first = fromTodoWrite([{ content: 'A', status: 'completed', activeForm: 'Aing' }], [], 100)
    expect(first[0]?.doneAt).toBe(100)
    const second = fromTodoWrite(
      [
        { content: 'A', status: 'completed', activeForm: 'Aing' },
        { content: 'B', status: 'pending', activeForm: 'Bing' },
      ],
      first,
      200,
    )
    expect(second[0]?.doneAt).toBe(100)
    expect(second[1]?.doneAt).toBeUndefined()
  })
})

describe('hooks', () => {
  test('TodoWrite drives the plan bar at the top of the pane', async ($, on) => {
    mock.clock(on, { now: 1_000 })
    on('ui.render', ($, e) => {
      const { Text } = $.ui.resolve(e)
      return <Text>engine-band</Text>
    })
    on('tool.call', { tool: 'TodoWrite' }, () => ({ result: { oldTodos: [], newTodos: [] } }))
    await $.tool.call({
      tool: 'TodoWrite',
      tool_use_id: 'tu1',
      todos: [
        { content: '분석', status: 'completed', activeForm: '분석 중' },
        { content: '구현', status: 'in_progress', activeForm: '구현하는 중' },
        { content: '테스트', status: 'pending', activeForm: '테스트 중' },
      ],
    })
    for (const surface of ['terminal', 'desktop'] as const) {
      const ui = await $.ui.mount({ plugin: 'session-progress', surface, ...PANE_VIEW })
      expect(await ui.find({ type: 'Text', text: '1/3 (33%)' })).toBeDefined()
      expect(await ui.find({ type: 'Text', text: /구현하는 중/ })).toBeDefined()
      await ui.unmount()
    }
  })

  test('a failed TodoWrite leaves the list untouched', async ($, on) => {
    mock.clock(on, { now: 1_000 })
    on('ui.render', ($, e) => {
      const { Text } = $.ui.resolve(e)
      return <Text>engine-band</Text>
    })
    on('tool.call', { tool: 'TodoWrite' }, () => ({ deny: 'no' }))
    await $.tool.call({
      tool: 'TodoWrite',
      tool_use_id: 'tu2',
      todos: [{ content: '분석', status: 'pending', activeForm: '분석 중' }],
    })
    const ui = await $.ui.mount({ plugin: 'session-progress', surface: 'terminal', ...PANE_VIEW })
    expect(await ui.find({ type: 'Text', text: /0\/1/ })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: '아직 보고된 단계가 없습니다.' })).toBeDefined()
    await ui.unmount()
  })
})
