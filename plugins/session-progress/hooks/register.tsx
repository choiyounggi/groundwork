import { atom, read, update } from 'claude-code'
import type { EngineInterface, PluginOptions, Register, Timer } from 'claude-code'

import type { AgentRow, ContextUsage, Todo, TodoStatus, Turn } from '../types'
import { isAgentFinished, mergeAgents, parseSteps } from './agents'
import {
  barFromPercent,
  combineTodos,
  briefTitle,
  cleanTitle,
  compactText,
  elapsed,
  fromTodoWrite,
  ICON,
  progressOf,
} from './format'
import { CANVAS_ROWS, CANVAS_W, MORPH_MS, STAGES, TICK_MS, sceneCells, shortTokens, stageOf, stageProgress } from './dragon'
import { MESSAGES, pickLanguage } from './i18n'
import type { Lang, Messages } from './i18n'
import { buildHistoryRows, cellWidth, cutToWidth, layoutHistoryLines, spinnerAt } from './tree'
import { findRunRoot, readRun } from './run-reader'
import type { RunIo } from './run-reader'

const PANE = 'session-progress'
const MAX_TURNS = 200
const STEPS_TOOL = 'mcp__session-progress__steps'
/**
 * Only a turn that starts within this window after the previous task ended
 * counts as a "request entered while it was running".
 */
const APPEND_WINDOW_MS = 10_000
/** Fixed height (rows) of the task history list. */
const LIST_ROWS = 12
/** Cap on stored task title length — keeps a long pasted body from taking over the whole list. */
const MAX_TITLE_CHARS = 400

const todos = atom({ plugin: 'session-progress', key: 'todos' } as const, [])
const turns = atom({ plugin: 'session-progress', key: 'turns' } as const, [])
const agents = atom({ plugin: 'session-progress', key: 'agents' } as const, [])
const orchestration = atom({ plugin: 'session-progress', key: 'orchestration' } as const, null)
const expanded = atom({ plugin: 'session-progress', key: 'expanded' } as const, [])
const carried = atom({ plugin: 'session-progress', key: 'carried' } as const, [])
const chainStart = atom({ plugin: 'session-progress', key: 'chainStart' } as const, null)
const appendRequestedAt = atom({ plugin: 'session-progress', key: 'appendRequestedAt' } as const, null)
const openNodes = atom({ plugin: 'session-progress', key: 'openNodes' } as const, [])
const historyOffset = atom({ plugin: 'session-progress', key: 'historyOffset' } as const, 0)
const isPaneOpen = atom({ plugin: 'session-progress', key: 'isPaneOpen' } as const, false)
const pendingTitles = atom({ plugin: 'session-progress', key: 'pendingTitles' } as const, [])
const spinFrame = atom({ plugin: 'session-progress', key: 'spinFrame' } as const, 0)
const isPaneDismissed = atom({ plugin: 'session-progress', key: 'isPaneDismissed' } as const, false)
const contextUsage = atom({ plugin: 'session-progress', key: 'contextUsage' } as const, null)
const dragonStage = atom({ plugin: 'session-progress', key: 'dragonStage' } as const, null)
const dragonMorph = atom({ plugin: 'session-progress', key: 'dragonMorph' } as const, null)
const dragonCompact = atom({ plugin: 'session-progress', key: 'dragonCompact' } as const, 'idle')
const DRAGON_KEY = 'dragon'
const DRAGON_ICON = ['🥚', '🐣', '🦎', '🐉', '🐉', '🐲', '👁']

/**
 * Guide for reporting steps. It goes into the system prompt (prompt.compose); some setups (an organization policy
 * plugin, for one) skip user-tier compose hooks, so until the system prompt is seen to carry it the guide rides on
 * each prompt's context instead — the model reads it, the person never sees it.
 */
const STEPS_GUIDE = [
  `[Session progress] If you will use tools for this request, first report your plan with ${STEPS_TOOL} as 2-7 short`,
  'steps in the user’s language, the first one in_progress. Send the whole list again whenever a step starts or',
  'finishes, and report every finished step as completed before your final answer. Skip it for a request you answer',
  'without tools. Subagents do not call it.',
].join(' ')
/** Set when a prompt.compose hook of this module added the guide; until then prompt.submit carries it. */
let isGuideInSystemPrompt = false

/** The plugin's userConfig fields (plugin.json), defaults filled in by the engine. */
type Config = {
  language: string
  openPaneOnStart: boolean
  reportSteps: boolean
  summarizeTitles: boolean
  showDragon: boolean
}

function readConfig(options: PluginOptions): Config {
  const flag = (key: string) => options[key] !== false

  return {
    language: typeof options.language === 'string' ? options.language : 'auto',
    openPaneOnStart: flag('openPaneOnStart'),
    reportSteps: flag('reportSteps'),
    summarizeTitles: flag('summarizeTitles'),
    showDragon: flag('showDragon'),
  }
}

let config: Config = readConfig({})
/** Everything the person reads, in their language. session.start picks it; English until then. */
let m: Messages = MESSAGES.en

async function detectLanguage($: EngineInterface): Promise<Lang> {
  if (config.language === 'en' || config.language === 'ko') return config.language
  let fromSettings: unknown
  let fromEnv: string | undefined
  try {
    fromSettings = ((await $.settings.read()) as { language?: unknown }).language
  } catch {
    // No settings to read (a test, an SDK host): fall through to the locale.
  }
  try {
    fromEnv = (await $.env.get('LC_ALL')) || (await $.env.get('LANG'))
  } catch {
    // Same.
  }

  return pickLanguage(config.language, fromSettings, fromEnv)
}

/**
 * Whether this session receives steps through the mod's steps tool (when no TodoWrite/Task tools exist).
 * Set by session.start.
 */
let isReportingSteps = false
/** Lets only one title summary run at a time. */
let isSummarizing = false
const TITLE_MAX_CHARS = 40
const TITLE_SYSTEM =
  'Shorten the user’s request into a title for a task list, in the language of the request: one noun phrase of at most 40 characters (15-25 in Korean, Japanese or Chinese) on one line. Output the title only — no quotes, no period, no explanation.'

const STATUS_COLOR: Record<TodoStatus, string | undefined> = {
  completed: 'success',
  in_progress: 'claude',
  pending: undefined,
}

function isTodoStatus(value: unknown): value is TodoStatus {
  return value === 'pending' || value === 'in_progress' || value === 'completed'
}

function shortPath(path: string): string {
  return path.replace(/^\/(?:Users|home)\/[^/]+/, '~')
}

function runIo($: EngineInterface): RunIo {
  return {
    read: path => $.fs.read(path),
    listFiles: async path => (await $.fs.list(path)).filter(f => f.kind === 'file').map(f => f.name),
    listDirs: async path => (await $.fs.list(path)).filter(f => f.kind === 'dir').map(f => f.name),
    exists: path => $.fs.exists(path),
    cwd: () => $.session.cwd(),
    root: () => $.session.root(),
  }
}

async function refreshOrchestration($: EngineInterface): Promise<void> {
  try {
    const io = runIo($)
    const root = await findRunRoot(io)
    const run = root === null ? null : await readRun(io, root, await $.clock.now())
    if (JSON.stringify(await read($, orchestration)) !== JSON.stringify(run)) {
      await update($, orchestration, () => run)
    }
  } catch {
    // The state file may be mid-write; read it again next cycle.
  }
}

async function refreshAgents($: EngineInterface): Promise<void> {
  try {
    const snapshot = await $.agent.list()
    const history = await read($, turns)
    const anchor = history.findLast(t => t.endedAt === undefined)?.id ?? history.at(-1)?.id
    // Reading the same value twice returns different copies, so the reference comparison always mismatches — then
    // even with no change it rewrites every 2s and the pane/banner redraw (2026-10-13 probe: 5 writes in 10s idle).
    const rows = await read($, agents)
    if (mergeAgents(rows, snapshot, anchor) === rows) return
    await update($, agents, rows => [...mergeAgents(rows, snapshot, anchor)])
  } catch {
    // Read again next cycle.
  }
}

/**
 * Position of the task history list as last drawn — used only to decide whether a wheel event is over the list.
 * It is derived from the draw result, so it is a module variable rather than state
 * (after a reload the next draw refills it).
 */
let historyView = { top: 0, height: 0, total: 0, paneOffset: 0 }

/**
 * Turn ids of the current task chain: from the chain's first turn to the last.
 * Just the last turn if the first is unknown.
 */
function chainTurnIds(history: readonly Turn[], start: string | null): Set<string> {
  const index = start === null ? -1 : history.findIndex(t => t.id === start)

  return new Set((index < 0 ? history.slice(-1) : history.slice(index)).map(t => t.id))
}

/**
 * Stamps the plan steps onto the task in progress — they show when the task is expanded in the history tree.
 * In a chained task group, also updates the status of same-named steps in earlier tasks
 * (steps finished in a later one).
 */
async function snapshotSteps($: EngineInterface, list: readonly Todo[]): Promise<void> {
  const steps = list.map(t => ({ title: t.subject, status: t.status }))
  const latest = new Map(steps.map(s => [s.title, s.status]))
  const start = await read($, chainStart)
  await update($, turns, all => {
    const index = all.findLastIndex(t => t.endedAt === undefined)
    if (index < 0) return all
    const found = start === null ? -1 : all.findIndex(t => t.id === start)
    const from = found < 0 ? index : found

    return all.map((t, i) => {
      if (i === index) return { ...t, steps }
      if (i < from || i > index || t.steps === undefined) return t

      return { ...t, steps: t.steps.map(s => ({ ...s, status: latest.get(s.title) ?? s.status })) }
    })
  })
}

/**
 * One spinner frame redraws the whole pane, so this was raised from 150ms —
 * CPU while working was ~3x a session without the mod (2026-10-13 A/B).
 */
const SPIN_MS = 300

async function advanceSpinner($: EngineInterface): Promise<void> {
  try {
    await update($, spinFrame, f => (f + 1) % 1000)
  } catch {
    // Runs again next cycle.
  }
}

/**
 * Whether a main turn is in progress. Set by turn.start/turn.complete;
 * after a reload session.start restores it from history.
 */
let isWorking = false
let spinTimer: Timer | undefined
let dragonTimer: Timer | undefined

/**
 * Fast timers run only when needed: the dragon while the pane is open,
 * the spinner only while a task is running on top of that.
 * Each timer tick is one engine dispatch, so leaving them on always would call the engine
 * a dozen times a second even when idle.
 */
async function syncFastTimers($: EngineInterface): Promise<void> {
  const isOpen = await read($, isPaneOpen)
  const shouldTick = isOpen && config.showDragon
  if (shouldTick && dragonTimer === undefined) dragonTimer = $.clock.every(TICK_MS, () => void tickDragon($))
  if (!shouldTick && dragonTimer !== undefined) {
    dragonTimer.cancel()
    dragonTimer = undefined
  }
  const shouldSpin = isOpen && isWorking
  if (shouldSpin && spinTimer === undefined) spinTimer = $.clock.every(SPIN_MS, () => void advanceSpinner($))
  if (!shouldSpin && spinTimer !== undefined) {
    spinTimer.cancel()
    spinTimer = undefined
  }
}

/** If the first sentence is the whole text and it is short, there is nothing to summarize. */
function needsSummary(text: string): boolean {
  return briefTitle(text) !== text || cellWidth(text) > TITLE_MAX_CHARS
}

/**
 * Summarizes the first task in the queue with haiku.
 * On failure it is only removed from the queue and the first-sentence title stays.
 */
async function summarizeNextTitle($: EngineInterface): Promise<void> {
  if (isSummarizing) return
  isSummarizing = true
  try {
    const id = (await read($, pendingTitles))[0]
    if (id === undefined) return
    const turn = (await read($, turns)).find(t => t.id === id)
    const reply =
      turn === undefined
        ? undefined
        : await $.model.complete({
            model: 'haiku',
            system: TITLE_SYSTEM,
            prompt: turn.text,
            maxTokens: 60,
            effort: 'low',
            timeoutMs: 8000,
          })
    const title = reply?.isAnswered ? cleanTitle(reply.text, TITLE_MAX_CHARS) : ''
    if (title !== '') await update($, turns, all => all.map(t => (t.id === id ? { ...t, title } : t)))
    await update($, pendingTitles, ids => ids.filter(x => x !== id))
  } catch {
    // Retry next cycle.
  } finally {
    isSummarizing = false
  }
}

/** Whether the dragon Raster is currently drawn in the pane — the timer blits the next frame only while it is. */
let isDragonMounted = false
let lastDragonCells = ''

/**
 * Records the new usage and starts a transformation if the stage changed
 * (the first time it just stands at that stage, no motion).
 */
async function applyContext($: EngineInterface, context: { percent?: number; tokens?: number; window: number }) {
  if (context.percent === undefined) return
  const usage: ContextUsage = { percent: context.percent, tokens: context.tokens ?? 0, window: context.window }
  await update($, contextUsage, () => usage)
  const target = stageOf(usage.percent)
  const shown = await read($, dragonStage)
  if (shown === null) {
    await update($, dragonStage, () => target)

    return
  }
  if (target === shown || (await read($, dragonMorph)) !== null) return
  const now = await $.clock.now()
  await update($, dragonMorph, () => ({ from: shown, to: target, startedAt: now }))
}

/**
 * Draws the dragon's next frame. If a transformation finished it advances the stage,
 * and continues transforming if usage changed meanwhile.
 */
async function tickDragon($: EngineInterface): Promise<void> {
  try {
    const now = await $.clock.now()
    const morph = await read($, dragonMorph)
    if (morph !== null && now - morph.startedAt >= MORPH_MS) {
      await update($, dragonStage, () => morph.to)
      const usage = await read($, contextUsage)
      const target = usage === null ? morph.to : stageOf(usage.percent)
      await update($, dragonMorph, () => (target === morph.to ? null : { from: morph.to, to: target, startedAt: now }))

      return
    }
    if (!isDragonMounted) return
    const cells = sceneCells({ stage: (await read($, dragonStage)) ?? 0, morph, now })
    if (cells === lastDragonCells) return
    const result = await $.ui.blit({ requestId: PANE, key: DRAGON_KEY, cells })
    if (result.deny === undefined) lastDragonCells = cells
    else isDragonMounted = false
  } catch {
    // Runs again next frame.
  }
}

/**
 * "Regrow": compacts the conversation to free context and lets the dragon grow again from a low stage.
 * Compaction is rejected while a turn is running (engine spec), so if a task is running
 * it is queued and run when that turn ends.
 */
async function regrowDragon($: EngineInterface): Promise<void> {
  if ((await read($, dragonCompact)) !== 'idle') return
  if ((await read($, turns)).some(t => t.endedAt === undefined)) {
    await update($, dragonCompact, () => 'queued')
    $.ui.toast(m.toastQueued)

    return
  }
  // Compaction takes tens of seconds — hand it to a timer so it is not tied to the pressed event's handling time.
  $.clock.after(0, () => void runCompact($))
}

async function runCompact($: EngineInterface): Promise<void> {
  await update($, dragonCompact, () => 'running')
  try {
    const result = await $.session.compact()
    if (result.skip !== undefined) {
      $.ui.toast(m.toastSkipped(result.skip))
    } else {
      // Right after compaction no usage arrives until the next response —
      // regress the dragon at once from the compaction result's token count.
      const usage = await read($, contextUsage)
      if (result.tokensAfter !== undefined && usage !== null && usage.window > 0) {
        await applyContext($, {
          percent: Math.round((result.tokensAfter / usage.window) * 100),
          tokens: result.tokensAfter,
          window: usage.window,
        })
      }
      $.ui.toast(m.toastCompacted)
    }
    await update($, dragonCompact, () => 'idle')
  } catch {
    // If the next turn started meanwhile and compaction was rejected, retry when that turn ends.
    const isWorking = (await read($, turns)).some(t => t.endedAt === undefined)
    await update($, dragonCompact, () => (isWorking ? 'queued' : 'idle'))
    if (!isWorking) $.ui.toast(m.toastFailed)
  }
}

export const register: Register = (on, options) => {
  config = readConfig(options)

  on('session.start', async ($, e, next) => {
    m = MESSAGES[await detectLanguage($)]
    await $.command.register({ name: 'progress', description: m.commandDescription })
    // Open a tool for the model to report steps only in sessions without TodoWrite/Task tools.
    const names = (await $.tool.list()).map(t => t.name)
    if (config.reportSteps && !names.includes('TodoWrite') && !names.includes('TaskCreate')) {
      await $.tool.register({
        name: 'steps',
        description:
          'Report your plan for the current request as 2-7 short steps with their status; it drives the progress bar the user watches. Call it before starting any work that uses tools, then again with the whole list whenever a step starts or finishes, and mark every finished step completed before the final answer.',
        inputSchema: {
          type: 'object',
          properties: {
            steps: {
              type: 'array',
              items: {
                type: 'object',
                properties: {
                  title: { type: 'string', description: 'Short step title in the user’s language' },
                  status: { type: 'string', enum: ['pending', 'in_progress', 'completed'] },
                },
                required: ['title', 'status'],
              },
            },
          },
          required: ['steps'],
        },
        isDeferred: false,
      })
      isReportingSteps = true
    }
    void refreshOrchestration($)
    $.clock.every(5000, () => void refreshOrchestration($))
    $.clock.every(2000, () => void refreshAgents($))
    if (config.summarizeTitles) $.clock.every(1500, () => void summarizeNextTitle($))
    isWorking = (await read($, turns)).some(t => t.endedAt === undefined)
    await syncFastTimers($)
    try {
      await applyContext($, (await $.session.usage()).context)
    } catch {
      // If usage cannot be read, the first measurement (session.measure) fills it in.
    }
    // A reload (file edit, worker swap) loses an open pane's state subscription along with the old module —
    // left alone, the history looks frozen until the engine redraws on the next prompt (2026-10-13 measurement).
    // The new module redraws once to restore the subscription.
    $.ui.invalidate('ui.render')
    // In an interactive session, open the list pane right away. Since this opens without human input,
    // the engine does not draw below 144 columns (110 once opened before) and waits —
    // a narrow terminal reopens it on the first prompt (prompt.submit).
    // Do not await the result so session start is not blocked while waiting
    // (once placed, the ui.open hook sets isPaneOpen).
    if (config.openPaneOnStart && e.isInteractive && e.surface !== null && !(await read($, isPaneDismissed))) {
      void $.ui.open({ id: PANE, title: m.paneTitle })
    }

    return next(e)
  })

  on('command.run', { command: 'progress' }, async $ => {
    await update($, isPaneDismissed, () => false)
    void refreshOrchestration($)
    await $.ui.open({ id: PANE, title: m.paneTitle })

    return { text: m.commandOpened }
  })

  // The step guide goes into the system prompt of every request that offers the steps tool. A teammate's prompt
  // gets none (its steps are not recorded), and an analysis render (/context) sends nothing, so it adds the
  // section without counting as the guide having reached a real request.
  on('prompt.compose', async ($, e, next) => {
    const composed = await next(e)
    if (!isReportingSteps || !e.tools.includes(STEPS_TOOL) || e.traits.includes('teammate')) return composed
    if (!e.traits.includes('analysis')) isGuideInSystemPrompt = true

    return { sections: [...composed.sections, { id: 'session-progress:steps', text: STEPS_GUIDE, scope: 'session' }] }
  })

  // Re-measure the dragon's stage whenever context moves.
  on('session.measure', async ($, e, next) => {
    if (e.changed.includes('context')) await applyContext($, e.context)

    return next(e)
  })

  // /clear empties the conversation and the todo list, so progress is cleared with them.
  on('session.end', async ($, e, next) => {
    if (e.reason === 'clear') {
      await update($, todos, () => [])
      await update($, carried, () => [])
      await update($, chainStart, () => null)
      await update($, turns, () => [])
      await update($, agents, () => [])
      isWorking = false
      await syncFastTimers($)
    }

    return next(e)
  })

  // A request entered while a task is running is chained onto that task —
  // the engine starts it as a new turn right after the previous one ends.
  on('prompt.submit', async ($, e, next) => {
    if (e.turnId !== undefined) {
      const now = await $.clock.now()
      await update($, appendRequestedAt, () => now)
    }

    // A pane opened in response to a prompt the person sent is placed regardless of width — this opens the pane
    // that was waiting because the terminal was too narrow at session start.
    // If the person closed it, leave it closed until /progress reopens it.
    // The prompt and the guide (context) must go through even if the pane fails to open, so swallow the failure.
    try {
      if (config.openPaneOnStart && e.origin.kind === 'composer' && !(await read($, isPaneDismissed))) {
        const ours = (await $.ui.panes()).find(pane => pane.id === PANE)
        if (ours?.isPlaced !== true) void $.ui.open({ id: PANE, title: m.paneTitle })
      }
    } catch {
      // Sessions with no screen to draw on (-p, SDK), etc.
    }

    return isReportingSteps && !isGuideInSystemPrompt
      ? next({ ...e, context: [...(e.context ?? []), STEPS_GUIDE] })
      : next(e)
  })

  on('turn.start', async ($, e, next) => {
    const now = await $.clock.now()
    const previous = (await read($, turns)).at(-1)
    const requestedAt = await read($, appendRequestedAt)
    const isAppending =
      requestedAt !== null &&
      previous !== undefined &&
      requestedAt >= previous.startedAt &&
      (previous.endedAt === undefined || now - previous.endedAt < APPEND_WINDOW_MS)
    await update($, appendRequestedAt, () => null)

    if (isAppending) {
      const finished = await read($, todos)
      await update($, carried, list => combineTodos(list, finished))
    } else {
      await update($, carried, () => [])
      await update($, chainStart, () => e.turnId)
    }
    await update($, todos, () => [])

    const turn: Turn = {
      id: e.turnId,
      text: compactText(e.text, MAX_TITLE_CHARS) || m.emptyRequest,
      startedAt: now,
      tools: 0,
    }
    await update($, turns, list => [...list, turn].slice(-MAX_TURNS))
    if (config.summarizeTitles && needsSummary(turn.text)) await update($, pendingTitles, ids => [...ids, turn.id].slice(-20))
    isWorking = true
    await syncFastTimers($)
    // Redraw once more so the new task row shows immediately even if the subscription is broken (per turn, so cheap).
    $.ui.invalidate('ui.render')

    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    if (e.agentId === undefined) {
      const now = await $.clock.now()
      await update($, turns, list =>
        list.map(t => (t.id === e.turnId ? { ...t, endedAt: now, outcome: e.reason } : t)),
      )
      isWorking = (await read($, turns)).some(t => t.endedAt === undefined)
      await syncFastTimers($)
      $.ui.invalidate('ui.render')
    }
    const done = await next(e)
    // A "Regrow" pressed during a task runs after the main turn ends.
    if (e.agentId === undefined && (await read($, dragonCompact)) === 'queued') {
      $.clock.after(300, () => void runCompact($))
    }

    return done
  })

  on('tool.call', async ($, e, next) => {
    const agentId = e.agentId

    if (String(e.tool) === STEPS_TOOL) {
      if (agentId !== undefined) return { result: 'Subagent steps are not recorded in session progress.' }
      const steps = parseSteps((e as Record<string, unknown>).steps)
      if (typeof steps === 'string') return { deny: steps }
      const now = await $.clock.now()
      const items = steps.map(s => ({ content: s.title, status: s.status, activeForm: s.title }))
      const saved = await update($, todos, previous => fromTodoWrite(items, previous, now))
      await snapshotSteps($, saved)
      const { done, total } = progressOf(saved)

      return { result: `Recorded in session progress: ${done}/${total}` }
    }

    if (agentId === undefined) {
      await update($, turns, list => {
        const index = list.findLastIndex(t => t.endedAt === undefined)
        if (index < 0) return list

        return list.map((t, i) =>
          i === index ? { ...t, tools: t.tools + 1 } : t,
        )
      })
    } else {
      const history = await read($, turns)
      const anchor = history.findLast(t => t.endedAt === undefined)?.id
      await update($, agents, rows =>
        rows.some(r => r.id === agentId)
          ? rows.map(r => (r.id === agentId ? { ...r, tools: r.tools + 1 } : r))
          : [
              ...rows,
              {
                id: agentId,
                description: '',
                type: '',
                status: 'running',
                ...(anchor === undefined ? {} : { turnId: anchor }),
                tools: 1,
              } satisfies AgentRow,
            ],
      )
    }

    const ran = await next(e)
    const isOk = ran.deny === undefined && ran.isError !== true
    // Only the main loop's todo list counts as progress.
    if (!isOk || agentId !== undefined) return ran

    if (e.tool === 'TodoWrite') {
      const now = await $.clock.now()
      await snapshotSteps($, await update($, todos, previous => fromTodoWrite(e.todos, previous, now)))
    } else if (e.tool === 'TaskCreate') {
      const id = (ran.result as { task?: { id?: unknown } } | undefined)?.task?.id
      if (typeof id === 'string') {
        const todo: Todo = {
          id,
          subject: e.subject,
          status: 'pending',
          ...(e.activeForm === undefined ? {} : { activeForm: e.activeForm }),
        }
        await snapshotSteps($, await update($, todos, list => [...list.filter(t => t.id !== id), todo]))
      }
    } else if (e.tool === 'TaskUpdate') {
      const now = await $.clock.now()
      const { taskId, status, subject, activeForm } = e
      const saved = await update($, todos, list => {
        if (status === 'deleted') return list.filter(t => t.id !== taskId)

        return list.map(t => {
          if (t.id !== taskId) return t
          const nextStatus = isTodoStatus(status) ? status : t.status
          const doneAt = nextStatus === 'completed' ? (t.doneAt ?? now) : undefined
          const { doneAt: _drop, ...rest } = t

          return {
            ...rest,
            status: nextStatus,
            ...(subject === undefined ? {} : { subject }),
            ...(activeForm === undefined ? {} : { activeForm }),
            ...(doneAt === undefined ? {} : { doneAt }),
          }
        })
      })
      await snapshotSteps($, saved)
    }

    return ran
  }).catch(($, e, next) => next(e))

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey) return next(e)
    const history = await read($, turns)
    const agentRows = await read($, agents)
    const run = await read($, orchestration)
    const now = await $.clock.now()

    // Todo progress is drawn only at the top of the list pane (the banner does not repeat the same bar).
    // The banner keeps only the agents of the current task chain (including chained requests),
    // plus orchestration while the pane is closed.
    const chain = chainTurnIds(history, await read($, chainStart))
    const chainAgents = agentRows.filter(a => a.type !== '' && a.turnId !== undefined && chain.has(a.turnId))
    const showRun = run !== null && run.isActive && !(await read($, isPaneOpen))
    if (!showRun && chainAgents.length === 0) return next(e)

    const { Box, Text } = $.ui.resolve(e)
    const barWidth = Math.min(24, Math.max(8, Math.floor(e.props.bodyColumns / 5)))
    const bar = (percent: number, width: number, color = 'success') => {
      const { filled, empty } = barFromPercent(percent, width)

      // Returning a fragment stacks the two cells vertically inside a row Box
      // (the empty cells drop below the filled ones) — wrap them in a row.
      return (
        <Box flexDirection="row">
          <Text color={color}>{filled}</Text>
          <Text dimColor>{empty}</Text>
        </Box>
      )
    }

    const rows = []
    if (chainAgents.length > 0) {
      const done = chainAgents.filter(a => isAgentFinished(a.status)).length
      const live = chainAgents.find(a => !isAgentFinished(a.status))
      rows.push(
        <Box flexDirection="row">
          <Text bold>{m.agentsLabel}</Text>
          {bar(Math.round((done / chainAgents.length) * 100), barWidth)}
          <Text wrap="truncate-end">
            {' '}
            {m.agentsDone(done, chainAgents.length)}
            {live ? ` · ▶ ${live.type}: ${live.description}` : ''}
          </Text>
        </Box>,
      )
    }

    if (showRun) {
      const failed = run.workers.filter(w => w.phase === 'failed').length
      const doneCount = run.workers.filter(w => w.phase === 'done' || w.phase === 'merged' || w.phase === 'approved').length
      rows.push(
        <Box flexDirection="row">
          <Text bold>{m.runLabel}</Text>
          {bar(run.percent, barWidth)}
          <Text wrap="truncate-end">
            {' '}
            {m.runSummary(run.percent, run.workers.length)} (✔{doneCount}
            {failed > 0 ? ` ✖${failed}` : ''})
          </Text>
        </Box>,
      )
      const room = Math.max(1, e.props.maxRows - rows.length - 1)
      const shown = run.workers.length > room + 1 ? run.workers.slice(0, room) : run.workers
      const nameWidth = Math.max(...run.workers.map(w => w.task.length))
      for (const w of shown) {
        rows.push(
          <Box flexDirection="row">
            <Text>  {w.task.padEnd(nameWidth)} </Text>
            {bar(w.percent, Math.max(6, barWidth - 6), w.phase === 'failed' ? 'error' : 'success')}
            <Text wrap="truncate-end">
              {' '}
              {String(w.percent).padStart(3)}% {m.phase[w.phase] ?? w.phase}
              {w.gates.length > 0 ? ` · ${m.gates(w.gates.filter(g => g.isDone).length, w.gates.length)}` : ''}
              {w.updatedAt === undefined ? '' : ` · ${m.ago(elapsed(now - w.updatedAt, m))}`}
            </Text>
          </Box>,
        )
      }
      if (shown.length < run.workers.length) {
        rows.push(<Text dimColor>  {m.moreWorkers(run.workers.length - shown.length)}</Text>)
      }
    }

    return <Box flexDirection="column">{rows}</Box>
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Button, Text } = $.ui.resolve(e)
    const list = combineTodos(await read($, carried), await read($, todos))
    const history = await read($, turns)
    const agentRows = await read($, agents)
    const run = await read($, orchestration)
    const openWorkers = await read($, expanded)
    const open = new Set(await read($, openNodes))
    const now = await $.clock.now()
    // Spin only while a task is in progress
    // (reading the frame is itself the subscription asking for a redraw on the next frame).
    const isLive = history.some(t => t.endedAt === undefined)
    const live = isLive ? spinnerAt(await read($, spinFrame)) : '▶'
    const columns = e.props.bodyColumns
    const barWidth = Math.min(30, Math.max(8, columns - 40))
    const bar = (percent: number, width: number, color = 'success') => {
      const { filled, empty } = barFromPercent(percent, width)

      // Returning a fragment stacks the two cells vertically inside a row Box
      // (the empty cells drop below the filled ones) — wrap them in a row.
      return (
        <Box flexDirection="row">
          <Text color={color}>{filled}</Text>
          <Text dimColor>{empty}</Text>
        </Box>
      )
    }

    // One element = one row. Count which row the task history list starts at to decide the wheel scroll position.
    const out = []
    const progress = progressOf(list)
    out.push(<Text bold>{m.planHeader}</Text>)
    if (list.length === 0) {
      out.push(<Text dimColor>{m.noSteps}</Text>)
    } else {
      out.push(
        <Box flexDirection="row">
          {bar(progress.percent, barWidth)}
          <Text>
            {' '}
            {progress.done}/{progress.total} ({progress.percent}%)
          </Text>
        </Box>,
      )
      for (const todo of list) {
        out.push(
          <Text
            color={STATUS_COLOR[todo.status]}
            dimColor={todo.status === 'pending'}
            bold={todo.status === 'in_progress'}
            wrap="truncate-end"
          >
            {todo.status === 'in_progress' ? live : ICON[todo.status]}{' '}
            {todo.status === 'in_progress' ? (todo.activeForm ?? todo.subject) : todo.subject}
          </Text>,
        )
      }
    }

    if (run !== null) {
      out.push(<Text> </Text>)
      out.push(
        <Text bold wrap="truncate-end">
          {m.runHeader(shortPath(run.root))}
          {run.isActive ? '' : m.runIdle}
        </Text>,
      )
      out.push(
        <Box flexDirection="row">
          {bar(run.percent, barWidth)}
          <Text> {m.runOverall(run.percent, run.workers.length)}</Text>
        </Box>,
      )
      for (const w of run.workers) {
        const isOpen = openWorkers.includes(w.task)
        const passed = w.gates.filter(g => g.isDone).length
        const cells = barFromPercent(w.percent, Math.max(6, barWidth - 10))
        const meta = cutToWidth(
          `${m.phase[w.phase] ?? w.phase}${w.gates.length > 0 ? ` · ${m.gates(passed, w.gates.length)}` : ''}${
            w.attempt === undefined ? '' : ` · ${m.attempt(w.attempt)}`
          }${w.updatedAt === undefined ? '' : ` · ${m.ago(elapsed(now - w.updatedAt, m))}`}`,
          Math.max(4, columns - cellWidth(w.task) - cells.filled.length - cells.empty.length - 12),
        )
        out.push(
          <Button
            key={`w-${w.task}`}
            plain
            onPress={() =>
              update($, expanded, xs => (xs.includes(w.task) ? xs.filter(x => x !== w.task) : [...xs, w.task]))
            }
          >
            {isOpen ? '▾' : '▸'} {w.task}{' '}
            <Text color={w.phase === 'failed' ? 'error' : 'success'}>{cells.filled}</Text>
            <Text dimColor>{cells.empty}</Text> {w.percent}% <Text dimColor>{meta}</Text>
          </Button>,
        )
        if (!isOpen) continue
        if (w.session !== undefined) out.push(<Text dimColor>    {m.session(w.session)}</Text>)
        if (w.error !== undefined) {
          out.push(
            <Text color="error" wrap="truncate-end">
              {'    '}
              {m.error(w.error)}
            </Text>,
          )
        }
        if (w.gates.length === 0) out.push(<Text dimColor>    {m.noGates}</Text>)
        for (const g of w.gates) {
          out.push(
            <Text color={g.isDone ? 'success' : undefined} dimColor={!g.isDone} wrap="truncate-end">
              {'    '}
              {g.isDone ? '✔' : '○'} {g.id} {g.title}
            </Text>,
          )
        }
      }
    }

    // Task history: expand the tree (newest task on top) into rows and show it through a fixed-height window.
    // A long title wraps at the right edge so it is fully visible.
    // The fixed-height window and scrolling count in screen lines.
    const lines = layoutHistoryLines(buildHistoryRows(history, agentRows, open, now, live, m), columns)
    const height = Math.max(4, Math.min(LIST_ROWS, (e.viewport?.rows ?? 40) - out.length - 8))
    const maxOffset = Math.max(0, lines.length - height)
    // The list is ascending, so by default it sticks to the bottom (newest).
    // historyOffset is the number of lines scrolled up from the bottom.
    const fromEnd = Math.min(await read($, historyOffset), maxOffset)
    const offset = maxOffset - fromEnd
    out.push(<Text> </Text>)
    out.push(
      <Text bold>
        {m.historyHeader(history.length)}
        <Text dimColor>{m.historyHint}</Text>
      </Text>,
    )
    historyView = { top: out.length, height, total: lines.length, paneOffset: e.props.scroll.offset }

    const toggle = (key: string) =>
      update($, openNodes, xs => (xs.includes(key) ? xs.filter(x => x !== key) : [...xs, key]))
    const visible = lines.slice(offset, offset + height).map(line => {
      return line.isOpenable ? (
        <Button key={`h-${line.key}`} plain onPress={() => toggle(line.key)}>
          {line.prefix}
          <Text color={line.markColor}>{line.mark}</Text> {line.text}
          {line.pad}
          <Text dimColor>{line.meta}</Text>
        </Button>
      ) : (
        <Box flexDirection="row">
          <Text dimColor>{line.prefix}</Text>
          <Text color={line.markColor}>{line.mark}</Text>
          <Text>
            {' '}
            {line.text}
            {line.pad}
          </Text>
          <Text dimColor>{line.meta}</Text>
        </Box>
      )
    })
    out.push(
      <Box flexDirection="column" height={height} overflow="hidden">
        {lines.length === 0 ? <Text dimColor>{m.noHistory}</Text> : visible}
      </Box>,
    )
    if (lines.length > height) {
      const step = Math.max(1, Math.floor(height / 2))
      out.push(
        <Box flexDirection="row">
          <Button
            key="h-up"
            label="▲"
            onPress={() => update($, historyOffset, o => Math.min(maxOffset, Math.min(o, maxOffset) + step))}
          />
          <Button
            key="h-down"
            label="▼"
            onPress={() => update($, historyOffset, o => Math.max(0, Math.min(o, maxOffset) - step))}
          />
          <Button key="h-top" label={m.latest} onPress={() => update($, historyOffset, () => 0)} />
          <Text dimColor>
            {' '}
            {m.scrollInfo(offset + 1, Math.min(lines.length, offset + height), lines.length)}
          </Text>
        </Box>,
      )
    }

    if (open.size > 0 || run !== null) {
      out.push(<Text> </Text>)
      out.push(
        <Box>
          {open.size > 0 && <Button key="collapse" label={m.collapseHistory} onPress={() => update($, openNodes, () => [])} />}
          {run !== null && (
            <Button
              key="expand"
              label={openWorkers.length > 0 ? m.collapseWorkers : m.expandWorkers}
              onPress={() => update($, expanded, () => (openWorkers.length > 0 ? [] : run.workers.map(w => w.task)))}
            />
          )}
        </Box>,
      )
    }

    // Draw the context dragon in the remaining vertical space.
    // Each element of out is one row, except the history list Box, which is height rows.
    const room = e.props.scroll.bodyRows - (out.length - 1 + height) - 1
    const usage = await read($, contextUsage)
    const percentText = usage === null ? m.measuring : `${usage.percent}%`
    const tokensText =
      usage === null ? '' : <Text dimColor> · {shortTokens(usage.tokens)}/{shortTokens(usage.window)}</Text>
    if (!config.showDragon) {
      isDragonMounted = false
      out.push(<Text> </Text>)
      out.push(
        <Text wrap="truncate-end">
          {m.context(percentText)}
          {tokensText}
        </Text>,
      )

      return <Box flexDirection="column">{out}</Box>
    }
    const shownStage = (await read($, dragonStage)) ?? 0
    const morph = await read($, dragonMorph)
    const stage = STAGES[shownStage] ?? STAGES[0]
    const tint = stage?.tint ?? 'claude'
    const next = STAGES[shownStage + 1]
    const compactState = await read($, dragonCompact)
    const regrow =
      compactState === 'idle' ? (
        <Button key="dragon-regrow" label={m.regrow} onPress={() => regrowDragon($)} />
      ) : (
        <Text color={tint}>{compactState === 'queued' ? m.regrowQueued : m.regrowRunning}</Text>
      )
    const els = $.ui.resolve(e)
    const Raster = 'Raster' in els ? els.Raster : undefined
    isDragonMounted = false
    if (Raster !== undefined && room >= CANVAS_ROWS) {
      const title =
        morph === null ? `${m.dragonName} Lv.${shownStage + 1}` : morph.to > morph.from ? m.evolving : m.devolving
      const info = [
        <Text bold color={tint}>
          {title}
        </Text>,
        <Text>
          {m.context(percentText)}
          {tokensText}
        </Text>,
        next === undefined ? (
          <Text color={tint}>{m.maxed}</Text>
        ) : (
          <Box flexDirection="row">
            <Text dimColor>→ Lv.{shownStage + 2} </Text>
            {bar(usage === null ? 0 : stageProgress(usage.percent), 10, tint)}
          </Box>
        ),
        <Text dimColor italic wrap="wrap">
          {m.dragonFlavor[shownStage] ?? ''}
        </Text>,
        regrow,
      ]
      const isSide = columns >= CANVAS_W + 24
      if (isSide || room >= CANVAS_ROWS + info.length) {
        const cells = sceneCells({ stage: shownStage, morph, now })
        const canvas = <Raster key={DRAGON_KEY} columns={CANVAS_W} rows={CANVAS_ROWS} cells={cells} />
        isDragonMounted = true
        lastDragonCells = cells
        out.push(<Text> </Text>)
        out.push(
          isSide ? (
            // The dragon stands on the canvas floor, so align the text to the bottom too —
            // at the top it floats beside empty sky.
            <Box flexDirection="row" alignItems="flex-end">
              {canvas}
              <Box flexDirection="column" marginLeft={2} width={Math.max(10, columns - CANVAS_W - 2)}>
                {info}
              </Box>
            </Box>
          ) : (
            <Box flexDirection="column">
              {canvas}
              {info}
            </Box>
          ),
        )
      }
    }
    // If there is no room for the canvas, still show the stage in one line.
    if (!isDragonMounted) {
      out.push(<Text> </Text>)
      out.push(
        <Box flexDirection="row">
          <Text color={tint} wrap="truncate-end">
            {DRAGON_ICON[shownStage] ?? '🐉'} {m.dragonName} Lv.{shownStage + 1} · {m.context(percentText)}
            {morph === null ? '' : morph.to > morph.from ? m.evolvingShort : m.devolvingShort}{' '}
          </Text>
          {regrow}
        </Box>,
      )
    }

    return <Box flexDirection="column">{out}</Box>
  })

  on('ui.open', async ($, e, next) => {
    const opened = await next(e)
    if (e.id === PANE && opened.value?.isPlaced === true) {
      await update($, isPaneOpen, () => true)
      await syncFastTimers($)
    }

    return opened
  })

  on('ui.close', async ($, e, next) => {
    const closed = await next(e)
    if (e.id === PANE && closed.deny === undefined) {
      await update($, isPaneOpen, () => false)
      await syncFastTimers($)
      if (e.origin.kind === 'person') await update($, isPaneDismissed, () => true)
    }

    return closed
  })

  // A wheel scrolled over the task history list moves only the list.
  // Anywhere else passes through to scrolling the whole pane.
  on('ui.scroll', { component: 'Pane', requestId: PANE }, async ($, e, next) => {
    const view = historyView
    const row = e.pointer === undefined ? undefined : view.paneOffset + e.pointer.row
    const isOverList = row !== undefined && row >= view.top && row < view.top + view.height
    if (!isOverList || view.total <= view.height) return next(e)
    const maxOffset = view.total - view.height
    await update($, historyOffset, o => Math.max(0, Math.min(maxOffset, Math.min(o, maxOffset) - e.by)))

    return {}
  })
}
