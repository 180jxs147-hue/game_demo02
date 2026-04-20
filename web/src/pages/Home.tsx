import { useEffect } from "react"
import { Link } from "react-router-dom"
import { ArrowRight, Shield, Sparkles, Swords } from "lucide-react"
import Frame from "@/components/Frame"
import { useGameStore } from "@/store/useGameStore"

export default function Home() {
  const init = useGameStore((s) => s.initFromAutosave)
  const progress = useGameStore((s) => s.progress)
  const library = useGameStore((s) => s.library)

  useEffect(() => {
    init()
  }, [init])

  return (
    <Frame title="时空阵线">
      <section className="grid gap-6 md:grid-cols-[1.1fr_0.9fr]">
        <div className="relative overflow-hidden rounded-[28px] border border-white/10 bg-white/[0.03] p-6">
          <div className="absolute inset-0 opacity-70 [background:radial-gradient(900px_500px_at_25%_15%,rgba(241,203,127,0.20),transparent_60%),radial-gradient(700px_420px_at_70%_90%,rgba(49,197,255,0.12),transparent_55%)]" />
          <div className="relative">
            <div className="inline-flex items-center gap-2 rounded-full border border-amber-200/15 bg-amber-200/10 px-3 py-1 text-xs text-amber-100">
              <Sparkles className="h-4 w-4" />
              浏览器可试玩 Demo（移植版）
            </div>
            <h1 className="mt-4 font-display text-4xl leading-[1.05] tracking-wide text-zinc-50">
              部署你的战线
              <br />
              让时间替你出刀
            </h1>
            <p className="mt-4 max-w-prose text-sm leading-6 text-zinc-300">
              这是对原 Godot 版本核心循环的 Web 化复刻：从备战区拖拽部署到网格，点击开始后自动战斗，
              通过民力与冷却的节奏赢下战线。
            </p>
            <div className="mt-6 flex flex-wrap items-center gap-3">
              <Link
                to="/battle"
                className="inline-flex items-center gap-2 rounded-2xl bg-amber-200 px-4 py-3 text-sm font-semibold text-black hover:bg-amber-100"
              >
                <Swords className="h-4 w-4" />
                开始试玩
                <ArrowRight className="h-4 w-4" />
              </Link>
              <Link
                to="/barracks"
                className="inline-flex items-center gap-2 rounded-2xl border border-white/10 bg-white/5 px-4 py-3 text-sm text-zinc-100 hover:bg-white/10"
              >
                <Shield className="h-4 w-4" />
                查看图鉴
              </Link>
            </div>
          </div>
        </div>

        <div className="rounded-[28px] border border-white/10 bg-white/[0.03] p-6">
          <div className="text-xs uppercase tracking-wider text-zinc-500">试玩存档</div>
          <div className="mt-3 grid gap-3">
            <InfoRow label="关卡索引" value={`${progress.levelIndex}`} />
            <InfoRow label="战线尺寸" value={`${progress.cols}×${progress.rows}`} />
            <InfoRow label="军资" value={`${progress.runGold}`} />
            <InfoRow label="拥有单位" value={`${library.ownedUnitIds.length}`} />
          </div>
          <div className="mt-5 text-xs leading-5 text-zinc-400">
            已自动保存到本地浏览器（autosave）。点击右上角“重置”可恢复默认试玩档。
          </div>
        </div>
      </section>
    </Frame>
  )
}

function InfoRow(props: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between rounded-2xl border border-white/10 bg-black/20 px-4 py-3">
      <div className="text-sm text-zinc-300">{props.label}</div>
      <div className="font-display tracking-wide text-zinc-50">{props.value}</div>
    </div>
  )
}
