import type { Reward } from "@/engine/types"
import { unitById } from "@/data/units"
import { Gift, Coins, Expand, X } from "lucide-react"

export default function ResultModal(props: {
  open: boolean
  title: string
  detail: string
  rewards: Reward[] | null
  onPick: (r: Reward) => void
  onClose: () => void
}) {
  if (!props.open) return null
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center px-4">
      <div className="absolute inset-0 bg-black/70 backdrop-blur-sm" onClick={props.onClose} />
      <div className="relative w-full max-w-2xl overflow-hidden rounded-3xl border border-white/10 bg-[#0b0d10] shadow-[0_40px_120px_rgba(0,0,0,0.75)]">
        <div className="absolute inset-0 opacity-60 [background:radial-gradient(700px_400px_at_30%_15%,rgba(241,203,127,0.20),transparent_60%),radial-gradient(600px_360px_at_70%_80%,rgba(255,90,90,0.16),transparent_55%)]" />
        <div className="relative p-6">
          <div className="flex items-start justify-between gap-4">
            <div>
              <div className="font-display text-2xl tracking-wide text-zinc-50">{props.title}</div>
              <div className="mt-2 text-sm text-zinc-300">{props.detail}</div>
            </div>
            <button
              type="button"
              onClick={props.onClose}
              className="rounded-2xl border border-white/10 bg-white/5 p-2 text-zinc-200 hover:bg-white/10"
            >
              <X className="h-5 w-5" />
            </button>
          </div>

          {props.rewards ? (
            <div className="mt-6 grid gap-3 md:grid-cols-3">
              {props.rewards.map((r, idx) => (
                <button
                  key={`${r.kind}-${idx}`}
                  type="button"
                  onClick={() => props.onPick(r)}
                  className="group rounded-3xl border border-white/10 bg-white/[0.03] p-4 text-left hover:bg-white/[0.06]"
                >
                  <RewardView reward={r} />
                </button>
              ))}
            </div>
          ) : (
            <div className="mt-6 text-sm text-zinc-300">你可以重试或返回。</div>
          )}
        </div>
      </div>
    </div>
  )
}

function RewardView(props: { reward: Reward }) {
  if (props.reward.kind === "gold") {
    return (
      <div>
        <div className="flex items-center gap-2 text-sm text-amber-100">
          <Coins className="h-4 w-4" />
          军资 +{props.reward.amount}
        </div>
        <div className="mt-2 text-xs text-zinc-400">用于营地升级（Demo 仅展示数值）。</div>
      </div>
    )
  }
  if (props.reward.kind === "upgrade") {
    return (
      <div>
        <div className="flex items-center gap-2 text-sm text-emerald-100">
          <Expand className="h-4 w-4" />
          战线扩充 {props.reward.axis === "rows" ? "行" : "列"} +{props.reward.amount}
        </div>
        <div className="mt-2 text-xs text-zinc-400">让部署空间更大，容纳更多单位。</div>
      </div>
    )
  }
  const u = unitById[props.reward.unitId]
  return (
    <div>
      <div className="flex items-center gap-2 text-sm text-zinc-100">
        <Gift className="h-4 w-4 text-amber-200/90" />
        获得单位
      </div>
      <div className="mt-2 font-display text-base tracking-wide text-zinc-50">{u?.name ?? props.reward.unitId}</div>
      <div className="mt-1 text-xs text-zinc-400">x{props.reward.amount}</div>
    </div>
  )
}

