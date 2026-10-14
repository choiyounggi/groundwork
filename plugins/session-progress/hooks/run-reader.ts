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
  /** The path with every link resolved; absent where the host cannot say (paths are then compared as written). */
  realPath?: (path: string) => Promise<string>
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

async function listFilesSafe(io: RunIo, path: string): Promise<string[]> {
  try {
    return await io.listFiles(path)
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

async function realPath(io: RunIo, path: string): Promise<string> {
  try {
    return io.realPath === undefined ? path : await io.realPath(path)
  } catch {
    return path
  }
}

/**
 * Coordinator only. A worker runs inside `<root>/.worktrees/<name>`, and its checkout may see the run through a shared
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
  // time to time (collect-status.sh). Read the copies the way that collector does: every `<root>/.worktrees/*`, in its
  // glob order, each copy merged in turn by its rule. Each worktree's status directory is listed once per poll.
  const trees: { dir: string; tasks: ReadonlySet<string> }[] = []
  for (const name of [...(await listDirs(io, `${root}/.worktrees`))].sort()) {
    const dir = `${root}/.worktrees/${name}`
    const files = await listFilesSafe(io, `${dir}/.orchestration/status`)
    trees.push({ dir, tasks: new Set(files.filter(f => f.endsWith('.json')).map(f => f.slice(0, -'.json'.length))) })
  }
  const rootReal = await realPath(io, root)
  const workers: Worker[] = []
  for (const task of ids) {
    const main = await readStatus(io, `${root}/.orchestration/status/${task}.json`)
    // status-update.sh records a resolved path, so a coordinator write (rework, done, a reset) names the coordinator's
    // own checkout, however the session spells it. That is never a worker's worktree.
    const named =
      main?.worktree !== undefined && (await realPath(io, main.worktree)) !== rootReal ? main.worktree : undefined
    let status = main
    let fromTree: string | undefined
    let newestTree: string | undefined
    let newestAt = -1
    for (const tree of trees) {
      if (!tree.tasks.has(task)) continue
      const copy = await readStatus(io, `${tree.dir}/.orchestration/status/${task}.json`)
      if (copy === null) continue
      if ((copy.updatedAt ?? 0) > newestAt) {
        newestAt = copy.updatedAt ?? 0
        newestTree = tree.dir
      }
      const next = collected(status, copy)
      if (next !== status) fromTree = tree.dir
      status = next
    }
    const phase = status?.phase ?? 'pending'
    // Gates come from the worktree the shown record belongs to: the copy that won, else the worktree the canonical
    // record names. Only when the coordinator itself wrote last does the newest worker copy point the way.
    const gateTree = fromTree ?? named ?? newestTree
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
