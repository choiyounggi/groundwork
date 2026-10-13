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
 * . transparent · o outline · b body · d shade/wing bone · l belly · w wing membrane · e eye · h eye highlight
 * t horn/teeth/claw · m inside of mouth · q eggshell · z shell spot · c glowing crack (veins) · x void
 */
type Key = 'o' | 'b' | 'd' | 'l' | 'w' | 'e' | 'h' | 't' | 'm' | 'q' | 'z' | 'c' | 'x'
type Palette = Record<Key, number>

type Stage = {
  /** Context usage (%) at which this stage begins. */
  from: number
  flavor: string
  /** Info text color (body color). */
  tint: string
  palette: Palette
  sprite: readonly string[]
}

const EGG = [
  '.....oooo.....',
  '...ooqqqqoo...',
  '..oqqqzqqqqo..',
  '..oqqqqqqzqo..',
  '.oqzqqqqqqqqo.',
  '.oqqqqqzqqqqo.',
  '.oqqqqqqqqzqo.',
  '.oqqzqqqqqqqo.',
  '.oqqqqqqzqqqo.',
  '..oqqqqqqqqo..',
  '..ooqqqqqqoo..',
  '....oooooo....',
]

const HATCHLING = [
  '...........oooo...',
  '..........obbbbo..',
  '.........obbbbbbo.',
  '.........obbhobbbo',
  '.........obboobbbo',
  '..........obbbbmmo',
  '....oo....oobbboo.',
  '...owwo..obbbbbo..',
  '...owwwoobllbbbo..',
  '....owwobllbbbbo..',
  '.oo..oobbllbbbbo..',
  '.obo.obbbllbbbo...',
  '..oqoqoqzqoqoqo...',
  '..oqqqzqqqqqzqqo..',
  '...oqqqqqqqqqqo...',
  '....oooooooooo....',
]

const CHILD = [
  '................to....',
  '...............tbbo...',
  '..............obbbbo..',
  '..............obbeobo.',
  '..............obbbbbbo',
  '...............obbmmmo',
  '.....oo.......obbooo..',
  '....owwo.....obbo.....',
  '...owwwwo...obbbo.....',
  '...owwwwwoobbbbo......',
  '....owwwobbbbbbo......',
  '.....oobbbllllbbo.....',
  'oo..obbbbllllbbbo.....',
  'obo.obbbbbbbbbbbo.....',
  '.obbbbbobbbbobbo......',
  '..ooooobtbo.obtbo.....',
  '.......ottto.ottto....',
]

const TEEN = [
  '...................t.t....',
  '..................tbtbo...',
  '.................obbbbbo..',
  '.................obbbeebo.',
  '.................obbbbbbbo',
  '..................obbmtmto',
  '..o..............obboooo..',
  '.owo............obbo......',
  '.owwo..........obbo.......',
  '.owwwo....t...obbo........',
  '..owwwo..tbo.obbbo........',
  '..owwwwootbbobbbbo........',
  '...owwwwobbbbbbbo.........',
  '....owwobbbblllbbo........',
  '.....oobbbbllllbbo........',
  'oo...obbbbbllllbbo........',
  'tbo..obbbbbbbbbbbo........',
  '.obbbbbbobbbbbobbo........',
  '..oooooobtbo..obtbo.......',
  '........ottto.ottto.......',
]

const ADULT = [
  '......................tt......',
  '..o..................tbbt.....',
  '.odo................obbbbo....',
  '.owdo...............obbbeeo...',
  '.owwdo.............obbbbbbbo..',
  'owwwwdo............obbbmmmmto.',
  'owwwwwdo..........obbbttttoo..',
  'owwdwwwdo........tobbbbbo.....',
  'owwdwwwwdo......tobbbo........',
  'owwwdwwwwdo....tobbbo.........',
  '.owwdwwwwwdo..tobbbo..........',
  '.owwwdwwwwwdotobbbbo..........',
  '..owwwdwwwwobbbbbbbo..........',
  '...owwwdwwobbbbbbbbbo.........',
  '....owwwwobbbblllllbbo........',
  '.....oooobbbbblllllbbo........',
  'too.....obbbbbllllbbbo........',
  '.tbo....obbbbbbbbbbbbo........',
  '..obbo..obbbbbbbbbbbbo........',
  '...obbbbbbbbobbbbbobbo........',
  '....oooooobtbo...obtbo........',
  '..........ottto..ottto........',
]

// From here on, "unease": torn wings, a third eye, light leaking through gaps in the scales.
const ELDER = [
  '........................t..t......',
  '..o.....................tt.tt.....',
  '.odo...................tbbbbbt....',
  '.ow.o.................obbbbbbbo...',
  '.owwdo................obbecbbeeo..',
  'owwwwdo..............obbbbbbbbbo..',
  'ow.wwwdo.............obbbmmmmmmmto',
  'owwdw.wdo...........obbbtmtmtmto..',
  'owwdwwwwdo........ttobbbbtttto....',
  'owwwdww.wdo.....ttobbbboo.........',
  'owwwdwwwwwdo..ttobbbbo............',
  '.owwwdwwwwwdottobbbco.............',
  '.owwwwd.wwwwdobbbbbbo.............',
  '..owwwwdwwwwobbcbbbbbo............',
  '...owwwwdwwobbbbbbcbbbo...........',
  '....owwwwwobbbblllllllbbo.........',
  '.....ooooobbbbbllcllllbbo.........',
  'ttoo......obbbbbllllllbbbo........',
  '.ttbo.....obbbbcbbbbbbbbbo........',
  '..otbbo...obbbbbbbbbbbcbbo........',
  '...otbbbbbbbbbbbbobbbbbobbo.......',
  '....ooooooooobtbo....obtbo........',
  '.............ottto...ottto........',
]

// Ultimate form: a crown of horns, eyes opened even on the neck and belly, double-layered teeth, void-spread wings.
const ULTIMATE = [
  '..........................t.t.t.t.....',
  '..o......................tt.ttt.tt....',
  '.oxo....................tbbttbbbtbt...',
  '.ow.o..................obbbbbbbbbbbo..',
  'owx.do................obbeobbbcbbeeo..',
  'owwwwdo..............obbbbbbebbbbbbbo.',
  'ow.wxwdo.............obbbmmmmmmmmmmmto',
  'owwdw.wdo...........obbbtmtmtmtmtmto..',
  'owwdwwxwdo.........obbbmmmmmmmmmmo....',
  'owwxdww.wdo......ttobbbbtmtmtmtmo.....',
  'owwwdwwwxwdo...ttobbebboooooooo.......',
  'owwwdw.wwwwdo.ttobbbbco...............',
  '.owwwdwwxwwwdttobbcbbo................',
  '.owwwwd.wwwwdobbbbebbo................',
  '..owwwxwdwwwobbcbbbbbbo...............',
  '...owwwwdwxobbbbbxcbbbbo..............',
  '....owwwwwobbbblllcllllbbo............',
  '.....ooooobbbbbllellxllbbbo...........',
  'tttoo.....obbbbbllllllllbbbo..........',
  '.tttbo....obbbbcbbbbxbbbbbbbo.........',
  '..ottbbo..obbbbbbbbbbbbbcbbbo.........',
  '...otbbbbbbbbbbbbbbbobbbbbbobbo.......',
  '....oooooooooooobtbo.....obtbo........',
  '................ottto.....ottto.......',
]

const SHELL = { q: 0xf3e9d2, z: 0xd9705a }

export const STAGES: readonly Stage[] = [
  {
    from: 0,
    flavor: '따뜻하다. 안에서 무언가 꿈틀거린다.',
    tint: '#e8c8a8',
    sprite: EGG,
    palette: { o: 0x3a2418, b: 0, d: 0, l: 0, w: 0, e: 0, h: 0, t: 0, m: 0, ...SHELL, c: 0xff4030, x: 0 },
  },
  {
    from: 10,
    flavor: '삐약… 아니, 크앙?',
    tint: '#f4a58a',
    sprite: HATCHLING,
    palette: {
      o: 0x4a2a22, b: 0xf4a58a, d: 0xd9806a, l: 0xfde0c8, w: 0xf7c0a8, e: 0x2a1410, h: 0xffffff,
      t: 0xfff4e0, m: 0xb04040, ...SHELL, c: 0xff6040, x: 0,
    },
  },
  {
    from: 25,
    flavor: '작은 불씨를 뱉기 시작했다.',
    tint: '#ec7a5a',
    sprite: CHILD,
    palette: {
      o: 0x3e1e18, b: 0xec7a5a, d: 0xc85a40, l: 0xf8c8a0, w: 0xf09a7a, e: 0x301010, h: 0xffe0c0,
      t: 0xf4ead0, m: 0x902828, ...SHELL, c: 0xff5030, x: 0,
    },
  },
  {
    from: 40,
    flavor: '눈빛이 달라졌다.',
    tint: '#dc4a34',
    sprite: TEEN,
    palette: {
      o: 0x301410, b: 0xdc4a34, d: 0xac3022, l: 0xeea078, w: 0xc8503a, e: 0xffd040, h: 0xffd040,
      t: 0xe8dcc0, m: 0x601010, ...SHELL, c: 0xff4020, x: 0,
    },
  },
  {
    from: 55,
    flavor: '날개 그림자가 화면을 덮는다.',
    tint: '#c0282a',
    sprite: ADULT,
    palette: {
      o: 0x220a0a, b: 0xb8221e, d: 0x861414, l: 0xd0704c, w: 0x8e1a1a, e: 0xffb000, h: 0xfff080,
      t: 0xddd0b0, m: 0x3a0606, ...SHELL, c: 0xff3a10, x: 0x100000,
    },
  },
  {
    from: 70,
    flavor: '비늘 틈으로 붉은 빛이 샌다. 무언가 잘못됐다.',
    tint: '#a01020',
    sprite: ELDER,
    palette: {
      o: 0x160406, b: 0x8a0e14, d: 0x5c060c, l: 0xa43a2a, w: 0x5a0a10, e: 0xff3a10, h: 0xffd0a0,
      t: 0xc8b890, m: 0x200204, ...SHELL, c: 0xff4020, x: 0x0a0002,
    },
  },
  {
    from: 85,
    flavor: '눈이 너무 많다. 지금 압축하라.',
    tint: '#7a0010',
    sprite: ULTIMATE,
    palette: {
      o: 0x0a0002, b: 0x5e0410, d: 0x3a0208, l: 0x7a1a18, w: 0x2e0206, e: 0xffffff, h: 0xff2000,
      t: 0xb0a070, m: 0x000000, ...SHELL, c: 0xff2a10, x: 0x1a0004,
    },
  },
]

export const LAST_STAGE = STAGES.length - 1

/** Only the appearance changes per stage; there is a single name. */
export const DRAGON_NAME = '컨텍스트 드래곤'

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
