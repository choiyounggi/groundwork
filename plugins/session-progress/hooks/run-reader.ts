import type { Gate, Orchestration, Worker } from '../types'
import {
  gateFileFor,
  isRunActive,
  newer,
  overallPercent,
  parseGates,
  parseGraphIds,
  parseStatus,
  workerPercent,
} from './orchestration'
import type { StatusRecord } from './orchestration'

const HOUR = 3_600_000

/**
 * File access used by this module. The engine interface cannot cross the import boundary, so register.tsx wraps it
 * and passes it in.
 */
export type RunIo = {
  read: (path: string) => Promise<string>
  listFiles: (path: string) => Promise<string[]>
  exists: (path: string) => Promise<boolean>
  cwd: () => Promise<string>
  root: () => Promise<string>
}

async function readStatus(io: RunIo, path: string): Promise<StatusRecord | null> {
  try {
    return parseStatus(await io.read(path))
  } catch {
    return null
  }
}

async function readGates(io: RunIo, worktree: string, task: string): Promise<Gate[]> {
  try {
    const dir = `${worktree}/.dev-loop/gates`
    const file = gateFileFor(task, await io.listFiles(dir))

    return file === undefined ? [] : parseGates(await io.read(`${dir}/${file}`))
  } catch {
    return []
  }
}

/** Coordinator only: workers run inside `.worktrees/<wt>` (same distinction as dev-loop loop-gate.sh). */
export async function findRunRoot(io: RunIo): Promise<string | null> {
  const cwd = await io.cwd()
  if (`${cwd}/`.includes('/.worktrees/')) return null
  for (const dir of new Set([cwd, await io.root()])) {
    if (await io.exists(`${dir}/.orchestration/graph.json`)) return dir
  }

  return null
}

export async function readRun(io: RunIo, root: string, now: number): Promise<Orchestration | null> {
  const ids = parseGraphIds(await io.read(`${root}/.orchestration/graph.json`))
  if (ids.length === 0) return null

  const workers: Worker[] = []
  for (const task of ids) {
    const main = await readStatus(io, `${root}/.orchestration/status/${task}.json`)
    const local =
      main?.worktree === undefined
        ? null
        : await readStatus(io, `${main.worktree}/.orchestration/status/${task}.json`)
    const status = newer(main, local)
    const phase = status?.phase ?? 'pending'
    const gates = status?.worktree === undefined ? [] : await readGates(io, status.worktree, task)
    workers.push({
      task,
      phase,
      percent: workerPercent(phase, gates),
      gates,
      ...(status?.updatedAt === undefined ? {} : { updatedAt: status.updatedAt }),
      ...(status?.session === undefined ? {} : { session: status.session }),
      ...(status?.attempt === undefined ? {} : { attempt: status.attempt }),
      ...(status?.error === undefined ? {} : { error: status.error }),
    })
  }

  return {
    root,
    workers,
    percent: overallPercent(workers),
    isActive: isRunActive(workers, now, 12 * HOUR, 72 * HOUR),
  }
}
