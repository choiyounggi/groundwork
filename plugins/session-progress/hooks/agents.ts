import type { AgentRow, AgentRowStatus, TodoStatus } from '../types'

export type AgentSnapshot = { id: string; description: string; type: string; status: string }

const LIVE: ReadonlySet<string> = new Set(['pending', 'running', 'waiting', 'idle'])
const KNOWN: ReadonlySet<string> = new Set([...LIVE, 'completed', 'failed', 'killed'])
const MAX_AGENTS = 300

export function isAgentFinished(status: AgentRowStatus): boolean {
  return !LIVE.has(status)
}

/**
 * Merges a `$.agent.list()` snapshot into state. New agents are attached to `anchorTurnId` (the turn in progress at
 * that moment), and agents that were alive but vanished from the list are marked `gone`. If nothing changed,
 * `rows` is returned as is.
 */
export function mergeAgents(
  rows: readonly AgentRow[],
  snapshot: readonly AgentSnapshot[],
  anchorTurnId: string | undefined,
): readonly AgentRow[] {
  const byId = new Map(snapshot.map(s => [s.id, s]))
  let changed = false

  const merged: AgentRow[] = rows.map(row => {
    const info = byId.get(row.id)
    if (info === undefined) {
      if (!LIVE.has(row.status)) return row
      changed = true

      return { ...row, status: 'gone' }
    }
    byId.delete(row.id)
    const status = KNOWN.has(info.status) ? (info.status as AgentRowStatus) : row.status
    const description = info.description || row.description
    if (status === row.status && description === row.description && info.type === row.type) return row
    changed = true

    return { ...row, status, description, type: info.type }
  })

  for (const info of byId.values()) {
    changed = true
    merged.push({
      id: info.id,
      description: info.description,
      type: info.type,
      status: KNOWN.has(info.status) ? (info.status as AgentRowStatus) : 'running',
      ...(anchorTurnId === undefined ? {} : { turnId: anchorTurnId }),
      tools: 0,
    })
  }

  return changed ? merged.slice(-MAX_AGENTS) : rows
}

export type Step = { title: string; status: TodoStatus }

/** Validates the steps tool input. Returns a reason string if the format is wrong. */
export function parseSteps(raw: unknown): Step[] | string {
  if (!Array.isArray(raw)) return 'steps must be an array.'
  const steps: Step[] = []
  for (const [i, item] of raw.entries()) {
    const s = typeof item === 'object' && item !== null ? (item as Record<string, unknown>) : {}
    const title = typeof s.title === 'string' ? s.title.trim() : ''
    const status = s.status
    if (title === '') return `steps[${i}].title is empty.`
    if (status !== 'pending' && status !== 'in_progress' && status !== 'completed') {
      return `steps[${i}].status must be one of pending, in_progress, completed.`
    }
    steps.push({ title, status })
  }

  return steps
}
