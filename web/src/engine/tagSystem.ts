import type { BattleState, GridPoint, UnitData, UnitInstance } from "@/engine/types"

export type TagCtx = {
  battle: BattleState
  unit: UnitInstance
  unitData: UnitData
  getUnit: (instanceId: string) => UnitInstance | null
  getUnitData: (unitId: string) => UnitData
  rand: () => number
  findAllies: () => UnitInstance[]
  findEnemies: () => UnitInstance[]
  distance: (a: GridPoint, b: GridPoint) => number
  log: (text: string, tone?: "info" | "good" | "bad") => void
  heal: (target: UnitInstance, amount: number) => void
  damage: (target: UnitInstance, amount: number) => void
}

export type TagHooks = {
  onBattleStart?: (ctx: TagCtx) => void
  onAttackStart?: (ctx: TagCtx) => boolean
  modifyDamage?: (ctx: TagCtx, target: UnitInstance | null, damage: number) => number
  onPostAttack?: (ctx: TagCtx, target: UnitInstance | null) => void
  onAllyDied?: (ctx: TagCtx, ally: UnitInstance) => void
  onDeath?: (ctx: TagCtx) => void
}

export const tagHooks: Record<string, TagHooks> = {
  charge: {
    onBattleStart: ({ unit, unitData }) => {
      unit.tagState.charge = { stacks: Math.max(0, unitData.chargeCount | 0) }
    },
    modifyDamage: ({ unit, log }, _target, damage) => {
      const st = unit.tagState.charge as { stacks: number } | undefined
      if (!st || st.stacks <= 0) return damage
      log(`${unit.tagState._name ?? ""}触发冲锋`, "good")
      return damage * 2
    },
    onPostAttack: ({ unit }) => {
      const st = unit.tagState.charge as { stacks: number } | undefined
      if (!st || st.stacks <= 0) return
      st.stacks -= 1
    },
  },
  sniper: {
    modifyDamage: ({ unit, distance }, target, damage) => {
      if (!target) return damage
      const d = distance(unit.anchor, target.anchor)
      return Math.round(damage * (1 + 0.06 * d))
    },
  },
  medic: {
    onAttackStart: ({ battle, unit, unitData, findAllies, heal, log }) => {
      const allies = findAllies().filter((u) => u.alive)
      if (allies.length === 0) return true
      let best = allies[0]
      let bestRatio = best.hp / best.maxHp
      for (const a of allies) {
        const r = a.hp / a.maxHp
        if (r < bestRatio) {
          best = a
          bestRatio = r
        }
      }
      const amount = Math.max(8, Math.round(unitData.attackDamage))
      heal(best, amount)
      const cost = Math.max(0, unitData.manpowerCost)
      if (unit.faction === "friendly") battle.friendlyManpower = Math.max(0, battle.friendlyManpower - cost)
      else battle.enemyManpower = Math.max(0, battle.enemyManpower - cost)
      log(`${unitData.name} 治疗 ${amount}`, "good")
      return true
    },
  },
  last_stand: {
    onDeath: ({ unitData, findEnemies, damage, rand, log }) => {
      const enemies = findEnemies().filter((u) => u.alive)
      const amount = Math.round(unitData.attackDamage * 3)
      if (enemies.length > 0) {
        const i = Math.floor(rand() * enemies.length)
        damage(enemies[i], amount)
        log(`${unitData.name} 亡语造成 ${amount}`, "bad")
        return
      }
      log(`${unitData.name} 亡语无目标`, "info")
    },
  },
  sacrifice: {
    onAllyDied: ({ unit, log }) => {
      unit.cd = Math.max(200, Math.round(unit.cd * 0.7))
      log(`牺牲触发：冷却缩短`, "good")
    },
  },
  produce: {
    onAttackStart: () => true,
  },
}
