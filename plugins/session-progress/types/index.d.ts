export type TodoStatus = 'pending' | 'in_progress' | 'completed'

/** One todo the model manages through TodoWrite, TaskCreate/TaskUpdate, or the mod's steps tool. */
export type Todo = {
  id: string
  subject: string
  status: TodoStatus
  activeForm?: string
  /** Time (ms) it changed to completed. Kept if the same subject is written again. */
  doneAt?: number
}

/** One turn of the main loop = one task done in the session. `tools` counts only main-loop calls. */
export type Turn = {
  id: string
  text: string
  startedAt: number
  endedAt?: number
  /**
   * One-line title condensed from the request (haiku summary). Before it arrives, or on failure, the first sentence
   * of text is used.
   */
  title?: string
  tools: number
  outcome?: 'answer' | 'aborted' | 'refusal' | 'error'
  /** This task's plan steps and the status of each — shown when the task is expanded in the history tree. */
  steps?: { title: string; status: TodoStatus }[]
}

/** The engine's AgentStatus plus "vanished from the list". */
export type AgentRowStatus =
  | 'pending'
  | 'running'
  | 'waiting'
  | 'idle'
  | 'completed'
  | 'failed'
  | 'killed'
  | 'gone'

/** One subagent or teammate of this session. Attached to the turn that was in progress when it first appeared. */
export type AgentRow = {
  id: string
  description: string
  type: string
  status: AgentRowStatus
  turnId?: string
  tools: number
}

/** One `- [x] Gn: …` line of a dev-loop gate ledger (`.dev-loop/gates/<task>.md`). */
export type Gate = { id: string; title: string; isDone: boolean }

/** One dev-loop:orchestrate task = the progress state of one worker session. */
export type Worker = {
  task: string
  phase: string
  percent: number
  updatedAt?: number
  session?: string
  attempt?: number
  error?: string
  gates: Gate[]
}

/** One dev-loop run that the coordinator session is watching. */
export type Orchestration = {
  root: string
  workers: Worker[]
  percent: number
  /** True if there are unfinished workers or it was updated recently — the banner is drawn only then. */
  isActive: boolean
}

/** Most recently measured context window usage. Null before the first response. */
export type ContextUsage = { percent: number; tokens: number; window: number }

/** One dragon morph animation: from stage `from` to stage `to`, lasting MORPH_MS from startedAt (ms). */
export type DragonMorph = { from: number; to: number; startedAt: number }

declare module 'claude-code' {
  interface PluginState {
    'session-progress': {
      /** Todos reported by the current task. Cleared when a new task starts. */
      todos: Todo[]
      /**
       * Todos of earlier tasks when the next request arrived while they were running and was chained. Shown before
       * todos on screen.
       */
      carried: Todo[]
      /**
       * Id of the first turn of the task chain currently in progress. The bottom agent bar counts only this chain's
       * agents.
       */
      chainStart: string | null
      /**
       * Time the next request was entered while a task was running — decides whether the next turn chains on instead
       * of resetting.
       */
      appendRequestedAt: number | null
      turns: Turn[]
      agents: AgentRow[]
      orchestration: Orchestration | null
      expanded: string[]
      /** Ids of the nodes expanded in the task history tree. */
      openNodes: string[]
      /**
       * Scroll position of the task history list — how many lines up from the bottom (latest). 0 follows the
       * latest.
       */
      historyOffset: number
      /** Whether the list pane is on screen. If it is, the banner does not redraw the same bar as the pane. */
      isPaneOpen: boolean
      /**
       * Whether the user closed the pane manually. If so, it is not opened automatically until reopened with
       * /progress.
       */
      isPaneDismissed: boolean
      /** Tasks (turn ids) waiting for a title summary. A timer takes them one at a time and summarizes. */
      pendingTitles: string[]
      /** Spinner frame number. The timer advances it only while a task is in progress and the pane is open. */
      spinFrame: number
      /** Context usage — determines the dragon's stage. */
      contextUsage: ContextUsage | null
      /** Stage of the dragon currently on screen (0 egg ~ 6 ultimate form). Changes only once the morph finishes. */
      dragonStage: number | null
      /** Morph in progress. Null if none. */
      dragonMorph: DragonMorph | null
      /** "Raise again" (compaction) state: idle · queued (waiting for the task to finish) · running (compacting). */
      dragonCompact: 'idle' | 'queued' | 'running'
    }
  }
}
