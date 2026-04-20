import { Gauge, ScrollText, Swords } from "lucide-react"
import type { BattleState } from "@/engine/types"

export default function HudBar(props: {
  battle: BattleState | null
  logOpen: boolean
  onToggleLog: () => void
  onSpeed: (s: 1 | 2 | 3) => void
}) {
  const b = props.battle
  return (
    <div className="flex flex-wrap items-center justify-between gap-3 rounded-3xl border border-white/10 bg-white/[0.03] px-4 py-3">
      <div className="flex items-center gap-3">
        <div className="flex items-center gap-2 text-sm text-zinc-200">
          <Swords className="h-4 w-4 text-amber-200/90" />
          <span className="font-display tracking-wide">战斗</span>
        </div>
        <div className="h-5 w-px bg-white/10" />
        <div className="text-xs text-zinc-400">{b?.started ? "进行中" : "部署阶段"}</div>
      </div>

      <div className="flex items-center gap-2">
        <StatPill
          label="我方民力"
          val={b ? `${b.friendlyManpower.toFixed(1)}/${b.friendlyMaxManpower.toFixed(0)}` : "--"}
          tone="good"
        />
        <StatPill
          label="敌方民力"
          val={b ? `${b.enemyManpower.toFixed(1)}/${b.enemyMaxManpower.toFixed(0)}` : "--"}
          tone="bad"
        />
        <div className="h-5 w-px bg-white/10" />
        <div className="flex items-center gap-1 rounded-2xl border border-white/10 bg-black/20 p-1">
          <button
            type="button"
            onClick={() => props.onSpeed(1)}
            className={speedBtn(b?.speed === 1)}
          >
            1×
          </button>
          <button
            type="button"
            onClick={() => props.onSpeed(2)}
            className={speedBtn(b?.speed === 2)}
          >
            2×
          </button>
          <button
            type="button"
            onClick={() => props.onSpeed(3)}
            className={speedBtn(b?.speed === 3)}
          >
            3×
          </button>
        </div>
        <button
          type="button"
          onClick={props.onToggleLog}
          className="inline-flex items-center gap-2 rounded-2xl border border-white/10 bg-white/5 px-3 py-2 text-sm text-zinc-100 hover:bg-white/10"
        >
          <ScrollText className="h-4 w-4" />
          {props.logOpen ? "收起日志" : "展开日志"}
        </button>
      </div>
    </div>
  )
}

function speedBtn(active: boolean) {
  return [
    "rounded-xl px-3 py-1.5 text-sm",
    active ? "bg-amber-200/15 text-amber-100" : "text-zinc-200 hover:bg-white/10",
  ].join(" ")
}

function StatPill(props: { label: string; val: string; tone: "good" | "bad" }) {
  const iconColor = props.tone === "good" ? "text-emerald-200/90" : "text-rose-200/90"
  return (
    <div className="flex items-center gap-2 rounded-2xl border border-white/10 bg-black/20 px-3 py-2">
      <Gauge className={`h-4 w-4 ${iconColor}`} />
      <div className="leading-tight">
        <div className="text-[10px] uppercase tracking-wider text-zinc-500">{props.label}</div>
        <div className="text-sm text-zinc-100">{props.val}</div>
      </div>
    </div>
  )
}

