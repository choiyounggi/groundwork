// A pixel dragon that grows through 7 stages with context usage. Only pure functions live here — state, timers and
// draw wiring are done by register.tsx.
//
// Each terminal cell holds two vertically stacked pixels as a half block (▀/▄): the foreground color is the top
// pixel and the background color is the bottom pixel. So the canvas is a single Raster of CANVAS_W columns ×
// CANVAS_H/2 rows.

export const CANVAS_W = 44
export const CANVAS_H = 28
export const CANVAS_ROWS = CANVAS_H / 2
/** One animation frame (ms). The timer blits at this interval. */
export const TICK_MS = 140
/** Morph animation length (ms). */
export const MORPH_MS = 3000

export type Morph = { from: number; to: number; startedAt: number }
export type DragonScene = { stage: number; morph: Morph | null; now: number }

/**
 * Sprite character → palette key.
 * . transparent · o outline · b body · d shade · l belly and yellow highlight · w wing membrane · e eye · h eye highlight
 * t horn/teeth/claw · m inside of mouth · q eggshell, on a dragon the lit top of the body · z shell spot, on a
 * dragon the cheek blush · c glowing crack (veins) · x deep shade, wing bones, void
 */
type Key = 'o' | 'b' | 'd' | 'l' | 'w' | 'e' | 'h' | 't' | 'm' | 'q' | 'z' | 'c' | 'x'
type Palette = Record<Key, number>

type Stage = {
  /** Context usage (%) at which this stage begins. */
  from: number
  /** Info text color (body color). */
  tint: string
  palette: Palette
  sprite: readonly string[]
}

const EGG = [
  '.....oooo.....',
  '...ooqqqqoo...',
  '..oqqhqqzqqo..',
  '.oqqhqqqqzzqo.',
  '.oqhqqzqqqzqo.',
  'oqqqqzzqqqqqqo',
  'oqqqqzzqqqcqqo',
  'oqqqqqqqqcqqqo',
  'oqzqqqqqccqqqo',
  'oqzzqqqcqqqzqo',
  'oqqqqqqqcqqzqo',
  '.oqqqqqqqcqqo.',
  '.oxqqqqqqqqxo.',
  '..oxxqqqqxxo..',
  '...ooxxxxoo...',
  '.....oooo.....',
]
const HATCHLING = [
  '.......oo.......',
  '......oqqo......',
  '.....oqzqqo.....',
  '......ooooo.....',
  '.....ooqqqqoo...',
  '....oqqbbbbqqo..',
  '...oqbbbboobbqo.',
  '...obbbbbehbbbqo',
  '...obbbbbeobbboo',
  '...odzzbbbbbbbbo',
  '..ooddbbbbbbbbdo',
  '.oooodobooloooo.',
  'oqotqtqoqqoqtoto',
  'oqqqqqqqqqqqqqqo',
  'oqzqqqqqzzqqqqqo',
  'oqqqqzqqqqqqzqqo',
  'oqqqqqqqqqqqqqqo',
  '.oqqqqqqqqqqqqo.',
  '..oqqqqqqqqqqo..',
  '...ooqqqqqqoo...',
  '.....oooooo.....',
]
const CHILD = [
  '.........o....o...o.......',
  '.......ooqo..otooooo......',
  '.....ooxxqo..ooqqqqqoo....',
  '....oxwxwqqooqqbbbbbqqo...',
  '.....owxxqqoqbbbbbbbbbqo..',
  '.....oxwxwqobbbbbbboobbqo.',
  '....oowwxwqobbbbbboehbbbqo',
  '..ooxoooxwqobbbbbboeobbboo',
  '.oxoo...ooqodzzbbbboobbbbo',
  'oxxbo...ooooddbbbbbbbbbbdo',
  '.obbdoooqqqqoddbllllloooo.',
  '..obbboqbbbbbodddddddddo..',
  '...odoqbbbbbblooooooooo...',
  '....oobbbbbbldllo.........',
  '.....odbbbbblllbo.........',
  '.....odbbbbbblooo.........',
  '......oddoobbobbo.........',
  '......ooobbodobdo.........',
  '.......oobdoooto..........',
  '.........to...............',
]
const TEEN = [
  '............o.....o....o..........',
  '.........oooqo...oto..oto.........',
  '.....ooooxwxqqo..otto.otto........',
  '.ooooxxwwxxxqqo..ottoooooo........',
  'oxxwwwwwxwwxwqo...oooqqqqqoo......',
  '.oowwwwxwwxwwqqo..oqqbbbbbqqo.....',
  '...owxxwwwxwwwqo.oqbbbbbbbbbqo....',
  '.o.oxwwwwxwwwwqooqbbbbbbbooobqo...',
  'owoxwwwwwxwwwwqqobbbbbbboeehbbqo..',
  'owxwoowwxwwwwowoobbbbbbboeeobbbqo.',
  '.owo.owwxwwwololobbbbbbbboobbbboqo',
  '..o..owxwwwoooooobzzbbbbbbbbbbbbbo',
  '.oxo.owxwwooqqqqodbbbbbbbbbbbbbbbo',
  'oxxxo.owwoqqbbbboddbbbbbbbbooombdo',
  '.oxbdo.ooqbbbbbbboddblllllllltdoo.',
  '..obdo..obbbbbbbbloddddlllllddo...',
  '..obbdo.obbbbbbblddooodddddooo....',
  '..obbbdoodbbbbbbllllldooooo.......',
  '...obbbbodbbbbbbldddlboo..........',
  '....odddoddbboobbllldobbo.........',
  '.....oooooddobbobbddobbbdo........',
  '.........ooobbbdoddoobbbdo........',
  '.........odobbbdooo..obdo.........',
  '..........odobdo.....tot..........',
  '..........ootot...................',
]
const ADULT = [
  '...............o...o..................',
  '...........ooooqooodoo....o...........',
  '......oooooxxxxqqoodoto..oto..........',
  '.oooooxxwwwwxwxqqoodotto.otto.........',
  'oxxwwwwwwwxxwxwwqooxotto.ooooo........',
  'owowwwwwwxwwwxwwqooxdooooqqqqqoo......',
  '.o.owwwxxwwwxwwwqqoxddoqqbbbbbqqo.....',
  '...owwxwwwwwxwwwwqoxdoqbbbbbbbbbqo....',
  '.oowxwwwwwwxwwwwwqoxoqbbbbbbbooobqo...',
  'owxxwwwwwwwxwwwwwqooobbbbbbboeehbbqo..',
  'oxwwwowwwwxwwwwwooloobbbbbbboeeobbbqo.',
  '.oowo.owwwwwwwwoololobbbbbbbboobbbboqo',
  '...oxoowwxwwwoolloooobzzbbbbbbbbbbbbbo',
  '..oxxowwxwwwoxoooqqqodbbbbbbbbbbbbbbbo',
  '..oxxxooxwwwooqqbbbboddbbbbbbbooommbdo',
  '...oxbdooooooqbbbbbbboddbllllllltltoo.',
  '....obdo....obbbbbbbbloddddlllllddo...',
  '....obbdo...obbbbbbblddooodddddooo....',
  '....obbbdoooodbbbbbbllllldooooo.......',
  '.....obbbbbbodbbbbbbldddlboo..........',
  '......odddddoddbboobbllldobbo.........',
  '.......oooooooddobbobbddobbbdo........',
  '.............ooobbbdoddoobbbdo........',
  '.............odobbbdooo..obdo.........',
  '..............odobdo.....tot..........',
  '..............ootot...................',
]
const ELDER = [
  '..................o...o................',
  '.............oooooqooooo...o...........',
  '.......ooooooxxwxxqqooto..oto..........',
  '..oooooxxwwwwwxxwxqqootto.otto.........',
  '.oxxwwwwwwwwxxwwxwwqoootto.otto........',
  'owwwwwwwwwwxwwwxwwwotoottoooooo........',
  '.ooowwwwwxxwwwwxwwwottooooqqqqqoo......',
  '...owwwxxwwwwwxwwwwottooqqbbbbbqqo.....',
  '.ooowxxwwwwwwwwwwwwwoooqbbbbbbbbbqo....',
  'owwwxwwwwwwwwxwwwwwwqoqbbbbbbbooobqo...',
  '.oxxwwwwwwwwxwwwwwwoqobbbbbbboeehbbqo..',
  '.owwwoowwwwwwwwwwoocoobbbcbbboeeobbbqo.',
  '..ooo..owwwxwwwwoococobbbbcbbboobbbboqo',
  '...oxo.owwxwwwwocooooobbbbbbbbbbbbbbbbo',
  '..oxxxowwwxwwwoccoqqqodbbbbbbbbbbbbbbbo',
  '..oxxxxooowwwwooobbbboddbbbbbbbooommbdo',
  '...oxbdo..ooooqbcbbbcboddbllllllltltoo.',
  '....obdo.....obbbcbcbbloddddlllllddo...',
  '....obbdo....obbbbbbblddooodddddooo....',
  '....obbbdooooodbbbcbbllllldooooo.......',
  '.....obbbbbbbodbbbbbbldddlboo..........',
  '......oddddddoddbboobbllldobbo.........',
  '.......oooooo.oddobbobbddobbbdo........',
  '..............ooobbbdoddoobbbdo........',
  '..............odobbbdooo..obdo.........',
  '...............odobdo.....tot..........',
  '...............ootot...................',
]
const ULTIMATE = [
  '.....................o...o..............',
  '...............ooooooqooodo.o...........',
  '........oooooooxxwwxxqotoototo...o......',
  '..ooooooxxxwwwwwwxwwxqottototto.oto.....',
  '.oxxwwwwwwwwwwwxxwwxwoqottooottotto.....',
  'owwwwwwwwwwwwxoowwxwotoottooooootto.....',
  '.oowwwwwwwwxxweowxwwottooooqqqqqoo......',
  '...owwwwwxxwwwwwwxwwottooqqbbbbbqqo.....',
  '.o.owwwxxoowwwwwxwwwwoooqoobbbbbbbqo....',
  'owowwxxwweowwwwxwwwwwwoqbeobbbbooobqo...',
  'owwxxwwwwwwwwwxwwwwwowobbbbbbboeehbbqo..',
  '.oxwwwwwwwwwwwxwwwooxoobbbcbbboeeobbbqo.',
  '..owwooowwwwwxwwwooxoxobbbbcbbboobbbboqo',
  '...owo.owwwwxwwwoxooooobbbbbbbbbbbbbbbbo',
  '..oxoxoowwwwwwwoxxoqqqodbbbbbbbbbxbbbbbo',
  '..oxxxxowwwxwwwooobbbboddbbbbbbbooommbdo',
  '...oxbdoooowwwoqbcoobcboddbllllllltltoo.',
  '....obdo...oooobbbeocbbloddddlllllddo...',
  '....obbdo.....obbbbbbblddooodddddooo....',
  '....obbbdoooo.odbbbcbbllllldooooo.......',
  '.....obbbbbbboodbbbbbxlxddlboo..........',
  '......oddddddooddbboobbllldobbo.........',
  '.......oooooo..oddobbobbddobbbdo........',
  '...............ooobbbdoddoobbbdo........',
  '...............odobbbdooo..obdo.........',
  '................odobdo.....tot..........',
  '................ootot...................',
]
export const STAGES: readonly Stage[] = [
  {
    from: 0,
    tint: '#f3e9d2',
    sprite: EGG,
    palette: {
      o: 0x3a2418, b: 0x000000, d: 0x000000, l: 0x000000, w: 0x000000,
      e: 0x000000, h: 0xffffff, t: 0x000000, m: 0x000000, q: 0xfff3dc,
      z: 0xf2994a, c: 0xff7a30, x: 0xe6c39a,
    },
  },
  {
    from: 10,
    tint: '#f59a48',
    sprite: HATCHLING,
    palette: {
      o: 0x2a1214, b: 0xf59a48, d: 0xd8674a, l: 0xffd35a, w: 0xe0605a,
      e: 0x3a1a24, h: 0xffffff, t: 0xfff8ec, m: 0x8a2c46, q: 0xfff3dc,
      z: 0xf2994a, c: 0xff7a30, x: 0x8a2c46,
    },
  },
  {
    from: 25,
    tint: '#ec7a2c',
    sprite: CHILD,
    palette: {
      o: 0x22101a, b: 0xec7a2c, d: 0xc04a4a, l: 0xf6c43a, w: 0xd8505a,
      e: 0xffe680, h: 0xffffff, t: 0xf4efe6, m: 0x6e1a44, q: 0xf8a640,
      z: 0xff8f80, c: 0xff6030, x: 0x6e1a44,
    },
  },
  {
    from: 40,
    tint: '#dd5b1f',
    sprite: TEEN,
    palette: {
      o: 0x1a0a12, b: 0xdd5b1f, d: 0xa9384e, l: 0xefb027, w: 0xc8434f,
      e: 0xffe066, h: 0xffffff, t: 0xf0ece3, m: 0x5d123d, q: 0xec8610,
      z: 0xf0806a, c: 0xff5030, x: 0x5d123d,
    },
  },
  {
    from: 55,
    tint: '#cf4520',
    sprite: ADULT,
    palette: {
      o: 0x16060e, b: 0xcf4520, d: 0x92283e, l: 0xeca82c, w: 0xb4323e,
      e: 0xffd23a, h: 0xffffff, t: 0xece4d6, m: 0x4e0e30, q: 0xe8702a,
      z: 0xe8705e, c: 0xff4a20, x: 0x4e0e30,
    },
  },
  {
    from: 70,
    tint: '#b02a28',
    sprite: ELDER,
    palette: {
      o: 0x120408, b: 0xb02a28, d: 0x6e1630, l: 0xd8803a, w: 0x8a1a30,
      e: 0xff8a1a, h: 0xfff0a0, t: 0xd8ccb8, m: 0x380820, q: 0xd0452a,
      z: 0xc04040, c: 0xff5a1a, x: 0x380820,
    },
  },
  {
    from: 85,
    tint: '#6a0e1c',
    sprite: ULTIMATE,
    palette: {
      o: 0x080104, b: 0x6a0e1c, d: 0x3c0612, l: 0xa83a24, w: 0x4a0818,
      e: 0xffffff, h: 0xff2000, t: 0xb8a888, m: 0x14020a, q: 0x8e1a24,
      z: 0x8e1a24, c: 0xff2a10, x: 0x14020a,
    },
  },
]

export const LAST_STAGE = STAGES.length - 1

/** Context usage (0~100) → stage number (0~6). */
export function stageOf(percent: number): number {
  let stage = 0
  for (let i = 0; i < STAGES.length; i++) {
    if (percent >= (STAGES[i]?.from ?? Infinity)) stage = i
  }

  return stage
}

/** How far through the current stage toward the next morph (0~100). The last stage is 100. */
export function stageProgress(percent: number): number {
  const stage = stageOf(percent)
  const from = STAGES[stage]?.from ?? 0
  const to = STAGES[stage + 1]?.from
  if (to === undefined) return 100

  return Math.max(0, Math.min(100, Math.round(((percent - from) / (to - from)) * 100)))
}

// ── Pixel drawing ──────────────────────────────────────────────

/** null = transparent. */
type Grid = (number | null)[]

/** Deterministic noise (0~1) — the same input gives the same frame, so tests stay stable. */
function noise(a: number, b: number, c = 0): number {
  let h = (a * 374761393 + b * 668265263 + c * 2147483647) | 0
  h = Math.imul(h ^ (h >>> 13), 1274126177)
  h ^= h >>> 16

  return (h >>> 0) / 4294967296
}

function spriteOf(stage: number): Stage {
  return STAGES[Math.max(0, Math.min(LAST_STAGE, stage))] as Stage
}

function spriteWidth(sprite: readonly string[]): number {
  return Math.max(...sprite.map(row => row.length))
}

/**
 * Top-left canvas coordinates of the sprite. Anchored to the bottom, with room on the right for stages that breathe
 * fire.
 */
function originOf(stage: number): { x: number; y: number } {
  const { sprite } = spriteOf(stage)
  const room = stage >= 3 ? 3 : 0

  return {
    x: Math.max(0, Math.floor((CANVAS_W - spriteWidth(sprite)) / 2) - room),
    y: CANVAS_H - sprite.length,
  }
}

function put(grid: Grid, x: number, y: number, color: number): void {
  if (x < 0 || y < 0 || x >= CANVAS_W || y >= CANVAS_H) return
  grid[y * CANVAS_W + x] = color
}

function mix(a: number, b: number, t: number): number {
  const k = Math.max(0, Math.min(1, t))
  const ch = (shift: number) =>
    Math.round(((a >> shift) & 0xff) * (1 - k) + ((b >> shift) & 0xff) * k) & 0xff

  return (ch(16) << 16) | (ch(8) << 8) | ch(0)
}

type DrawOptions = {
  dx?: number
  dy?: number
  isBlinking?: boolean
  /** Paint every pixel with this color (morph flash silhouette). */
  silhouette?: number
  /** 0~1: how much to blend toward the white flash. */
  flash?: number
  /** Brightness of the glowing cracks (0~1). */
  glow?: number
  /** Whether to draw this pixel (morph dissolve). */
  mask?: (x: number, y: number) => boolean
}

function drawSprite(grid: Grid, stage: number, options: DrawOptions = {}): void {
  const { sprite, palette } = spriteOf(stage)
  const origin = originOf(stage)
  const glow = options.glow ?? 1
  sprite.forEach((row, sy) => {
    for (let sx = 0; sx < row.length; sx++) {
      const key = row[sx] as Key | '.'
      if (key === '.') continue
      const x = origin.x + sx + (options.dx ?? 0)
      const y = origin.y + sy - (options.dy ?? 0)
      if (options.mask !== undefined && !options.mask(x, y)) continue
      let color = palette[key]
      if (options.isBlinking && (key === 'e' || key === 'h')) color = palette.d
      if (key === 'c') color = mix(palette.d, palette.c, glow)
      if (options.silhouette !== undefined) color = options.silhouette
      if (options.flash !== undefined) color = mix(color, 0xffffff, options.flash)
      put(grid, x, y, color)
    }
  })
}

/** Mouth tip (where fire is breathed out): the cell just right of the rightmost 'm' in the topmost row that has one. */
function mouthOf(stage: number): { x: number; y: number } | null {
  const { sprite } = spriteOf(stage)
  const origin = originOf(stage)
  for (let sy = 0; sy < sprite.length; sy++) {
    const row = sprite[sy] as string
    if (!row.includes('m')) continue

    // Where the trailing transparent (.) begins = just right of the end of the head.
    return { x: origin.x + row.search(/\.*$/), y: origin.y + sy }
  }

  return null
}

const FIRE: readonly (readonly number[])[] = [
  [0xfff4c0, 0xffc040, 0xff7020, 0xd02010], // bright fire
  [0xffe0a0, 0xff9020, 0xe03010, 0x901008], // deep fire
  [0xffffff, 0xff2040, 0x900018, 0x30000a], // ultimate form: from blood red to dark crimson
]

function drawFire(grid: Grid, stage: number, t: number, frame: number, dy: number): void {
  const mouth = mouthOf(stage)
  if (mouth === null) return
  const colors = FIRE[stage >= 6 ? 2 : stage >= 5 ? 1 : 0] as readonly number[]
  const maxLength = stage >= 6 ? 16 : stage >= 4 ? 12 : 5
  // Bursts out (first 20%), holds, then dies down (last 25%).
  const reach = t < 0.2 ? t / 0.2 : t > 0.75 ? (1 - t) / 0.25 : 1
  const length = Math.max(1, Math.round(maxLength * reach))
  for (let dx = 0; dx < length; dx++) {
    const spread = Math.floor(dx / 3)
    for (let off = -spread; off <= spread; off++) {
      if (noise(dx, off, frame) > 0.78) continue
      const depth = dx / maxLength + Math.abs(off) * 0.08
      const color = colors[Math.min(colors.length - 1, Math.floor(depth * colors.length))] as number
      put(grid, mouth.x + dx, mouth.y + off - dy, color)
    }
  }
}

/** From stage 5, embers rise around the body; the ultimate form adds void fragments too. */
function drawEmbers(grid: Grid, stage: number, now: number): void {
  const count = stage >= 6 ? 16 : 7
  const { palette } = spriteOf(stage)
  for (let i = 0; i < count; i++) {
    const x = Math.floor(noise(i, 7) * CANVAS_W)
    const speed = 60 + noise(i, 11) * 80
    const y = CANVAS_H - 1 - Math.floor((now / speed + noise(i, 3) * CANVAS_H) % CANVAS_H)
    if (grid[y * CANVAS_W + x] !== null) continue
    const isVoid = stage >= 6 && i % 3 === 0
    put(grid, x, y, isVoid ? 0x3a0010 : mix(palette.c, 0x400000, noise(i, Math.floor(now / 300))))
  }
}

/** Shifts a few rows sideways as if the screen were torn — more frequent toward the ultimate form. */
function glitch(grid: Grid, stage: number, frame: number): void {
  const chance = stage >= 6 ? 0.45 : 0.12
  if (noise(frame, 99) > chance) return
  const bands = stage >= 6 ? 1 + Math.floor(noise(frame, 5) * 3) : 1
  for (let b = 0; b < bands; b++) {
    const y0 = Math.floor(noise(frame, b, 1) * CANVAS_H)
    const h = 1 + Math.floor(noise(frame, b, 2) * (stage >= 6 ? 4 : 2))
    const shift = (noise(frame, b, 3) < 0.5 ? -1 : 1) * (1 + Math.floor(noise(frame, b, 4) * (stage >= 6 ? 3 : 1)))
    for (let y = y0; y < Math.min(CANVAS_H, y0 + h); y++) {
      const row = grid.slice(y * CANVAS_W, (y + 1) * CANVAS_W)
      for (let x = 0; x < CANVAS_W; x++) grid[y * CANVAS_W + x] = row[(x - shift + CANVAS_W) % CANVAS_W] ?? null
    }
  }
}

function drawIdle(grid: Grid, stage: number, now: number): void {
  const frame = Math.floor(now / TICK_MS)
  if (stage === 0) {
    // Egg: wobbles now and then.
    const isWobbling = now % 3200 < 420
    drawSprite(grid, 0, { dx: isWobbling ? (frame % 2 === 0 ? 1 : -1) : 0 })

    return
  }
  const dy = Math.floor(now / 800) % 2
  // The ultimate form never closes its eyes — instead the gaze pulses.
  const isBlinking = stage < 6 && now % 4200 < 180
  const glow = 0.55 + 0.45 * Math.sin(now / 260)
  if (stage >= 5) drawEmbers(grid, stage, now)
  drawSprite(grid, stage, { dy, isBlinking, glow })
  if (stage >= 6 && Math.floor(now / 300) % 2 === 1) {
    const { palette } = spriteOf(stage)
    // The eyes alternately blaze white and red.
    const swap: Grid = grid.map(color => (color === palette.e ? palette.h : color))
    swap.forEach((color, i) => (grid[i] = color))
  }
  if (stage >= 3) {
    const period = stage >= 6 ? 6000 : 9000
    const duration = stage >= 4 ? 1800 : 900
    const phase = (now + 2500) % period
    if (phase < duration) drawFire(grid, stage, phase / duration, frame, dy)
  }
  if (stage >= 5) glitch(grid, stage, frame)
}

function drawMorph(grid: Grid, morph: Morph, now: number): void {
  const p = Math.max(0, Math.min(1, (now - morph.startedAt) / MORPH_MS))
  const frame = Math.floor(now / TICK_MS)
  const target = spriteOf(morph.to)
  if (p < 0.35) {
    // Trembles, then flashes — faster and faster.
    const shake = noise(frame, 1) < 0.5 ? -1 : 1
    const isFlash = frame % (p < 0.2 ? 3 : 2) === 0
    drawSprite(grid, morph.from, { dx: shake, silhouette: isFlash ? target.palette.c : undefined })

    return
  }
  if (p < 0.75) {
    // The old body shatters and the new body is revealed.
    const q = (p - 0.35) / 0.4
    drawSprite(grid, morph.from, { mask: (x, y) => noise(x, y, 17) >= q, flash: 0.25 })
    drawSprite(grid, morph.to, { mask: (x, y) => noise(x, y, 17) < q, flash: 0.5 * (1 - q) })
    for (let i = 0; i < 18; i++) {
      put(grid, Math.floor(noise(i, frame, 5) * CANVAS_W), Math.floor(noise(i, frame, 6) * CANVAS_H), 0xfff0d0)
    }

    return
  }
  // The flash clears and a shockwave spreads.
  const r = (p - 0.75) / 0.25
  drawSprite(grid, morph.to, { flash: 1 - r })
  const origin = originOf(morph.to)
  const cx = origin.x + spriteWidth(target.sprite) / 2
  const cy = origin.y + target.sprite.length / 2
  const radius = 4 + r * 26
  for (let a = 0; a < 96; a++) {
    const angle = (a / 96) * Math.PI * 2
    put(grid, Math.round(cx + Math.cos(angle) * radius), Math.round(cy + Math.sin(angle) * radius * 0.55), mix(target.palette.c, 0x000000, r))
  }
}

/** Pixels of one scene (CANVAS_W × CANVAS_H, null = transparent). */
export function renderPixels(scene: DragonScene): Grid {
  const grid: Grid = new Array(CANVAS_W * CANVAS_H).fill(null)
  if (scene.morph !== null && scene.now - scene.morph.startedAt < MORPH_MS) drawMorph(grid, scene.morph, scene.now)
  else drawIdle(grid, scene.stage, scene.now)

  return grid
}

const DEFAULT_COLOR = 0x01000000
const UPPER = 0x2580
const LOWER = 0x2584
const SPACE = 0x20

/** Packs pixels into the cells of a Raster (half blocks, base64). */
export function encodeCells(grid: Grid): string {
  const words = new Uint32Array(CANVAS_W * CANVAS_ROWS * 3)
  for (let row = 0; row < CANVAS_ROWS; row++) {
    for (let x = 0; x < CANVAS_W; x++) {
      const top = grid[row * 2 * CANVAS_W + x] ?? null
      const bottom = grid[(row * 2 + 1) * CANVAS_W + x] ?? null
      const at = (row * CANVAS_W + x) * 3
      if (top === null && bottom === null) words.set([SPACE, DEFAULT_COLOR, DEFAULT_COLOR], at)
      else if (top === null) words.set([LOWER, bottom as number, DEFAULT_COLOR], at)
      else words.set([UPPER, top, bottom ?? DEFAULT_COLOR], at)
    }
  }
  const bytes = new Uint8Array(words.buffer)
  let binary = ''
  for (let i = 0; i < bytes.length; i += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000))
  }

  return btoa(binary)
}

export function sceneCells(scene: DragonScene): string {
  return encodeCells(renderPixels(scene))
}

/** Shortens a token count: 1234 → 1.2k, 1_200_000 → 1.2M. */
export function shortTokens(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(n >= 10_000_000 ? 0 : 1)}M`
  if (n >= 1_000) return `${(n / 1_000).toFixed(n >= 100_000 ? 0 : 1)}k`

  return String(n)
}
