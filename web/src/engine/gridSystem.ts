import type { GridPoint, UnitData } from "@/engine/types"

export function shapeCells(anchor: GridPoint, shape: GridPoint[]) {
  return shape.map((p) => ({ x: anchor.x + p.x, y: anchor.y + p.y }))
}

export function bboxForShape(shape: GridPoint[]) {
  let minX = 0
  let minY = 0
  let maxX = 0
  let maxY = 0
  for (const p of shape) {
    minX = Math.min(minX, p.x)
    minY = Math.min(minY, p.y)
    maxX = Math.max(maxX, p.x)
    maxY = Math.max(maxY, p.y)
  }
  return { minX, minY, maxX, maxY, w: maxX - minX + 1, h: maxY - minY + 1 }
}

export type Occupancy = Map<string, string>

export function keyOfCell(p: GridPoint) {
  return `${p.x},${p.y}`
}

export function canPlaceUnit(args: {
  unit: UnitData
  anchor: GridPoint
  cols: number
  rows: number
  occ: Occupancy
}) {
  const cells = shapeCells(args.anchor, args.unit.gridShape)
  for (const c of cells) {
    if (c.x < 0 || c.x >= args.cols) return false
    if (c.y < 0 || c.y >= args.rows) return false
    if (args.occ.has(keyOfCell(c))) return false
  }
  return true
}

export function placeUnit(args: { unit: UnitData; anchor: GridPoint; instanceId: string; occ: Occupancy }) {
  const cells = shapeCells(args.anchor, args.unit.gridShape)
  for (const c of cells) args.occ.set(keyOfCell(c), args.instanceId)
}

export function clearUnit(args: { unit: UnitData; anchor: GridPoint; occ: Occupancy }) {
  const cells = shapeCells(args.anchor, args.unit.gridShape)
  for (const c of cells) args.occ.delete(keyOfCell(c))
}

