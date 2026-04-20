import { create } from "zustand"
import type { BattleState, GridPoint, Reward } from "@/engine/types"
import { levels } from "@/data/levels"
import { unitById, units } from "@/data/units"
import { canPlaceUnit, placeUnit, type Occupancy } from "@/engine/gridSystem"
import { makeBattleState, setSpeed, startBattle, tickBattle } from "@/engine/battleEngine"
import { uid } from "@/utils/id"
import { loadSave, saveSave, type PersistSave } from "@/utils/persist"
import { pickWeighted, shuffleInPlace } from "@/utils/rng"

type PlacedUnit = { slotId: string; unitId: string; anchor: GridPoint }

type Progress = {
  levelIndex: number
  rows: number
  cols: number
  runGold: number
  runManpowerBonus: number
}

type Library = {
  ownedUnitIds: string[]
  copies: Record<string, number>
}

type GameState = {
  progress: Progress
  library: Library
  placed: PlacedUnit[]
  battle: BattleState | null
  rewards: Reward[] | null
  logOpen: boolean
  initFromAutosave: () => void
  resetAutosave: () => void
  toggleLog: () => void
  placeFromBench: (unitId: string, anchor: GridPoint) => { ok: boolean; reason?: string }
  removePlaced: (slotId: string) => void
  clearPlaced: () => void
  startBattle: () => { ok: boolean; reason?: string }
  tick: (dtMs: number) => void
  setSpeed: (speed: 1 | 2 | 3) => void
  pickReward: (reward: Reward) => void
}

const DEFAULT_SAVE: PersistSave = {
  progress: { levelIndex: 0, rows: 6, cols: 6, runGold: 10, runManpowerBonus: 0 },
  library: {
    ownedUnitIds: ["camp", "han_caiguan", "archer", "shield", "medic", "ezei_youqi", "last_stand"],
    copies: {
      camp: 1,
      han_caiguan: 2,
      archer: 1,
      shield: 1,
      medic: 1,
      ezei_youqi: 1,
      last_stand: 1,
    },
  },
  meta: { prestige: 0, upgrades: {} },
}

function clamp(n: number, min: number, max: number) {
  return Math.min(max, Math.max(min, n))
}

function countPlaced(placed: PlacedUnit[], unitId: string) {
  let c = 0
  for (const p of placed) if (p.unitId === unitId) c++
  return c
}

function remainingCopies(lib: Library, placed: PlacedUnit[], unitId: string) {
  const owned = lib.copies[unitId] ?? 0
  const used = countPlaced(placed, unitId)
  return owned - used
}

function buildOcc(cols: number, rows: number, placed: PlacedUnit[]) {
  const occ: Occupancy = new Map()
  for (const p of placed) {
    const ud = unitById[p.unitId]
    if (!ud) continue
    placeUnit({ unit: ud, anchor: p.anchor, instanceId: p.slotId, occ })
  }
  return { occ, cols, rows }
}

function generateRewards(args: { rand: () => number; library: Library }) {
  const rand = args.rand
  const weights = units.map((u) => ({ item: u.id, weight: rarityWeight(u.rarity) }))
  const unitId = pickWeighted(weights, rand()) ?? "han_caiguan"
  const base: Reward[] = [
    { kind: "unit", unitId, amount: 1 },
    { kind: "gold", amount: 3 },
    { kind: "upgrade", axis: rand() < 0.5 ? "rows" : "cols", amount: 1 },
  ]
  return shuffleInPlace(base, rand).slice(0, 3)
}

function rarityWeight(r: string) {
  if (r === "legendary") return 0.25
  if (r === "epic") return 0.5
  if (r === "rare") return 1
  if (r === "uncommon") return 1.6
  return 2.2
}

export const useGameStore = create<GameState>((set, get) => ({
  progress: DEFAULT_SAVE.progress,
  library: DEFAULT_SAVE.library,
  placed: [],
  battle: null,
  rewards: null,
  logOpen: true,
  initFromAutosave: () => {
    const existing = loadSave("autosave")
    const data = existing ?? DEFAULT_SAVE
    if (!existing) saveSave("autosave", data)
    set({
      progress: data.progress,
      library: data.library,
      placed: [],
      battle: null,
      rewards: null,
      logOpen: true,
    })
  },
  resetAutosave: () => {
    saveSave("autosave", DEFAULT_SAVE)
    get().initFromAutosave()
  },
  toggleLog: () => set((s) => ({ logOpen: !s.logOpen })),
  placeFromBench: (unitId, anchor) => {
    const s = get()
    const ud = unitById[unitId]
    if (!ud) return { ok: false, reason: "未知单位" }
    if (s.battle?.started) return { ok: false, reason: "战斗中无法部署" }
    if (remainingCopies(s.library, s.placed, unitId) <= 0) return { ok: false, reason: "没有可用卡牌" }
    const { occ, cols, rows } = buildOcc(s.progress.cols, s.progress.rows, s.placed)
    if (!canPlaceUnit({ unit: ud, anchor, cols, rows, occ })) return { ok: false, reason: "位置被占用或越界" }
    const slotId = uid("p")
    set((st) => ({ placed: [...st.placed, { slotId, unitId, anchor }] }))
    return { ok: true }
  },
  removePlaced: (slotId) => {
    const s = get()
    if (s.battle?.started) return
    set((st) => ({ placed: st.placed.filter((p) => p.slotId !== slotId) }))
  },
  clearPlaced: () => {
    const s = get()
    if (s.battle?.started) return
    set({ placed: [] })
  },
  startBattle: () => {
    const s = get()
    if (s.battle?.started) return { ok: false, reason: "战斗已开始" }
    const level = levels[clamp(s.progress.levelIndex, 0, levels.length - 1)]
    const friendlyUnits = s.placed.map((p) => ({ unit: unitById[p.unitId], anchor: p.anchor }))
    if (friendlyUnits.length === 0) return { ok: false, reason: "请先部署至少 1 个单位" }
    const enemyUnits = level.enemyUnits.map((e) => ({ unit: unitById[e.unitId], anchor: e.gridPos }))
    const friendlyMax = 50 + s.progress.runManpowerBonus
    const enemyMax = level.enemyPower
    const battle = makeBattleState({
      level,
      friendlyUnits,
      enemyUnits,
      friendlyMaxManpower: friendlyMax,
      enemyMaxManpower: enemyMax,
    })
    startBattle({ battle, unitById: (id) => unitById[id] })
    set({ battle, rewards: null })
    return { ok: true }
  },
  tick: (dtMs) => {
    const s = get()
    const b = s.battle
    if (!b) return
    if (!b.started || b.result !== "running") return
    tickBattle({ battle: b, dtMs, unitById: (id) => unitById[id] })
    if (b.result !== "running" && !s.rewards) {
      const rewards = b.result === "victory" ? generateRewards({ rand: Math.random, library: s.library }) : null
      set({ rewards })
    } else {
      set({ battle: b })
    }
  },
  setSpeed: (speed) => {
    const b = get().battle
    if (!b) return
    setSpeed(b, speed)
    set({ battle: b })
  },
  pickReward: (reward) => {
    const s = get()
    if (!s.battle) return
    if (s.battle.result !== "victory") {
      set({ battle: null, rewards: null })
      return
    }
    const nextProgress: Progress = { ...s.progress }
    const nextLibrary: Library = { ...s.library, copies: { ...s.library.copies }, ownedUnitIds: [...s.library.ownedUnitIds] }
    if (reward.kind === "gold") nextProgress.runGold += reward.amount
    if (reward.kind === "upgrade") {
      if (reward.axis === "rows") nextProgress.rows = clamp(nextProgress.rows + reward.amount, 3, 8)
      else nextProgress.cols = clamp(nextProgress.cols + reward.amount, 3, 8)
    }
    if (reward.kind === "unit") {
      nextLibrary.copies[reward.unitId] = (nextLibrary.copies[reward.unitId] ?? 0) + reward.amount
      if (!nextLibrary.ownedUnitIds.includes(reward.unitId)) nextLibrary.ownedUnitIds.push(reward.unitId)
    }
    const nextSave: PersistSave = { progress: nextProgress, library: nextLibrary, meta: { prestige: 0, upgrades: {} } }
    saveSave("autosave", nextSave)
    set({
      progress: nextProgress,
      library: nextLibrary,
      battle: null,
      rewards: null,
      placed: s.placed,
    })
  },
}))

export function saveAutosaveSnapshot() {
  const s = useGameStore.getState()
  const payload: PersistSave = { progress: s.progress, library: s.library, meta: { prestige: 0, upgrades: {} } }
  saveSave("autosave", payload)
}
