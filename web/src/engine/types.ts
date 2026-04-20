export type Rarity = "common" | "uncommon" | "rare" | "epic" | "legendary"

export type Faction = "friendly" | "enemy"

export type GridPoint = { x: number; y: number }

export type UnitData = {
  id: string
  name: string
  rarity: Rarity
  civilization: string
  unitClass: string
  color: string
  tags: string[]
  gridShape: GridPoint[]
  maxHp: number
  manpowerCost: number
  cooldown: number
  attackDamage: number
  defense: number
  attackRange: number
  chargeCount: number
  story: string
}

export type UnitInstance = {
  instanceId: string
  unitId: string
  faction: Faction
  anchor: GridPoint
  hp: number
  maxHp: number
  cd: number
  cdMax: number
  alive: boolean
  tagState: Record<string, unknown>
}

export type LevelConfig = {
  id: string
  name: string
  gridWidth: number
  gridHeight: number
  formationCols: number
  formationRows: number
  enemyPower: number
  enemyUnits: { unitId: string; gridPos: GridPoint }[]
}

export type Reward =
  | { kind: "unit"; unitId: string; amount: number }
  | { kind: "gold"; amount: number }
  | { kind: "upgrade"; axis: "rows" | "cols"; amount: number }

export type BattleResult = "running" | "victory" | "defeat"

export type BattleState = {
  timeMs: number
  speed: 1 | 2 | 3
  started: boolean
  result: BattleResult
  friendlyManpower: number
  friendlyMaxManpower: number
  enemyManpower: number
  enemyMaxManpower: number
  units: UnitInstance[]
  logs: { id: string; t: number; text: string; tone: "info" | "good" | "bad" }[]
}
