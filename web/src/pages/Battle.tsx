import { useEffect, useMemo, useRef, useState } from "react"
import Frame from "@/components/Frame"
import HudBar from "@/components/HudBar"
import GridBoard from "@/components/GridBoard"
import CardSlot from "@/components/CardSlot"
import ResultModal from "@/components/ResultModal"
import { unitById } from "@/data/units"
import { tagText } from "@/data/tags"
import { useGameStore, saveAutosaveSnapshot } from "@/store/useGameStore"
import type { BattleState, GridPoint, Reward } from "@/engine/types"
import { canPlaceUnit, placeUnit, type Occupancy } from "@/engine/gridSystem"

type DragState = { unitId: string; x: number; y: number } | null
type DragPreview = { anchor: GridPoint; ok: boolean } | null

export default function Battle() {
  const init = useGameStore((s) => s.initFromAutosave)
  const progress = useGameStore((s) => s.progress)
  const library = useGameStore((s) => s.library)
  const placed = useGameStore((s) => s.placed)
  const battle = useGameStore((s) => s.battle)
  const rewards = useGameStore((s) => s.rewards)
  const logOpen = useGameStore((s) => s.logOpen)
  const toggleLog = useGameStore((s) => s.toggleLog)
  const placeFromBench = useGameStore((s) => s.placeFromBench)
  const removePlaced = useGameStore((s) => s.removePlaced)
  const clearPlaced = useGameStore((s) => s.clearPlaced)
  const startBattle = useGameStore((s) => s.startBattle)
  const tick = useGameStore((s) => s.tick)
  const setSpeed = useGameStore((s) => s.setSpeed)
  const pickReward = useGameStore((s) => s.pickReward)

  const cell = 56
  const cols = progress.cols
  const rows = progress.rows

  const [drag, setDrag] = useState<DragState>(null)
  const [preview, setPreview] = useState<DragPreview>(null)
  const boardRef = useRef<HTMLDivElement | null>(null)
  const dragUnitIdRef = useRef<string | null>(null)
  const rafRef = useRef<number | null>(null)
  const lastRef = useRef<number>(0)

  useEffect(() => {
    init()
  }, [init])

  useEffect(() => {
    saveAutosaveSnapshot()
  }, [progress, library])

  useEffect(() => {
    if (!battle?.started || battle.result !== "running") return
    lastRef.current = performance.now()
    const loop = (t: number) => {
      const dt = Math.min(50, Math.max(0, t - lastRef.current))
      lastRef.current = t
      tick(dt)
      rafRef.current = requestAnimationFrame(loop)
    }
    rafRef.current = requestAnimationFrame(loop)
    return () => {
      if (rafRef.current) cancelAnimationFrame(rafRef.current)
      rafRef.current = null
    }
  }, [battle?.started, battle?.result, tick])

  const occMemo = useMemo(() => {
    const occ: Occupancy = new Map()
    for (const p of placed) {
      const ud = unitById[p.unitId]
      if (!ud) continue
      placeUnit({ unit: ud, anchor: p.anchor, instanceId: p.slotId, occ })
    }
    return occ
  }, [placed])

  const computeAnchor = (clientX: number, clientY: number): GridPoint | null => {
    const el = boardRef.current
    if (!el) return null
    const rect = el.getBoundingClientRect()
    if (clientX < rect.left || clientX >= rect.right) return null
    if (clientY < rect.top || clientY >= rect.bottom) return null
    const x = Math.floor((clientX - rect.left) / cell)
    const y = Math.floor((clientY - rect.top) / cell)
    return { x, y }
  }

  useEffect(() => {
    const onMove = (e: PointerEvent) => {
      if (!dragUnitIdRef.current) return
      setDrag((d) => (d ? { ...d, x: e.clientX, y: e.clientY } : d))
      const anchor = computeAnchor(e.clientX, e.clientY)
      const unitId = dragUnitIdRef.current
      const u = unitId ? unitById[unitId] : undefined
      if (!anchor || !u) {
        setPreview(null)
        return
      }
      const ok = canPlaceUnit({ unit: u, anchor, cols, rows, occ: occMemo })
      setPreview({ anchor, ok })
    }
    const onUp = (e: PointerEvent) => {
      const unitId = dragUnitIdRef.current
      if (!unitId) return
      const anchor = computeAnchor(e.clientX, e.clientY)
      if (anchor) {
        placeFromBench(unitId, anchor)
      }
      dragUnitIdRef.current = null
      setPreview(null)
      setDrag(null)
    }
    window.addEventListener("pointermove", onMove)
    window.addEventListener("pointerup", onUp)
    return () => {
      window.removeEventListener("pointermove", onMove)
      window.removeEventListener("pointerup", onUp)
    }
  }, [cols, rows, occMemo, placeFromBench])

  const bench = useMemo(() => {
    const counts: Record<string, number> = { ...library.copies }
    for (const p of placed) counts[p.unitId] = (counts[p.unitId] ?? 0) - 1
    const list = Object.entries(counts)
      .filter(([, c]) => c > 0)
      .map(([unitId, c]) => ({ unitId, count: c }))
    list.sort((a, b) => (unitById[a.unitId]?.name ?? a.unitId).localeCompare(unitById[b.unitId]?.name ?? b.unitId))
    return list
  }, [library.copies, placed])

  const modal = useMemo(() => {
    if (!battle) return { open: false, title: "", detail: "" }
    if (battle.result === "running") return { open: false, title: "", detail: "" }
    if (battle.result === "victory") return { open: true, title: "胜利", detail: "战线推进成功。选择一项奖励继续推进。" }
    return { open: true, title: "失败", detail: "战线被击穿。你可以调整部署并重试。" }
  }, [battle])

  const rewardPick = (r: Reward) => pickReward(r)
  const closeResult = () => {
    if (!battle) return
    if (battle.result === "defeat") pickReward({ kind: "gold", amount: 0 })
  }

  return (
    <Frame title="战斗">
      <div className="grid gap-4">
        <HudBar battle={battle} logOpen={logOpen} onToggleLog={toggleLog} onSpeed={setSpeed} />

        <section className="grid gap-4 lg:grid-cols-[1fr_360px]">
          <div className="rounded-[28px] border border-white/10 bg-white/[0.03] p-4">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div className="text-sm text-zinc-300">拖拽卡牌到网格部署，点击“开始战斗”。</div>
              <div className="flex items-center gap-2">
                <button
                  type="button"
                  onClick={() => clearPlaced()}
                  disabled={battle?.started}
                  className="rounded-2xl border border-white/10 bg-white/5 px-3 py-2 text-sm text-zinc-100 hover:bg-white/10 disabled:opacity-40"
                >
                  清空部署
                </button>
                <button
                  type="button"
                  onClick={() => startBattle()}
                  disabled={battle?.started}
                  className="rounded-2xl bg-amber-200 px-4 py-2 text-sm font-semibold text-black hover:bg-amber-100 disabled:opacity-40"
                >
                  开始战斗
                </button>
              </div>
            </div>
            <div className="mt-4 flex items-start justify-center">
              <GridBoard
                cols={cols}
                rows={rows}
                cell={cell}
                placed={placed}
                battle={battle}
                boardRef={(el) => {
                  boardRef.current = el
                }}
                preview={
                  drag && preview && unitById[drag.unitId]
                    ? { unit: unitById[drag.unitId], anchor: preview.anchor, ok: preview.ok }
                    : null
                }
                onPieceClick={(slotId) => removePlaced(slotId)}
              />
            </div>
            {logOpen ? <BattleLog battle={battle} /> : null}
          </div>

          <aside className="rounded-[28px] border border-white/10 bg-white/[0.03] p-4">
            <div className="flex items-center justify-between gap-3">
              <div className="font-display tracking-wide text-zinc-50">备战区</div>
              <div className="text-xs text-zinc-500">可用卡牌 {bench.length}</div>
            </div>
            <div className="mt-4 grid gap-3">
              {bench.map((b) => {
                const data = unitById[b.unitId]
                if (!data) return null
                return (
                  <CardSlot
                    key={b.unitId}
                    data={data}
                    count={b.count}
                    disabled={battle?.started}
                    onPointerDown={(e) => {
                      if (battle?.started) return
                      dragUnitIdRef.current = b.unitId
                      setDrag({ unitId: b.unitId, x: e.clientX, y: e.clientY })
                    }}
                  />
                )
              })}
            </div>
            <div className="mt-6 rounded-2xl border border-white/10 bg-black/20 p-3">
              <div className="text-xs uppercase tracking-wider text-zinc-500">标签词条</div>
              <div className="mt-2 grid gap-2">
                {Object.entries(tagText).map(([k, v]) => (
                  <div key={k} className="text-sm text-zinc-200">
                    <span className="font-medium text-amber-100">{v.name}</span>
                    <span className="text-zinc-400"> · {v.description}</span>
                  </div>
                ))}
              </div>
            </div>
          </aside>
        </section>
      </div>

      <DragGhost drag={drag} />

      <ResultModal
        open={modal.open}
        title={modal.title}
        detail={modal.detail}
        rewards={battle?.result === "victory" ? rewards : null}
        onPick={rewardPick}
        onClose={closeResult}
      />
    </Frame>
  )
}

function DragGhost(props: { drag: DragState }) {
  if (!props.drag) return null
  const data = unitById[props.drag.unitId]
  if (!data) return null
  return (
    <div
      className="pointer-events-none fixed z-50 w-[260px] -translate-x-1/2 -translate-y-1/2 opacity-90"
      style={{ left: props.drag.x, top: props.drag.y }}
    >
      <CardSlot data={data} count={0} />
    </div>
  )
}

function BattleLog(props: { battle: BattleState | null }) {
  const logs = props.battle?.logs ?? []
  return (
    <div className="mt-4 rounded-2xl border border-white/10 bg-black/20">
      <div className="flex items-center justify-between px-4 py-3">
        <div className="font-display text-sm tracking-wide text-zinc-50">战斗日志</div>
        <div className="text-xs text-zinc-500">{logs.length}</div>
      </div>
      <div className="max-h-48 overflow-auto px-4 pb-4 text-sm">
        {logs.length === 0 ? (
          <div className="py-3 text-zinc-500">等待开战…</div>
        ) : (
          logs.slice(-60).map((l) => (
            <div
              key={l.id}
              className={[
                "py-1",
                l.tone === "good" ? "text-emerald-200/90" : l.tone === "bad" ? "text-rose-200/90" : "text-zinc-300",
              ].join(" ")}
            >
              {l.text}
            </div>
          ))
        )}
      </div>
    </div>
  )
}
