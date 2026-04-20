export type PersistSlot = "autosave" | "save_slot_1" | "save_slot_2" | "save_slot_3"

export type PersistProgress = {
  levelIndex: number
  rows: number
  cols: number
  runGold: number
  runManpowerBonus: number
}

export type PersistLibrary = {
  ownedUnitIds: string[]
  copies: Record<string, number>
}

export type PersistMeta = {
  prestige: number
  upgrades: Record<string, boolean>
}

export type PersistSave = {
  progress: PersistProgress
  library: PersistLibrary
  meta: PersistMeta
}

const PREFIX = "skzl_demo_"

export function loadSave(slot: PersistSlot): PersistSave | null {
  const raw = localStorage.getItem(PREFIX + slot)
  if (!raw) return null
  try {
    return JSON.parse(raw) as PersistSave
  } catch {
    return null
  }
}

export function saveSave(slot: PersistSlot, data: PersistSave) {
  localStorage.setItem(PREFIX + slot, JSON.stringify(data))
}

export function clearSave(slot: PersistSlot) {
  localStorage.removeItem(PREFIX + slot)
}

