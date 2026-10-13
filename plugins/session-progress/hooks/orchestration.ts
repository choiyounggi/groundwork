import type { Gate, Worker } from '../types'

/**
 * Scores the phases of dev-loop status-update.sh in progress order (0~7).
 * rework means going back to the implementation stage, so it scores the same as implementing.
 * failed is finished but not complete, so it is not scored and is shown separately.
 */
export const PHASE_SCORE: Record<string, number> = {
  pending: 0,
  planning: 1,
  plan_ready: 2,
  implementing: 3,
  rework: 3,
  impl_done: 4,
  approved: 5,
  merged: 6,
  done: 7,
}
const MAX_SCORE = 7

const TERMINAL = new Set(['approved', 'merged', 'done', 'failed'])

export function isTerminal(phase: string): boolean {
  return TERMINAL.has(phase)
}

/** During the implementation stage, interpolates toward the next stage by the fraction of gates passed. */
export function workerPercent(phase: string, gates: readonly Gate[]): number {
  const score = PHASE_SCORE[phase]
  if (score === undefined) return 0
  const isBuilding = phase === 'implementing' || phase === 'rework'
  const within =
    isBuilding && gates.length > 0 ? gates.filter(g => g.isDone).length / gates.length : 0

  return Math.round(((score + within) / MAX_SCORE) * 100)
}

export function overallPercent(workers: readonly Worker[]): number {
  if (workers.length === 0) return 0

  return Math.round(workers.reduce((sum, w) => sum + w.percent, 0) / workers.length)
}

const GATE_LINE = /^\s*-\s*\[( |x|X)\]\s*(G\d+)\s*:\s*(.*)$/

export function parseGates(markdown: string): Gate[] {
  const gates: Gate[] = []
  for (const line of markdown.split('\n')) {
    const match = GATE_LINE.exec(line)
    if (match) gates.push({ id: match[2] ?? '', title: (match[3] ?? '').trim(), isDone: match[1] !== ' ' })
  }

  return gates
}

/** A gate ledger file name is a loop-implement task id, so it is either `<task>.md` or `<task>-<slug>.md`. */
export function gateFileFor(task: string, names: readonly string[]): string | undefined {
  if (names.includes(`${task}.md`)) return `${task}.md`

  return [...names].sort().find(n => n.startsWith(`${task}-`) && n.endsWith('.md'))
}

export type StatusRecord = {
  task: string
  phase: string
  updatedAt?: number
  worktree?: string
  session?: string
  attempt?: number
  error?: string
}

/** One status/<task>.json. Null if it is corrupt or lacks task or phase. */
export function parseStatus(text: string): StatusRecord | null {
  let raw: unknown
  try {
    raw = JSON.parse(text)
  } catch {
    return null
  }
  if (typeof raw !== 'object' || raw === null) return null
  const r = raw as Record<string, unknown>
  if (typeof r.task !== 'string' || typeof r.phase !== 'string') return null
  const updatedAt = typeof r.updatedAt === 'string' ? Date.parse(r.updatedAt) : NaN
  const attempt = Number(r.attempt)

  return {
    task: r.task,
    phase: r.phase,
    ...(Number.isFinite(updatedAt) ? { updatedAt } : {}),
    ...(typeof r.worktree === 'string' ? { worktree: r.worktree } : {}),
    ...(typeof r.session === 'string' ? { session: r.session } : {}),
    ...(Number.isInteger(attempt) && attempt > 1 ? { attempt } : {}),
    ...(typeof r.error === 'string' && r.error !== '' ? { error: r.error } : {}),
  }
}

/**
 * Picks whichever of the main copy and the worker worktree copy has the newer updatedAt (same rule as
 * collect-status.sh).
 */
export function newer(a: StatusRecord | null, b: StatusRecord | null): StatusRecord | null {
  if (a === null) return b
  if (b === null) return a

  return (b.updatedAt ?? 0) > (a.updatedAt ?? 0) ? b : a
}

export function parseGraphIds(text: string): string[] {
  try {
    const raw = JSON.parse(text) as { tasks?: unknown }
    if (!Array.isArray(raw.tasks)) return []

    return raw.tasks
      .map(t => (typeof t === 'object' && t !== null ? (t as { id?: unknown }).id : undefined))
      .filter((id): id is string => typeof id === 'string')
  } catch {
    return []
  }
}

/**
 * A run updated within the last `recentMs` is treated as in progress. A run with unfinished workers is tolerated up to
 * `staleMs` — a run stalled longer than that is considered abandoned and is not put on the banner (it is still
 * visible in the pane).
 */
export function isRunActive(
  workers: readonly Worker[],
  now: number,
  recentMs: number,
  staleMs: number,
): boolean {
  const age = now - Math.max(0, ...workers.map(w => w.updatedAt ?? 0))
  if (age < recentMs) return true

  return workers.some(w => !isTerminal(w.phase)) && age < staleMs
}
