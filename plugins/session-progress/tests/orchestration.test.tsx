import { describe, expect, mock, test } from 'claude-code/testing'

import { mergeAgents, parseSteps } from '../hooks/agents'
import {
  gateFilesFor,
  isRunActive,
  collected,
  parseGates,
  parseGraphIds,
  parseStatus,
  workerPercent,
} from '../hooks/orchestration'
import { findRunRoot, readRun } from '../hooks/run-reader'
import type { RunIo } from '../hooks/run-reader'
import type { AgentRow, Gate, Worker } from '../types'

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

const LEDGER = [
  '# gates',
  '- [x] G1: DoD 1 — round trip',
  '  CHECK: x',
  '- [ ] G2: DoD 2 — errors',
  '- [X] G3: hygiene',
  '- [ ] not a gate',
].join('\n')

const gates = (done: number, total: number): Gate[] =>
  Array.from({ length: total }, (_, i) => ({ id: `G${i + 1}`, title: '', isDone: i < done }))

describe('orchestration parsing', () => {
  test('phase percent interpolates gates only while building', async () => {
    expect(workerPercent('pending', [])).toBe(0)
    expect(workerPercent('plan_ready', [])).toBe(29)
    // a real run builds under plan_ready, so its gates move it too
    expect(workerPercent('plan_ready', gates(2, 4))).toBe(36)
    expect(workerPercent('implementing', gates(2, 4))).toBe(50)
    // rework is not interpolated: the last round's ledgers are already met
    expect(workerPercent('rework', gates(4, 4))).toBe(43)
    expect(workerPercent('impl_done', gates(1, 4))).toBe(57)
    expect(workerPercent('done', [])).toBe(100)
    expect(workerPercent('failed', [])).toBe(0)
    expect(workerPercent('whatever', [])).toBe(0)
  })

  test('gate ledger lines and file choice', async () => {
    expect(parseGates(LEDGER)).toEqual([
      { id: 'G1', title: 'DoD 1 — round trip', isDone: true },
      { id: 'G2', title: 'DoD 2 — errors', isDone: false },
      { id: 'G3', title: 'hygiene', isDone: true },
    ])
    expect(parseGates('')).toEqual([])
    expect(gateFilesFor('t2', ['t2-secrets.md', 't2.md'])).toEqual(['t2.md'])
    expect(gateFilesFor('t2', ['t2-secrets.md', 't20.md', 't2-api.md'])).toEqual(['t2-api.md', 't2-secrets.md'])
    // A worker worktree holds one task, so ledgers named after loop-implement's own plan tasks are all its own.
    expect(gateFilesFor('t2', ['02-ui.md', '01-api.md', 'notes.txt'])).toEqual(['01-api.md', '02-ui.md'])
    expect(gateFilesFor('t2', [])).toEqual([])
  })

  test('status records merge as collect-status.sh collects them; broken files are null', async () => {
    const at = (iso: string) => `"updatedAt":"2026-08-12T${iso}Z"`
    const a = parseStatus(`{"task":"t1","phase":"plan_ready",${at('04:00:00')},"attempt":null}`)
    const b = parseStatus(`{"task":"t1","phase":"impl_done",${at('05:00:00')},"attempt":"2"}`)
    expect(a).toEqual({ task: 't1', phase: 'plan_ready', updatedAt: Date.parse('2026-08-12T04:00:00Z') })
    expect(b?.attempt).toBe(2)
    // a strictly newer worker copy wins, and the canonical attempt survives it
    const reworked = parseStatus(`{"task":"t1","phase":"rework",${at('04:00:00')},"attempt":3}`)
    const workerCopy = parseStatus(`{"task":"t1","phase":"impl_done",${at('06:00:00')},"attempt":0}`)
    expect(collected(reworked, workerCopy)).toMatchObject({ phase: 'impl_done', attempt: 3 })
    // an equal or older worker copy loses
    expect(collected(b, a)?.phase).toBe('impl_done')
    expect(collected(a, parseStatus(`{"task":"t1","phase":"impl_done",${at('04:00:00')}}`))?.phase).toBe('plan_ready')
    // a canonical done or failed is never overwritten
    const done = parseStatus(`{"task":"t1","phase":"done",${at('01:00:00')}}`)
    expect(collected(done, workerCopy)?.phase).toBe('done')
    expect(collected(null, a)).toBe(a)
    expect(collected(a, null)).toBe(a)
    expect(parseStatus('{ not json')).toBeNull()
    expect(parseStatus('{"phase":"done"}')).toBeNull()
    expect(parseGraphIds('{"tasks":[{"id":"t1"},{"id":"t2"},{"x":1}]}')).toEqual(['t1', 't2'])
    expect(parseGraphIds('[]')).toEqual([])
  })

  test('a run is active while recent, or unfinished but not abandoned', async () => {
    const hour = 3_600_000
    const w = (phase: string, updatedAt: number): Worker => ({ task: 't', phase, percent: 0, updatedAt, gates: [] })
    const now = 100 * hour
    expect(isRunActive([w('done', now - hour)], now, 12 * hour, 72 * hour)).toBe(true)
    expect(isRunActive([w('done', now - 13 * hour)], now, 12 * hour, 72 * hour)).toBe(false)
    expect(isRunActive([w('implementing', now - 13 * hour)], now, 12 * hour, 72 * hour)).toBe(true)
    expect(isRunActive([w('implementing', now - 80 * hour)], now, 12 * hour, 72 * hour)).toBe(false)
  })
})

describe('agents and steps', () => {
  const row: AgentRow = { id: 'a1', description: 'x', type: 'Explore', status: 'running', turnId: 'T1', tools: 3 }

  test('merge adds, updates and retires agents', async () => {
    const added = mergeAgents([], [{ id: 'a1', description: 'x', type: 'Explore', status: 'running' }], 'T1')
    expect(added).toEqual([{ ...row, tools: 0 }])
    const same = [row]
    expect(mergeAgents(same, [{ id: 'a1', description: 'x', type: 'Explore', status: 'running' }], 'T2')).toBe(same)
    expect(mergeAgents(same, [{ id: 'a1', description: 'x', type: 'Explore', status: 'completed' }], 'T2')).toEqual([
      { ...row, status: 'completed' },
    ])
    expect(mergeAgents(same, [], 'T2')).toEqual([{ ...row, status: 'gone' }])
    const done = [{ ...row, status: 'completed' as const }]
    expect(mergeAgents(done, [], 'T2')).toBe(done)
  })

  test('steps input is validated', async () => {
    expect(parseSteps([{ title: ' 분석 ', status: 'completed' }])).toEqual([{ title: '분석', status: 'completed' }])
    expect(parseSteps([])).toEqual([])
    expect(parseSteps('x')).toBe('steps must be an array.')
    expect(parseSteps([{ title: '', status: 'pending' }])).toContain('title')
    expect(parseSteps([{ title: 'a', status: 'done' }])).toContain('status')
  })
})

describe('reading a dev-loop run', () => {
  const ROOT = '/repo'
  const WT = '/repo/.worktrees/wt-t2'
  const files: Record<string, string> = {
    [`${ROOT}/.orchestration/graph.json`]: '{"tasks":[{"id":"t1"},{"id":"t2"},{"id":"t3"}]}',
    [`${ROOT}/.orchestration/status/t1.json`]: '{"task":"t1","phase":"done","updatedAt":"2026-10-13T01:00:00Z"}',
    [`${ROOT}/.orchestration/status/t2.json`]: `{"task":"t2","phase":"planning","updatedAt":"2026-10-13T01:00:00Z","worktree":"${WT}","session":"lo-2-x"}`,
    [`${WT}/.orchestration/status/t2.json`]: `{"task":"t2","phase":"implementing","updatedAt":"2026-10-13T02:00:00Z","worktree":"${WT}","session":"lo-2-x"}`,
    [`${WT}/.dev-loop/gates/t2-feature.md`]: LEDGER,
  }

  const io = (cwd: string): RunIo => ({
    read: async path => {
      const text = files[path]
      if (text === undefined) throw new Error(`ENOENT ${path}`)
      return text
    },
    listFiles: async path => {
      if (path === `${WT}/.orchestration/status`) return ['t2.json']
      if (path !== `${WT}/.dev-loop/gates`) throw new Error(`ENOENT ${path}`)
      return ['t2-feature.md']
    },
    listDirs: async path => {
      if (path !== `${ROOT}/.worktrees`) throw new Error(`ENOENT ${path}`)
      return ['wt-t2']
    },
    exists: async path => path in files,
    cwd: async () => cwd,
    root: async () => cwd,
  })

  test('coordinator reads every worker, newest status and its gates', async () => {
    expect(await findRunRoot(io(ROOT))).toBe(ROOT)
    const run = await readRun(io(ROOT), ROOT, Date.parse('2026-10-13T03:00:00Z'))
    expect(run?.workers.map(w => [w.task, w.phase, w.percent])).toEqual([
      ['t1', 'done', 100],
      ['t2', 'implementing', 52],
      ['t3', 'pending', 0],
    ])
    expect(run?.workers[1]?.gates.map(g => g.isDone)).toEqual([true, false, true])
    expect(run?.workers[1]?.session).toBe('lo-2-x')
    expect(run?.percent).toBe(51)
    expect(run?.isActive).toBe(true)
  })

  test('a worker session is not a coordinator; a repo without a run has none', async () => {
    // Even when graph.json is visible from the worker worktree (shared path or symlink), it is not treated as a
    // coordinator.
    expect(await findRunRoot({ ...io(WT), exists: async () => true })).toBeNull()
    expect(await findRunRoot(io('/elsewhere'))).toBeNull()
  })
})

describe('plan bar', () => {
  test('before any steps the top of the pane says so, and the band draws no to-do row', async ($, on) => {
    mock.clock(on, { now: 1_000 })
    on('ui.render', ($$, e) => {
      const { Text } = $$.ui.resolve(e)
      return <Text>engine-band</Text>
    })
    on('turn.start', (_$, e) => ({ turnId: e.turnId }))
    await $.turn.start({ text: '리팩터링 해줘', turnId: 'T1' })
    const pane = await $.ui.mount({ plugin: 'session-progress', surface: 'terminal', ...PANE_VIEW })
    expect(await pane.find({ type: 'Text', text: 'No steps reported yet.' })).toBeDefined()
    await pane.unmount()
    const band = await $.ui.mount({ plugin: 'session-progress', surface: 'terminal', ...BAND })
    expect(await band.find({ type: 'Text', text: 'engine-band' })).toBeDefined()
    expect(await band.find({ type: 'Text', text: /No steps|단계 없음/ })).toBeUndefined()
    await band.unmount()
  })

  test('the steps tool fills the bar; a bad call is refused and changes nothing', async ($, on) => {
    mock.clock(on, { now: 1_000 })
    on('ui.render', ($$, e) => {
      const { Text } = $$.ui.resolve(e)
      return <Text>engine-band</Text>
    })
    const callSteps = (input: Record<string, unknown>) =>
      $.tool.call({ tool: 'mcp__session-progress__steps', ...input } as unknown as Parameters<typeof $.tool.call>[0])
    const bad = await callSteps({ tool_use_id: 's0', steps: 'nope' })
    expect(bad.deny).toBe('steps must be an array.')
    const ok = await callSteps({
      tool_use_id: 's1',
      steps: [
        { title: '분석', status: 'completed' },
        { title: '구현', status: 'in_progress' },
      ],
    })
    expect(ok.result).toBe('Recorded in session progress: 1/2')
    for (const surface of ['terminal', 'desktop'] as const) {
      const ui = await $.ui.mount({ plugin: 'session-progress', surface, ...PANE_VIEW })
      expect(await ui.find({ type: 'Text', text: /1\/2 \(50%\)/ })).toBeDefined()
      expect(await ui.find({ type: 'Text', text: /▶ 구현/ })).toBeDefined()
      expect(await ui.find({ type: 'Text', text: /^█+$/ })).toBeDefined()
      await ui.unmount()
    }
  })
})
