extends Node
## TurnManager — "just one more turn" pacing.
##
## * Every 5 piece drops = 1 Turn (shown as a pip bar).
## * The boss attacks when its own countdown (in drops) runs out; gear can
##   push that countdown back (DELAY_BOSS) and cards can lengthen it.
## * Every 3 turns a Tactical Draft offers 3 upgrade cards.

signal changed

const DROPS_PER_TURN := 5
const TURNS_PER_DRAFT := 3

var turn := 1
var drops_in_turn := 0
var total_drops := 0
var attack_interval := 6
var attack_countdown := 6
var bonus_interval := 0      # from cards


func reset(interval: int) -> void:
	turn = 1
	drops_in_turn = 0
	total_drops = 0
	bonus_interval = 0
	set_interval(interval)
	changed.emit()


func set_interval(interval: int) -> void:
	attack_interval = interval
	attack_countdown = interval + bonus_interval
	changed.emit()


## Call once per locked piece. Returns what happens next.
func register_drop() -> Dictionary:
	total_drops += 1
	drops_in_turn += 1
	attack_countdown -= 1
	var result := {"turn_end": false, "attack": false, "draft": false, "telegraph": false}
	if drops_in_turn >= DROPS_PER_TURN:
		drops_in_turn = 0
		result["turn_end"] = true
		result["draft"] = turn % TURNS_PER_DRAFT == 0
		turn += 1
	if attack_countdown <= 0:
		result["attack"] = true
		attack_countdown = attack_interval + bonus_interval
	elif attack_countdown == 1:
		result["telegraph"] = true
	changed.emit()
	return result


func delay_attack(drops: int) -> void:
	attack_countdown += drops
	changed.emit()
