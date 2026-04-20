import { Link } from "react-router-dom"
import { Sword, BookOpen, RotateCcw } from "lucide-react"
import { useGameStore } from "@/store/useGameStore"

export default function Frame(props: { title: string; children: React.ReactNode }) {
  const reset = useGameStore((s) => s.resetAutosave)
  return (
    <div className="min-h-dvh bg-[radial-gradient(1200px_800px_at_30%_20%,rgba(241,203,127,0.10),transparent_60%),radial-gradient(900px_600px_at_70%_70%,rgba(49,197,255,0.08),transparent_55%),linear-gradient(180deg,#0b0d10,#07080b_55%,#05060a)] text-zinc-100">
      <header className="mx-auto flex max-w-6xl items-center justify-between px-5 py-5">
        <div className="flex items-baseline gap-3">
          <div className="font-display text-xl tracking-wide text-zinc-50">{props.title}</div>
          <div className="text-xs text-zinc-400">Web Demo</div>
        </div>
        <nav className="flex items-center gap-2">
          <Link
            to="/battle"
            className="inline-flex items-center gap-2 rounded-xl border border-white/10 bg-white/5 px-3 py-2 text-sm text-zinc-100 hover:bg-white/10"
          >
            <Sword className="h-4 w-4" />
            试玩
          </Link>
          <Link
            to="/barracks"
            className="inline-flex items-center gap-2 rounded-xl border border-white/10 bg-white/5 px-3 py-2 text-sm text-zinc-100 hover:bg-white/10"
          >
            <BookOpen className="h-4 w-4" />
            图鉴
          </Link>
          <button
            onClick={reset}
            className="inline-flex items-center gap-2 rounded-xl border border-amber-200/10 bg-amber-200/5 px-3 py-2 text-sm text-amber-100 hover:bg-amber-200/10"
          >
            <RotateCcw className="h-4 w-4" />
            重置
          </button>
        </nav>
      </header>
      <main className="mx-auto max-w-6xl px-5 pb-10">{props.children}</main>
    </div>
  )
}

