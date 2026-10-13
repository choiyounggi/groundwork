import { describe, expect, test } from 'claude-code/testing'

import { findRunRoot, readRun } from '../hooks/run-reader'
import type { RunIo } from '../hooks/run-reader'
import { DEV_LOOP_RUN } from './fixtures/dev-loop-run'

// The fixture is what dev-loop's own scripts wrote (scripts/dev-loop-fixture.sh). The tests in
// orchestration.test.tsx use hand-written files; these pin that the reader agrees with the real writer.
const ROOT = '/run'
const NOW = Date.parse('2026-01-01T00:01:00Z')

const io = (cwd: string, files: Readonly<Record<string, string>> = DEV_LOOP_RUN): RunIo => ({
  read: async path => {
    const text = files[path]
    if (text === undefined) throw new Error(`ENOENT ${path}`)
    return text
  },
  listFiles: async dir => {
    const names = Object.keys(files)
      .filter(path => path.startsWith(`${dir}/`) && !path.slice(dir.length + 1).includes('/'))
      .map(path => path.slice(dir.length + 1))
    if (names.length === 0) throw new Error(`ENOENT ${dir}`)
    return names
  },
  exists: async path => path in files,
  cwd: async () => cwd,
  root: async () => cwd,
})

describe('dev-loop contract', () => {
  test('the fixture holds every file the reader opens', async () => {
    expect(Object.keys(DEV_LOOP_RUN).sort()).toEqual([
      '/run/.dev-loop/gates/task-1.md',
      '/run/.orchestration/graph.json',
      '/run/.orchestration/status/task-1.json',
      '/run/.orchestration/status/task-2.json',
      '/run/.orchestration/status/task-3.json',
    ])
  })

  test('a run written by dev-loop is found from the coordinator checkout and read whole', async () => {
    expect(await findRunRoot(io(ROOT))).toBe(ROOT)
    const run = await readRun(io(ROOT), ROOT, NOW)
    expect(run?.workers.map(w => [w.task, w.phase, w.percent])).toEqual([
      ['task-1', 'implementing', 50],
      ['task-2', 'rework', 43],
      ['task-3', 'done', 100],
    ])
    expect(run?.workers.map(w => w.session)).toEqual(['worker-1', 'worker-2', 'worker-3'])
    expect(run?.workers[0]?.gates.map(g => [g.id, g.title, g.isDone])).toEqual([
      ['G1', 'the endpoint answers', true],
      ['G2', 'the copy reads well', false],
    ])
    expect(run?.workers[1]?.attempt).toBe(2)
    expect(run?.workers[1]?.error).toBe('tests failed')
    expect(run?.workers[0]?.updatedAt).toBe(Date.parse('2026-01-01T00:00:00Z'))
    expect(run?.percent).toBe(64)
    expect(run?.isActive).toBe(true)
  })

  test('a status file without its phase is skipped as unreadable, not shown as a phase', async () => {
    const broken = {
      ...DEV_LOOP_RUN,
      '/run/.orchestration/status/task-3.json': '{"task":"task-3","updatedAt":"2026-01-01T00:00:00Z"}',
    }
    const run = await readRun(io(ROOT, broken), ROOT, NOW)
    expect(run?.workers.find(w => w.task === 'task-3')?.phase).toBe('pending')
  })

  test('a checkout without a run has none', async () => {
    expect(await findRunRoot(io('/elsewhere'))).toBeNull()
    expect(await findRunRoot(io(ROOT, {}))).toBeNull()
  })
})
