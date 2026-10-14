import type { Gate, Orchestration, Worker } from '../types'
import {
  collected,
  gateFilesFor,
  isRunActive,
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
  listDirs: (path: string) => Promise<string[]>
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
    const gates: Gate[] = []
    for (const file of gateFilesFor(task, await io.listFiles(dir))) {
      gates.push(...parseGates(await io.read(`${dir}/${file}`)))
    }

    return gates
  } catch {
    return []
  }
}

async function listDirs(io: RunIo, path: string): Promise<string[]> {
  try {
    return await io.listDirs(path)
  } catch {
    return []
  }
}

/**
 * Coordinator only. A worker runs inside `<root>/.worktrees/<task>`, and its checkout may see the run through a shared
 * path or a link; it is still not the coordinator, so it shows nothing.
 */
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

  // Workers write their status into their own worktree; the coordinator collects it into the canonical copy only from
  // time to time (collect-status.sh). Read where the worker wrote: its recorded worktree (an Orca worktree lives
  // elsewhere) and every `.worktrees/*`, the root collect-status.sh scans.
  const trees = (await listDirs(io, `${root}/.worktrees`)).map(name => `${root}/.worktrees/${name}`)
  const workers: Worker[] = []
  for (const task of ids) {
    const main = await readStatus(io, `${root}/.orchestration/status/${task}.json`)
    const dirs = new Set(trees)
    // A coordinator rework rewrites the canonical worktree to the coordinator's own path; that is not the worker's.
    if (main?.worktree !== undefined && main.worktree !== root) dirs.add(main.worktree)
    let local: StatusRecord | null = null
    let localTree: string | undefined
    for (const dir of dirs) {
      const record = await readStatus(io, `${dir}/.orchestration/status/${task}.json`)
      if (record !== null && (local === null || (record.updatedAt ?? 0) > (local.updatedAt ?? 0))) {
        local = record
        localTree = dir
      }
    }
    const status = collected(main, local)
    const phase = status?.phase ?? 'pending'
    const gateTree = localTree ?? (main?.worktree !== undefined && main.worktree !== root ? main.worktree : undefined)
    const gates = gateTree === undefined ? [] : await readGates(io, gateTree, task)
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
