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
  listDirs: async dir => {
    const names = new Set(
      Object.keys(files)
        .filter(path => path.startsWith(`${dir}/`) && path.slice(dir.length + 1).includes('/'))
        .map(path => path.slice(dir.length + 1).split('/')[0] as string),
    )
    if (names.size === 0) throw new Error(`ENOENT ${dir}`)
    return [...names]
  },
  exists: async path => path in files,
  cwd: async () => cwd,
  root: async () => cwd,
})

describe('dev-loop contract', () => {
  test('the fixture holds every file the reader opens', async () => {
    expect(Object.keys(DEV_LOOP_RUN).sort()).toEqual([
      '/run/.orchestration/graph.json',
      '/run/.orchestration/status/task-1.json',
      '/run/.orchestration/status/task-2.json',
      '/run/.orchestration/status/task-3.json',
      '/run/.worktrees/task-1/.dev-loop/gates/01-api.md',
      '/run/.worktrees/task-1/.orchestration/status/task-1.json',
      '/run/.worktrees/task-2/.dev-loop/gates/task-2.md',
      '/run/.worktrees/task-2/.orchestration/status/task-2.json',
    ])
  })

  test('a run as dev-loop writes it: worker copies, coordinator rework, ledgers in the worktrees', async () => {
    expect(await findRunRoot(io(ROOT))).toBe(ROOT)
    const run = await readRun(io(ROOT), ROOT, NOW)
    // task-1: the worker's own plan_ready copy is newer than the pre-seeded pending, and it builds under plan_ready,
    // so its ledger (named after loop-implement's plan task, 01-api.md) moves its percent: (2 + 1/2) / 7.
    // task-2: the coordinator's rework is newer than the worker's impl_done; its gates still come from the worker's
    // worktree although the canonical record now names the coordinator's own path; rework itself is not
    // interpolated: 3 / 7.
    expect(run?.workers.map(w => [w.task, w.phase, w.percent])).toEqual([
      ['task-1', 'plan_ready', 36],
      ['task-2', 'rework', 43],
      ['task-3', 'done', 100],
    ])
    expect(run?.workers.map(w => w.session)).toEqual(['worker-1', 'worker-2', 'worker-3'])
    expect(run?.workers[0]?.gates.map(g => [g.id, g.title, g.isDone])).toEqual([
      ['G1', 'the endpoint answers', true],
      ['G2', 'the copy reads well', false],
    ])
    expect(run?.workers[1]?.gates.map(g => g.isDone)).toEqual([true, false])
    expect(run?.workers[1]?.attempt).toBe(2)
    expect(run?.workers[1]?.error).toBe('tests failed')
    expect(run?.workers[0]?.updatedAt).toBe(Date.parse('2026-01-01T00:00:01Z'))
    expect(run?.percent).toBe(60)
    expect(run?.isActive).toBe(true)
  })

  test('before a worker writes anything, the pre-seed shows it pending', async () => {
    const preSeedOnly = Object.fromEntries(
      Object.entries(DEV_LOOP_RUN).filter(([path]) => !path.includes('/.orchestration/status/') || !path.includes('/.worktrees/')),
    )
    const run = await readRun(io(ROOT, preSeedOnly), ROOT, NOW)
    expect(run?.workers[0]).toMatchObject({ task: 'task-1', phase: 'pending', percent: 0 })
  })

  test('a stale copy from an older run lends no gates to a worker that has not written yet', async () => {
    const files: Record<string, string> = {}
    for (const [path, text] of Object.entries(DEV_LOOP_RUN)) {
      if (!path.startsWith('/run/.worktrees/task-1/')) files[path] = text
    }
    // an older run's worktree for the same task id, finished and fully gated, from before this run's pre-seed
    files['/run/.worktrees/old-task-1/.orchestration/status/task-1.json'] =
      '{"task":"task-1","phase":"impl_done","updatedAt":"2025-12-31T00:00:00Z","worktree":"/run/.worktrees/old-task-1"}'
    files['/run/.worktrees/old-task-1/.dev-loop/gates/task-1.md'] = '- [x] G1: old\n- [x] G2: old\n'
    const run = await readRun(io(ROOT, files), ROOT, NOW)
    expect(run?.workers[0]).toMatchObject({ task: 'task-1', phase: 'pending', gates: [] })
  })

  test('the coordinator under another spelling of its path is never read as a worker', async () => {
    const files: Record<string, string> = { ...DEV_LOOP_RUN }
    // the coordinator's rework recorded its resolved path, while the session spells the root through a link
    files['/run/.orchestration/status/task-2.json'] = (DEV_LOOP_RUN['/run/.orchestration/status/task-2.json'] as string)
      .replace('"worktree": "/run"', '"worktree": "/private/run"')
    files['/private/run/.dev-loop/gates/01-unrelated.md'] = '- [x] G1: x\n- [x] G2: x\n- [x] G3: x\n'
    const linked: RunIo = { ...io(ROOT, files), realPath: async p => p.replace(/^\/private\/run/, '/run') }
    const run = await readRun(linked, ROOT, NOW)
    expect(run?.workers[1]?.gates.map(g => g.title)).toEqual(['the endpoint answers', 'the copy reads well'])
  })

  test('copies merge one after another in folder order, as collect-status.sh does', async () => {
    const files: Record<string, string> = {
      '/run/.orchestration/graph.json': '{"tasks":[{"id":"t"}]}',
      '/run/.orchestration/status/t.json': '{"task":"t","phase":"pending","updatedAt":"2026-01-01T00:00:00Z"}',
      '/run/.worktrees/a/.orchestration/status/t.json': '{"task":"t","phase":"failed","updatedAt":"2026-01-01T00:00:01Z"}',
      '/run/.worktrees/b/.orchestration/status/t.json': '{"task":"t","phase":"impl_done","updatedAt":"2026-01-01T00:00:02Z"}',
    }
    // a: failed is newer than pending and lands; b: newer still, but a landed failed is never overwritten
    const run = await readRun(io(ROOT, files), ROOT, NOW)
    expect(run?.workers[0]?.phase).toBe('failed')
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
