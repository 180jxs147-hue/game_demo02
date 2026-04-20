import { useEffect, useMemo, useState } from "react"
import Frame from "@/components/Frame"
import CardSlot from "@/components/CardSlot"
import { unitById, units } from "@/data/units"
import { useGameStore } from "@/store/useGameStore"

export default function Barracks() {
  const init = useGameStore((s) => s.initFromAutosave)
  const library = useGameStore((s) => s.library)
  const [selected, setSelected] = useState<string | null>(null)

  useEffect(() => {
    init()
  }, [init])

  const owned = useMemo(() => {
    const list = library.ownedUnitIds
      .map((id) => unitById[id])
      .filter(Boolean)
      .slice()
      .sort((a, b) => a.name.localeCompare(b.name))
    return list
  }, [library.ownedUnitIds])

  const data = selected ? unitById[selected] : owned[0]

  return (
    <Frame title="图鉴">
      <section className="grid gap-4 lg:grid-cols-[420px_1fr]">
        <div className="rounded-[28px] border border-white/10 bg-white/[0.03] p-4">
          <div className="font-display tracking-wide text-zinc-50">已拥有</div>
          <div className="mt-4 grid gap-3">
            {owned.map((u) => (
              <CardSlot
                key={u.id}
                data={u}
                count={library.copies[u.id] ?? 0}
                onClick={() => setSelected(u.id)}
              />
            ))}
          </div>
        </div>
        <div className="rounded-[28px] border border-white/10 bg-white/[0.03] p-6">
          {data ? (
            <div>
              <div className="font-display text-3xl tracking-wide text-zinc-50">{data.name}</div>
              <div className="mt-2 text-sm text-zinc-400">
                {data.civilization} · {data.unitClass} · {data.rarity}
              </div>
              <div className="mt-5 grid gap-3 md:grid-cols-3">
                <Info label="生命" value={`${Math.round(data.maxHp)}`} />
                <Info label="攻击" value={`${Math.round(data.attackDamage)}`} />
                <Info label="冷却" value={`${data.cooldown.toFixed(1)}s`} />
                <Info label="防御" value={`${Math.round(data.defense)}`} />
                <Info label="射程" value={`${data.attackRange}`} />
                <Info label="民力" value={`${data.manpowerCost.toFixed(1)}`} />
              </div>
              <div className="mt-6 rounded-2xl border border-white/10 bg-black/20 p-4 text-sm leading-6 text-zinc-300">
                {data.story || "暂无简介"}
              </div>
            </div>
          ) : (
            <div className="text-zinc-400">暂无单位。</div>
          )}
          <div className="mt-6 text-xs text-zinc-500">
            Demo 数据来自 Web 侧的最小集（后续可从 Godot Resources 自动转换）。
          </div>
        </div>
      </section>
      <div className="mt-6 rounded-[28px] border border-white/10 bg-white/[0.03] p-6">
        <div className="text-xs uppercase tracking-wider text-zinc-500">全部单位（MVP）</div>
        <div className="mt-4 grid gap-3 md:grid-cols-2 lg:grid-cols-3">
          {units.map((u) => (
            <CardSlot key={u.id} data={u} count={library.copies[u.id] ?? 0} onClick={() => setSelected(u.id)} />
          ))}
        </div>
      </div>
    </Frame>
  )
}

function Info(props: { label: string; value: string }) {
  return (
    <div className="rounded-2xl border border-white/10 bg-black/20 px-4 py-3">
      <div className="text-[10px] uppercase tracking-wider text-zinc-500">{props.label}</div>
      <div className="mt-1 font-display tracking-wide text-zinc-50">{props.value}</div>
    </div>
  )
}

