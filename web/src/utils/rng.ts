export function pickWeighted<T>(items: Array<{ item: T; weight: number }>, r: number): T | null {
  let total = 0
  for (const it of items) total += Math.max(0, it.weight)
  if (total <= 0) return null
  let x = r * total
  for (const it of items) {
    x -= Math.max(0, it.weight)
    if (x <= 0) return it.item
  }
  return items[items.length - 1]?.item ?? null
}

export function shuffleInPlace<T>(arr: T[], rand: () => number) {
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1))
    const t = arr[i]
    arr[i] = arr[j]
    arr[j] = t
  }
  return arr
}

