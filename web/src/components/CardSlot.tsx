import { tagText } from "@/data/tags"
import type { UnitData } from "@/engine/types"

export default function CardSlot(props: {
  data: UnitData
  count?: number
  disabled?: boolean
  onPointerDown?: (e: React.PointerEvent) => void
  onClick?: () => void
}) {
  const count = props.count ?? 0
  const disabled = props.disabled ?? false
  const tags = props.data.tags.slice(0, 3).map((t) => tagText[t]?.name ?? t)
  const cost = props.data.manpowerCost
  return (
    <button
      type="button"
      disabled={disabled}
      onPointerDown={props.onPointerDown}
      onClick={props.onClick}
      className={[
        "group relative w-full select-none overflow-hidden rounded-2xl border text-left",
        "border-white/10 bg-white/[0.04] hover:bg-white/[0.06] active:bg-white/[0.08]",
        "disabled:opacity-40 disabled:hover:bg-white/[0.04]",
      ].join(" ")}
      style={{ borderColor: "rgba(255,255,255,0.10)" }}
    >
      <div className="absolute inset-0 opacity-40" style={{ background: `radial-gradient(120px 80px at 30% 20%, ${props.data.color}55, transparent 70%)` }} />
      <div className="relative p-3">
        <div className="flex items-start justify-between gap-3">
          <div>
            <div className="font-display text-sm tracking-wide text-zinc-50">{props.data.name}</div>
            <div className="mt-0.5 text-[11px] text-zinc-400">
              {props.data.civilization} · {props.data.unitClass}
            </div>
          </div>
          <div className="flex flex-col items-end gap-1">
            <div className="rounded-lg border border-white/10 bg-black/20 px-2 py-1 text-xs text-zinc-100">
              {cost < 0 ? `产出 ${Math.abs(cost).toFixed(1)}` : `消耗 ${cost.toFixed(1)}`}
            </div>
            {count > 0 ? <div className="text-xs text-amber-100">x{count}</div> : null}
          </div>
        </div>
        <div className="mt-3 grid grid-cols-3 gap-2 text-xs">
          <Stat label="HP" val={Math.round(props.data.maxHp)} />
          <Stat label="ATK" val={Math.round(props.data.attackDamage)} />
          <Stat label="CD" val={`${props.data.cooldown.toFixed(1)}s`} />
        </div>
        {tags.length > 0 ? (
          <div className="mt-3 flex flex-wrap gap-1.5">
            {tags.map((t) => (
              <span key={t} className="rounded-full border border-white/10 bg-white/5 px-2 py-0.5 text-[11px] text-zinc-200">
                {t}
              </span>
            ))}
          </div>
        ) : null}
      </div>
    </button>
  )
}

function Stat(props: { label: string; val: string | number }) {
  return (
    <div className="rounded-xl border border-white/10 bg-black/[0.15] px-2 py-1.5">
      <div className="text-[10px] uppercase tracking-wider text-zinc-500">{props.label}</div>
      <div className="mt-0.5 font-medium text-zinc-100">{props.val}</div>
    </div>
  )
}
