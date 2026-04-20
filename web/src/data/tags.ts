export const tagText: Record<string, { name: string; description: string }> = {
  charge: { name: "冲锋", description: "前若干次攻击造成双倍伤害。" },
  sniper: { name: "狙击", description: "距离越远伤害越高（每格约 +6%）。" },
  medic: { name: "医者", description: "不进行攻击，改为治疗我方最虚弱单位。" },
  last_stand: { name: "亡语", description: "阵亡时对随机敌人造成 300% 伤害。" },
  sacrifice: { name: "牺牲", description: "队友阵亡时，冷却减少 30%（最低 0.2s）。" },
  produce: { name: "产出", description: "不攻击，持续产出民力。" },
}

