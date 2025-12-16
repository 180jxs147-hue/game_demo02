extends Node

# 民力变化 (当前值, 最大值)
signal manpower_changed(current: float, max_val: float)

# 单位死亡 (单位节点, 死亡时的X坐标)
signal unit_died(unit_node: Node2D, pos_x: float)
