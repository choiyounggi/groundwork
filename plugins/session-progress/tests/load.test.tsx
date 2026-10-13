import type { On } from 'claude-code'
import { describe, expect, mock, test } from 'claude-code/testing'

// Load regression: these produce the same on-screen result and differ only in cost, so screen assertions cannot catch
// them — count state writes and reads directly.
// Timer ticks cannot be counted because mock.clock holds clock.every, so count the key each timer reads every tick
// instead: the dragon timer uses dragonMorph and the spinner timer uses spinFrame (the old implementation had both
// read isPaneOpen on every tick).
// (2026-10-13 A/B: without these guards, CPU was 10.9% while working and 2~4% idle, vs 3.9% and 0.5~0.8% for a
// session without the mod)

type Agent = { id: string; description: string; type: string; status: 'running' | 'completed' }

const boot = (on: On, opts: { placed: boolean; agents: Agent[] }) => {
  const writes: Record<string, number> = {}
  const reads: Record<string, number> = {}
  on('state.set', (_$, e, next) => {
    writes[e.key] = (writes[e.key] ?? 0) + 1
    return next(e)
  })
  on('state.get', (_$, e, next) => {
    reads[e.key] = (reads[e.key] ?? 0) + 1
    return next(e)
  })
  on('session.start', (_$, e) => ({ cwd: e.cwd }))
  on('command.register', () => ({ value: { command: 'progress' } }))
  on('tool.list', () => ({ value: [] }))
  on('tool.register', () => ({ value: { tool: 'mcp__session-progress__steps' } }))
  on('session.cwd', () => ({ value: '/nowhere' }))
  on('session.root', () => ({ value: '/nowhere' }))
  on('fs.exists', () => ({ value: false }))
  on('agent.list', () => ({ value: opts.agents }))
  on('ui.invalidate', () => ({ value: undefined }))
  on('ui.blit', () => ({ value: {} }))
  on('ui.open', () => ({
    value: opts.placed ? { isPlaced: true as const } : { isPlaced: false as const, reason: 'narrow' },
  }))
  on('turn.start', (_$, e) => ({ turnId: e.turnId }))
  on('turn.complete', (_$, e) => ({ text: e.answer }))
  const reset = () => {
    for (const k of Object.keys(writes)) delete writes[k]
    for (const k of Object.keys(reads)) delete reads[k]
  }

  return { writes, reads, reset }
}

const START = { cwd: '/nowhere', surface: 'terminal', isInteractive: true } as const
const done = (turnId: string) => ({ turnId, reason: 'answer', answer: '', durationMs: 1, isAborted: false }) as const

describe('load', () => {
  test('an unchanged subagent list is not written again on every poll', async ($, on) => {
    const clock = mock.clock(on, { now: 1_000 })
    const agent: Agent = { id: 'A1', description: '탐색', type: 'Explore', status: 'completed' }
    const probe = boot(on, { placed: true, agents: [agent] })
    await $.session.start(START)
    await clock.advance(2_100)
    expect(probe.writes.agents).toBe(1)
    probe.reset()
    await clock.advance(10_000)
    expect(probe.writes.agents).toBeUndefined()
  })

  test('a changed subagent is still written', async ($, on) => {
    const clock = mock.clock(on, { now: 1_000 })
    const agent: Agent = { id: 'A1', description: '탐색', type: 'Explore', status: 'running' }
    const probe = boot(on, { placed: true, agents: [agent] })
    await $.session.start(START)
    await clock.advance(2_100)
    probe.reset()
    agent.status = 'completed'
    await clock.advance(2_100)
    expect(probe.writes.agents).toBe(1)
  })

  test('with the pane not placed, neither the dragon nor the spinner timer runs, even while working', async ($, on) => {
    const clock = mock.clock(on, { now: 1_000 })
    const probe = boot(on, { placed: false, agents: [] })
    await $.session.start(START)
    await $.turn.start({ text: '작업', turnId: 'T1' })
    probe.reset()
    await clock.advance(3_000)
    expect(probe.reads.dragonMorph).toBeUndefined()
    expect(probe.reads.isPaneOpen).toBeUndefined()
    expect(probe.writes.spinFrame).toBeUndefined()
    // Slow polling (the 2-second agent poll) keeps running — a control showing the counter is alive.
    expect(probe.reads.turns).toBeGreaterThan(0)
  })

  test('with the pane placed, the spinner runs only while a task runs; the dragon keeps ticking', async ($, on) => {
    const clock = mock.clock(on, { now: 1_000 })
    const probe = boot(on, { placed: true, agents: [] })
    await $.session.start(START)
    probe.reset()
    await clock.advance(3_000)
    expect(probe.writes.spinFrame).toBeUndefined()
    expect(probe.reads.dragonMorph).toBeGreaterThan(0)

    await $.turn.start({ text: '작업', turnId: 'T1' })
    probe.reset()
    await clock.advance(3_000)
    expect(probe.writes.spinFrame).toBeGreaterThanOrEqual(9)
    expect(probe.writes.spinFrame).toBeLessThanOrEqual(11)

    await $.turn.complete(done('T1'))
    probe.reset()
    await clock.advance(3_000)
    expect(probe.writes.spinFrame).toBeUndefined()
  })
})
