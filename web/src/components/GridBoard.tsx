import { bboxForShape, shapeCells } from "@/engine/gridSystem"
import type { BattleState, GridPoint, UnitData } from "@/engine/types"
import { unitById } from "@/data/units"

type Placed = { slotId: string; unitId: string; anchor: GridPoint }

export default function GridBoard(props: {
  cols: number
  rows: number
  cell: number
  placed: Placed[]
  battle: BattleState | null
  onBoardPointerUp?: (p: GridPoint) => void
  onPieceClick?: (slotId: string) => void
}) {
  const w = props.cols * props.cell
  const h = props.rows * props.cell

  const pieces = props.battle
    ? props.battle.units
        .filter((u) => u.alive)
        .map((u) => ({
          key: u.instanceId,
          slotId: u.instanceId,
          unit: unitById[u.unitId],
          anchor: u.anchor,
          faction: u.faction,
          hp: u.hp,
          maxHp: u.maxHp,
          clickable: false,
        }))
    : props.placed.map((p) => ({
        key: p.slotId,
        slotId: p.slotId,
        unit: unitById[p.unitId],
        anchor: p.anchor,
        faction: "friendly" as const,
        hp: 1,
        maxHp: 1,
        clickable: true,
      }))

  return (
    <div className="relative select-none">
      <div
        className="relative overflow-hidden rounded-3xl border border-white/10 bg-black/20"
        style={{ width: w, height: h }}
        onPointerUp={(e) => {
          if (!props.onBoardPointerUp) return
          const rect = (e.currentTarget as HTMLDivElement).getBoundingClientRect()
          const x = Math.floor((e.clientX - rect.left) / props.cell)
          const y = Math.floor((e.clientY - rect.top) / props.cell)
          props.onBoardPointerUp({ x, y })
        }}
      >
        <GridLines cols={props.cols} rows={props.rows} cell={props.cell} />
        <div className="absolute inset-0">
          {pieces.map((p) => (
            <UnitPiece
              key={p.key}
              unit={p.unit}
              anchor={p.anchor}
              cell={props.cell}
              faction={p.faction}
              hp={p.hp}
              maxHp={p.maxHp}
              onClick={p.clickable ? () => props.onPieceClick?.(p.slotId) : undefined}
            />
          ))}
        </div>
      </div>
      <div className="mt-2 flex items-center justify-between text-xs text-zinc-400">
        <div>部署区 {props.cols}×{props.rows}</div>
        <div className="text-zinc-500">点击已部署单位可撤回（开战前）</div>
      </div>
    </div>
  )
}

function GridLines(props: { cols: number; rows: number; cell: number }) {
  const cols = Array.from({ length: props.cols }, (_, i) => i)
  const rows = Array.from({ length: props.rows }, (_, i) => i)
  return (
    <div className="absolute inset-0">
      {cols.map((c) => (
        <div
          key={`c${c}`}
          className="absolute top-0 h-full w-px bg-white/5"
          style={{ left: c * props.cell }}
        />
      ))}
      {rows.map((r) => (
        <div
          key={`r${r}`}
          className="absolute left-0 w-full h-px bg-white/5"
          style={{ top: r * props.cell }}
        />
      ))}
    </div>
  )
}

function UnitPiece(props: {
  unit: UnitData | undefined
  anchor: GridPoint
  cell: number
  faction: "friendly" | "enemy"
  hp: number
  maxHp: number
  onClick?: () => void
}) {
  if (!props.unit) return null
  const bb = bboxForShape(props.unit.gridShape)
  const left = props.anchor.x * props.cell
  const top = props.anchor.y * props.cell
  const w = bb.w * props.cell
  const h = bb.h * props.cell
  const hpP = props.maxHp > 0 ? Math.max(0, Math.min(1, props.hp / props.maxHp)) : 1
  const cells = shapeCells(props.anchor, props.unit.gridShape)
  const outline = props.faction === "friendly" ? "rgba(241,203,127,0.55)" : "rgba(255,90,90,0.55)"

  return (
    <button
      type="button"
      onClick={props.onClick}
      className={[
        "absolute rounded-2xl border",
        props.onClick ? "cursor-pointer hover:bg-white/5" : "cursor-default",
      ].join(" ")}
      style={{
        left,
        top,
        width: w,
        height: h,
        borderColor: outline,
        background: "rgba(0,0,0,0.20)",
      }}
    >
      <div className="absolute inset-0">
        {cells.map((c, i) => (
          <div
            key={`${c.x},${c.y},${i}`}
            className="absolute rounded-xl"
            style={{
              left: (c.x - props.anchor.x) * props.cell + 4,
              top: (c.y - props.anchor.y) * props.cell + 4,
              width: props.cell - 8,
              height: props.cell - 8,
              background: `radial-gradient(80px 60px at 30% 25%, ${props.unit.color}aa, rgba(0,0,0,0.25) 70%)`,
              border: "1px solid rgba(255,255,255,0.08)",
            }}
          />
        ))}
      </div>
      <div className="absolute left-2 top-2 rounded-lg border border-white/10 bg-black/35 px-2 py-1 text-[11px] text-zinc-100">
        {props.unit.name}
      </div>
      {props.maxHp > 1 ? (
        <div className="absolute bottom-2 left-2 right-2 h-2 overflow-hidden rounded-full border border-white/10 bg-black/35">
          <div
            className="h-full"
            style={{
              width: `${Math.round(hpP * 100)}%`,
              background: props.faction === "friendly" ? "linear-gradient(90deg,#2dd4bf,#22c55e)" : "linear-gradient(90deg,#fb7185,#f97316)",
            }}
          />
        </div>
      ) : null}
    </button>
  )
}

