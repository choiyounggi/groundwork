import type { AgentRow, Turn } from '../types'
import { isAgentFinished } from './agents'
import { briefTitle, elapsed, ICON } from './format'
import { MESSAGES } from './i18n'
import type { Messages } from './i18n'

/** Expanded node id. A task is `t:<turnId>`. */
export type NodeId = string

/** Spinner frames that animate the in-progress row marker (one braille cell wide). */
export const SPINNER = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'] as const

export function spinnerAt(frame: number): string {
  return SPINNER[((frame % SPINNER.length) + SPINNER.length) % SPINNER.length] ?? '▶'
}

export type TreeRow = {
  key: NodeId
  depth: number
  /** Tree guide (`│  ├─ `) — draws indentation and sibling relationships together. */
  guide: string
  isOpenable: boolean
  isOpen: boolean
  mark: string
  markColor?: string
  text: string
  meta: string
}

type Node = Omit<TreeRow, 'depth' | 'guide' | 'isOpen'> & { children: Node[] }

/** `live` is the in-progress marker: uses the spinner frame if one is given, otherwise ▶. */
function agentNode(agent: AgentRow, live: string, m: Messages): Node {
  const isDone = isAgentFinished(agent.status)

  return {
    key: `a:${agent.id}`,
    isOpenable: false,
    mark: isDone ? (agent.status === 'completed' ? '✔' : '✖') : live,
    markColor: isDone ? (agent.status === 'completed' ? 'success' : 'warning') : 'claude',
    text: `${agent.type}: ${agent.description}`,
    meta: m.agentStatus[agent.status],
    children: [],
  }
}

/**
 * One task: expanding it shows the task's plan steps (each with its status) and the agents it delegated work to in
 * parallel.
 */
function turnNode(
  turn: Turn,
  index: number,
  agents: readonly AgentRow[],
  now: number,
  live: string,
  m: Messages,
): Node {
  const isRunning = turn.endedAt === undefined
  const took = elapsed((turn.endedAt ?? now) - turn.startedAt, m)
  const steps = turn.steps ?? []
  const done = steps.filter(s => s.status === 'completed').length
  const children: Node[] = [
    ...steps.map((s, i) => ({
      key: `t:${turn.id}/s${i}`,
      isOpenable: false,
      // Only in-progress steps of a running task spin — an in_progress left over on a finished task stays a static ▶.
      mark: isRunning && s.status === 'in_progress' ? live : ICON[s.status],
      ...(s.status === 'completed' ? { markColor: 'success' } : s.status === 'in_progress' ? { markColor: 'claude' } : {}),
      text: s.title,
      meta: m.stepStatus[s.status],
      children: [],
    })),
    ...agents.filter(a => a.turnId === turn.id && a.type !== '').map(a => agentNode(a, live, m)),
  ]
  const time = isRunning ? m.running(took) : turn.outcome === 'answer' ? took : m.interrupted(took)

  return {
    key: `t:${turn.id}`,
    isOpenable: children.length > 0,
    mark: isRunning ? live : turn.outcome === 'answer' ? '✔' : '✖',
    markColor: isRunning ? 'claude' : turn.outcome === 'answer' ? 'success' : 'warning',
    text: `#${index + 1} ${turn.title ?? briefTitle(turn.text)}`,
    meta: steps.length > 0 ? `${done}/${steps.length} · ${time}` : time,
    children,
  }
}

/**
 * Expands the task history into a tree, oldest first (ascending), one row per line. Children of collapsed nodes
 * produce no rows.
 */
export function buildHistoryRows(
  turns: readonly Turn[],
  agents: readonly AgentRow[],
  open: ReadonlySet<NodeId>,
  now: number,
  /** Spinner frame to draw on in-progress rows. If absent, a static ▶ is used. */
  live = '▶',
  m: Messages = MESSAGES.en,
): TreeRow[] {
  const rows: TreeRow[] = []
  const walk = (nodes: readonly Node[], depth: number, lasts: readonly boolean[]) => {
    nodes.forEach((node, i) => {
      const isLast = i === nodes.length - 1
      const guide =
        depth === 0 ? '' : lasts.map(l => (l ? '   ' : '│  ')).join('') + (isLast ? '└─ ' : '├─ ')
      const isOpen = node.isOpenable && open.has(node.key)
      const { children, ...row } = node
      rows.push({ ...row, depth, guide, isOpen })
      if (isOpen) walk(children, depth + 1, depth === 0 ? [] : [...lasts, isLast])
    })
  }
  const roots = turns.map((turn, i) => turnNode(turn, i, agents, now, live, m))
  walk(roots, 0, [])

  return rows
}

/** Hangul and full-width characters occupy two cells in a terminal. */
export function cellWidth(text: string): number {
  let width = 0
  for (const ch of text) width += isWide(ch) ? 2 : 1

  return width
}

export function cutToWidth(text: string, columns: number): string {
  if (columns <= 0) return ''
  if (cellWidth(text) <= columns) return text
  let out = ''
  let width = 0
  for (const ch of text) {
    const w = isWide(ch) ? 2 : 1
    if (width + w > columns - 1) break
    out += ch
    width += w
  }

  return `${out}…`
}

function isWide(ch: string): boolean {
  const c = ch.codePointAt(0) ?? 0

  return (
    (c >= 0x1100 && c <= 0x115f) ||
    (c >= 0x2e80 && c <= 0xa4cf) ||
    (c >= 0xac00 && c <= 0xd7a3) ||
    (c >= 0xf900 && c <= 0xfaff) ||
    (c >= 0xfe30 && c <= 0xfe4f) ||
    (c >= 0xff00 && c <= 0xff60) ||
    (c >= 0xffe0 && c <= 0xffe6) ||
    (c >= 0x1f300 && c <= 0x1faff)
  )
}

/** One screen line = one tree row. The title is truncated so it never wraps. */
export type HistoryLine = {
  key: NodeId
  isOpenable: boolean
  isOpen: boolean
  /** Tree guide and expand arrow. */
  prefix: string
  mark: string
  markColor?: string
  text: string
  /** Padding that fills from the end of the text to the meta column. */
  pad: string
  meta: string
}

const TITLE_EDGE = 72
const META_GAP = 2

/**
 * Lays tree rows out as screen lines. Titles are truncated to stay within the right edge (at most 72 cells) and kept
 * on one line, and the meta (step count, time, status) is aligned to the same column on every row.
 */
export function layoutHistoryLines(rows: readonly TreeRow[], columns: number): HistoryLine[] {
  const metaWidth = Math.min(40, Math.max(0, ...rows.map(r => cellWidth(r.meta))))
  const edge = Math.max(16, Math.min(TITLE_EDGE, columns - (metaWidth > 0 ? metaWidth + META_GAP : 0)))

  return rows.map(row => {
    const arrow = row.isOpenable ? (row.isOpen ? '▾ ' : '▸ ') : '  '
    const prefix = `${row.guide}${arrow}`
    const lead = cellWidth(prefix) + cellWidth(row.mark) + 1
    const text = cutToWidth(row.text, Math.max(6, edge - lead))
    const used = lead + cellWidth(text)

    return {
      key: row.key,
      isOpenable: row.isOpenable,
      isOpen: row.isOpen,
      prefix,
      mark: row.mark,
      ...(row.markColor === undefined ? {} : { markColor: row.markColor }),
      text,
      pad: row.meta === '' ? '' : ' '.repeat(Math.max(META_GAP, edge - used + META_GAP)),
      meta: row.meta,
    }
  })
}
