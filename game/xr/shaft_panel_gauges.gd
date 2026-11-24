class_name ShaftPanelGauges
extends RefCounted

## What a shaft changes, as gauges drawn beside the other shafts' (#1320,
## RUN-2, GFX-2): one per entry of `ShaftPanelShapes.gauges`, each read from
## the modifiers `ShaftPanelModel` already reads, never from the run.
##
## - `robots`: the shaft's `risk.robot_count` multiplier;
## - `alarm`: its `risk.alarm` multiplier;
## - `finds`: the mean component tier of its `reward.tier_weights`, 1..3, so
##   weight moved to rarer tiers lengthens the gauge.
##
## A gauge's fill is its value placed on the gauge's own `min`..`max` and held
## within 0..1, so the same value fills the same length on every shaft.


## The gauges of a shaft with `risk` ({"robot_count", "alarm"}) and tier
## `weights`, worded with the panel's `look`: [{"label", "fill", "mark",
## "value_text", "color"}] in `shapes.gauges` order.
static func for_shaft(shapes: ShaftPanelShapes, risk: Dictionary, weights: Array, look: Dictionary) -> Array[Dictionary]:
	var shown: Array[Dictionary] = []
	for gauge: Dictionary in shapes.gauges:
		var value: float = value_of(gauge["source"], risk, weights)
		var text: String = ShaftPanelLook.reward_text(look, weights) if gauge["source"] == "finds" \
			else "x%.1f" % value
		shown.append({"label": gauge["label"], "fill": fill(gauge, value), "mark": fill(gauge, gauge["mark"]),
			"value_text": text, "color": gauge["color"]})
	return shown


static func value_of(source: String, risk: Dictionary, weights: Array) -> float:
	match source:
		"robots":
			return float(risk.get("robot_count", 1.0))
		"alarm":
			return float(risk.get("alarm", 1.0))
	return mean_tier(weights)


## The weighted mean of tiers 1..n; tier 1 when every weight is 0.
static func mean_tier(weights: Array) -> float:
	var total: float = 0.0
	var sum: float = 0.0
	for i: int in weights.size():
		total += float(weights[i])
		sum += float(weights[i]) * float(i + 1)
	return sum / total if total > 0.0 else 1.0


static func fill(gauge: Dictionary, value: float) -> float:
	return clampf((value - float(gauge["min"])) / (float(gauge["max"]) - float(gauge["min"])), 0.0, 1.0)
