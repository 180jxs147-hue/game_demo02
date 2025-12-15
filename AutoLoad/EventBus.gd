# EventBus.gd
extends Node

# 信号：民力发生变化 (当前值, 最大值)
signal manpower_changed(current, max_value)

# 信号：请求消耗民力 (如果成功返回true，这里用信号通知结果比较复杂，我们稍后在Manager里用函数直接调用)

# 信号：单位死亡 (谁死了, 在什么位置)
signal unit_died(unit_node, position_x)

# 信号：战线位置更新 (当前的X坐标)
signal battle_line_moved(new_x)
