import type { BattleState, GridPoint, LevelConfig, UnitData, UnitInstance } from "@/engine/types"
import { tagHooks } from "@/engine/tagSystem"
import { uid } from "@/utils/id"

export function makeBattleState(args: {
  level: LevelConfig
  friendlyUnits: Array<{ unit: UnitData; anchor: GridPoint }>
  enemyUnits: Array<{ unit: UnitData; anchor: GridPoint }>
  friendlyMaxManpower: number
  enemyMaxManpower: number
}): BattleState {
  const units: UnitInstance[] = []
  for (const u of args.friendlyUnits) {
    const instanceId = uid("u")
    units.push({
      instanceId,
      unitId: u.unit.id,
      faction: "friendly",
      anchor: u.anchor,
      hp: u.unit.maxHp,
      maxHp: u.unit.maxHp,
      cd: Math.round(u.unit.cooldown * 1000),
      cdMax: Math.round(u.unit.cooldown * 1000),
      alive: true,
      tagState: { _name: u.unit.name },
    })
  }
  for (const u of args.enemyUnits) {
    const instanceId = uid("e")
    units.push({
      instanceId,
      unitId: u.unit.id,
      faction: "enemy",
      anchor: u.anchor,
      hp: u.unit.maxHp,
      maxHp: u.unit.maxHp,
      cd: Math.round(u.unit.cooldown * 1000),
      cdMax: Math.round(u.unit.cooldown * 1000),
      alive: true,
      tagState: { _name: u.unit.name },
    })
  }

  const battle: BattleState = {
    timeMs: 0,
    speed: 1,
    started: false,
    result: "running",
    friendlyManpower: 10,
    friendlyMaxManpower: args.friendlyMaxManpower,
    enemyManpower: 10,
    enemyMaxManpower: args.enemyMaxManpower,
    friendlyBaseHp: 220,
    enemyBaseHp: args.level.enemyBaseHp,
    units,
    logs: [],
  }

  return battle
}

export function startBattle(args: { battle: BattleState; unitById: (id: string) => UnitData }) {
  if (args.battle.started) return
  args.battle.started = true
  for (const u of args.battle.units) {
    if (!u.alive) continue
    const data = args.unitById(u.unitId)
    for (const tagId of data.tags) {
      const hooks = tagHooks[tagId]
      hooks?.onBattleStart?.(makeTagCtx(args.battle, u, data, args.unitById))
    }
  }
}

export function tickBattle(args: {
  battle: BattleState
  dtMs: number
  unitById: (id: string) => UnitData
  rand?: () => number
}) {
  const b = args.battle
  if (!b.started) return
  if (b.result !== "running") return
  const rand = args.rand ?? Math.random

  b.timeMs += args.dtMs

  const dt = Math.round(args.dtMs * b.speed)
  for (const u of b.units) {
    if (!u.alive) continue
    u.cd -= dt
    if (u.cd > 0) continue
    stepUnitAction(b, u, args.unitById, rand)
    if (b.result !== "running") return
  }
}

export function setSpeed(battle: BattleState, speed: 1 | 2 | 3) {
  battle.speed = speed
}

function stepUnitAction(b: BattleState, unit: UnitInstance, unitById: (id: string) => UnitData, rand: () => number) {
  const data = unitById(unit.unitId)

  const cost = data.manpowerCost
  if (cost > 0) {
    if (unit.faction === "friendly") {
      if (b.friendlyManpower < cost) {
        unit.cd = 350
        return
      }
      b.friendlyManpower = clamp(b.friendlyManpower - cost, 0, b.friendlyMaxManpower)
    } else {
      if (b.enemyManpower < cost) {
        unit.cd = 350
        return
      }
      b.enemyManpower = clamp(b.enemyManpower - cost, 0, b.enemyMaxManpower)
    }
  }

  const ctx = makeTagCtx(b, unit, data, unitById, rand)
  for (const tagId of data.tags) {
    const hooks = tagHooks[tagId]
    const handled = hooks?.onAttackStart?.(ctx) ?? false
    if (handled) {
      unit.cd = unit.cdMax
      if (cost < 0) applyProduce(b, unit, Math.abs(cost))
      checkEnd(b)
      return
    }
  }

  if (cost < 0) {
    applyProduce(b, unit, Math.abs(cost))
    unit.cd = unit.cdMax
    checkEnd(b)
    return
  }

  const target = findTarget(b, unit, rand)
  let dmg = Math.round(data.attackDamage)
  for (const tagId of data.tags) {
    const hooks = tagHooks[tagId]
    if (hooks?.modifyDamage) dmg = Math.round(hooks.modifyDamage(ctx, target, dmg))
  }
  dmg = Math.max(0, dmg)
  if (target) {
    const tData = unitById(target.unitId)
    const eff = Math.max(0, dmg - Math.round(tData.defense))
    ctx.damage(target, eff)
    ctx.log(`${data.name} 攻击 ${tData.name} -${eff}`, unit.faction === "friendly" ? "good" : "bad")
    if (!target.alive) triggerDeath(b, target, unitById, rand)
  } else {
    if (unit.faction === "friendly") {
      b.enemyBaseHp = Math.max(0, b.enemyBaseHp - dmg)
      ctx.log(`${data.name} 攻击敌方阵线 -${dmg}`, "good")
    } else {
      b.friendlyBaseHp = Math.max(0, b.friendlyBaseHp - dmg)
      ctx.log(`${data.name} 攻击我方阵线 -${dmg}`, "bad")
    }
  }

  for (const tagId of data.tags) {
    const hooks = tagHooks[tagId]
    hooks?.onPostAttack?.(ctx, target)
  }

  unit.cd = unit.cdMax
  checkEnd(b)
}

function applyProduce(b: BattleState, unit: UnitInstance, amount: number) {
  if (unit.faction === "friendly") b.friendlyManpower = clamp(b.friendlyManpower + amount, 0, b.friendlyMaxManpower)
  else b.enemyManpower = clamp(b.enemyManpower + amount, 0, b.enemyMaxManpower)
}

function findTarget(b: BattleState, unit: UnitInstance, rand: () => number) {
  const enemies = b.units.filter((u) => u.alive && u.faction !== unit.faction)
  if (enemies.length === 0) return null
  let best = enemies[0]
  let bestD = dist(unit.anchor, best.anchor)
  for (const e of enemies) {
    const d = dist(unit.anchor, e.anchor)
    if (d < bestD) {
      best = e
      bestD = d
    }
  }
  const ties = enemies.filter((e) => dist(unit.anchor, e.anchor) === bestD)
  if (ties.length <= 1) return best
  return ties[Math.floor(rand() * ties.length)]
}

function triggerDeath(b: BattleState, dead: UnitInstance, unitById: (id: string) => UnitData, rand: () => number) {
  if (dead.alive) return
  const deadData = unitById(dead.unitId)
  const ctx = makeTagCtx(b, dead, deadData, unitById, rand)
  for (const tagId of deadData.tags) {
    tagHooks[tagId]?.onDeath?.(ctx)
  }
  const allies = b.units.filter((u) => u.alive && u.faction === dead.faction && u.instanceId !== dead.instanceId)
  for (const a of allies) {
    const aData = unitById(a.unitId)
    const aCtx = makeTagCtx(b, a, aData, unitById, rand)
    for (const tagId of aData.tags) {
      tagHooks[tagId]?.onAllyDied?.(aCtx, dead)
    }
  }
}

function checkEnd(b: BattleState) {
  if (b.enemyBaseHp <= 0) {
    b.result = "victory"
    addLog(b, "敌方阵线崩溃：胜利", "good")
    return
  }
  if (b.friendlyBaseHp <= 0) {
    b.result = "defeat"
    addLog(b, "我方阵线崩溃：失败", "bad")
  }
}

function makeTagCtx(
  battle: BattleState,
  unit: UnitInstance,
  unitData: UnitData,
  getUnitData: (id: string) => UnitData,
  rand: () => number = Math.random,
) {
  return {
    battle,
    unit,
    unitData,
    getUnit: (instanceId: string) => battle.units.find((u) => u.instanceId === instanceId) ?? null,
    getUnitData,
    rand,
    findAllies: () => battle.units.filter((u) => u.alive && u.faction === unit.faction),
    findEnemies: () => battle.units.filter((u) => u.alive && u.faction !== unit.faction),
    distance: dist,
    log: (text: string, tone: "info" | "good" | "bad" = "info") => addLog(battle, text, tone),
    heal: (target: UnitInstance, amount: number) => {
      if (!target.alive) return
      target.hp = clamp(target.hp + amount, 0, target.maxHp)
    },
    damage: (target: UnitInstance, amount: number) => {
      if (!target.alive) return
      target.hp = Math.max(0, target.hp - amount)
      if (target.hp <= 0) target.alive = false
    },
  }
}

function addLog(b: BattleState, text: string, tone: "info" | "good" | "bad") {
  b.logs.push({ id: uid("log"), t: b.timeMs, text, tone })
  if (b.logs.length > 90) b.logs.splice(0, b.logs.length - 90)
}

function dist(a: GridPoint, b: GridPoint) {
  return Math.abs(a.x - b.x) + Math.abs(a.y - b.y)
}

function clamp(n: number, min: number, max: number) {
  return Math.min(max, Math.max(min, n))
}

