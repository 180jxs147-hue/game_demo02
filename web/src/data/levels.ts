import type { LevelConfig } from "@/engine/types"

export const levels: LevelConfig[] = [
  {
    id: "demo_1",
    name: "黄巾初战",
    gridWidth: 6,
    gridHeight: 6,
    formationCols: 6,
    formationRows: 6,
    enemyPower: 50,
    enemyUnits: [
      { unitId: "huangjin_lishi", gridPos: { x: 4, y: 2 } },
      { unitId: "huangjin_lishi", gridPos: { x: 4, y: 3 } },
      { unitId: "archer", gridPos: { x: 5, y: 1 } },
    ],
  },
]
