import type { Todo, TodoStatus } from '../types'
import { MESSAGES } from './i18n'
import type { Messages } from './i18n'

export type Progress = { done: number; total: number; percent: number }

export function progressOf(todos: readonly Todo[]): Progress {
  const total = todos.length
  const done = todos.filter(t => t.status === 'completed').length
  const percent = total === 0 ? 0 : Math.round((done / total) * 100)

  return { done, total, percent }
}

/** Returns the filled and empty cells separately — so they can be drawn in different colors. */
export function barCells(progress: Progress, width: number): { filled: string; empty: string } {
  const cells = Math.max(1, Math.floor(width))
  const filled = progress.total === 0 ? 0 : Math.round((progress.done / progress.total) * cells)

  return { filled: '█'.repeat(filled), empty: '░'.repeat(cells - filled) }
}

export function barFromPercent(percent: number, width: number): { filled: string; empty: string } {
  const cells = Math.max(1, Math.floor(width))
  const filled = Math.round((Math.min(100, Math.max(0, percent)) / 100) * cells)

  return { filled: '█'.repeat(filled), empty: '░'.repeat(cells - filled) }
}

/** Shows only elapsed time instead of a clock time, so output does not depend on the time zone. */
export function elapsed(ms: number, m: Messages = MESSAGES.en): string {
  const seconds = Math.max(0, Math.round(ms / 1000))
  if (seconds < 60) return m.seconds(seconds)
  const minutes = Math.floor(seconds / 60)
  if (minutes < 60) return m.minutes(minutes, seconds % 60)

  return m.hours(Math.floor(minutes / 60), minutes % 60)
}

export function firstLine(text: string, max: number): string {
  const line = text.trim().split('\n').find(l => l.trim() !== '')?.trim() ?? ''

  return line.length > max ? `${line.slice(0, max - 1)}…` : line
}

export const ICON: Record<TodoStatus, string> = {
  completed: '✔',
  in_progress: '▶',
  pending: '○',
}

/**
 * TodoWrite resends the whole list, so doneAt is carried over from the previous item with the same subject.
 */
export function fromTodoWrite(
  next: readonly { content: string; status: TodoStatus; activeForm: string }[],
  previous: readonly Todo[],
  now: number,
): Todo[] {
  return next.map((item, index) => {
    const before = previous.find(p => p.subject === item.content)
    const doneAt =
      item.status === 'completed' ? (before?.status === 'completed' ? before.doneAt : now) : undefined

    return {
      id: `todo-${index}`,
      subject: item.content,
      status: item.status,
      activeForm: item.activeForm,
      ...(doneAt === undefined ? {} : { doneAt }),
    }
  })
}

/**
 * Merges the todos of a chain of consecutive tasks into one. If the current task reports a step with the same name
 * as one from an earlier task, it updates that entry's status in place instead of appending a duplicate.
 */
export function combineTodos(carried: readonly Todo[], current: readonly Todo[]): Todo[] {
  const bySubject = new Map(current.map(t => [t.subject, t]))
  const names = new Set(carried.map(t => t.subject))

  return [...carried.map(c => bySubject.get(c.subject) ?? c), ...current.filter(t => !names.has(t.subject))]
}

/** Collapses a multi-line request into one line (whitespace cleanup). Appends … if it exceeds `max`. */
export function compactText(text: string, max: number): string {
  const one = text.replace(/\s+/g, ' ').trim()

  return one.length > max ? `${one.slice(0, max - 1)}…` : one
}

/**
 * Title when there is no summary: up to the first sentence (before a period, question mark, exclamation mark or
 * line break). Truncating to fit the width is left to the renderer.
 */
export function briefTitle(text: string): string {
  const one = text.replace(/\s+/g, ' ').trim()
  const end = one.search(/[.?!。？！](\s|$)/)

  return end > 0 ? one.slice(0, end) : one
}

/**
 * Trims haiku's summary reply into a one-line title: first line only, surrounding quotes and trailing period removed,
 * length capped.
 */
export function cleanTitle(reply: string, max: number): string {
  const line = reply.trim().split('\n')[0] ?? ''
  const bare = line
    .replace(/[.。\s]+$/, '')
    .replace(/^["'“‘「『]+|["'”’」』]+$/g, '')
    .replace(/[.。\s]+$/, '')
    .trim()

  return bare.length > max ? `${bare.slice(0, max - 1)}…` : bare
}
