extends Node
## GearDatabase — 150 gameplay-altering items built from data, not scripts.
##
## Every item = Slot (Head / Face / Hand) + Silhouette (10 per slot) +
## Palette (5 materials) + one Trigger (10) + one Effect (15).
## The 10 x 15 = 150 trigger/effect combinations are each used exactly once,
## shuffled deterministically across the three slots, so every item plays
## differently. Rarity is derived from how strong the effect is and how often
## its trigger fires.

enum Slot { HEAD, FACE, HAND }
enum Rarity { COMMON, RARE, EPIC, LEGENDARY }

const SLOT_KEYS := ["head", "face", "hand"]
const SLOT_NAMES := ["Head", "Face", "Hand"]

const TRIGGERS := [
	"ON_POP_RED", "ON_POP_BLUE", "ON_POP_GREEN_YELLOW", "ON_COMBO_4_PLUS", "ON_CASCADE_2_PLUS",
	"ON_TURN_END", "ON_GARBAGE_LAND", "ON_DANGER_ZONE", "ON_MULTI_ROTATE", "ON_HARD_DROP",
]
const TRIGGER_TEXT := {
	"ON_POP_RED": "Pop Red blocks",
	"ON_POP_BLUE": "Pop Blue blocks",
	"ON_POP_GREEN_YELLOW": "Pop Green or Yellow blocks",
	"ON_COMBO_4_PLUS": "Clear 4+ blocks at once",
	"ON_CASCADE_2_PLUS": "Hit a 2x+ chain reaction",
	"ON_TURN_END": "Every turn end (5 drops)",
	"ON_GARBAGE_LAND": "Boss drops garbage on you",
	"ON_DANGER_ZONE": "Board goes over 75% full",
	"ON_MULTI_ROTATE": "Rotate a piece 3+ times",
	"ON_HARD_DROP": "Hard-drop a piece",
}
const TRIGGER_BADGE := {
	"ON_POP_RED": "RED", "ON_POP_BLUE": "BLUE", "ON_POP_GREEN_YELLOW": "G/Y", "ON_COMBO_4_PLUS": "4+",
	"ON_CASCADE_2_PLUS": "CHAIN", "ON_TURN_END": "TURN", "ON_GARBAGE_LAND": "JUNK", "ON_DANGER_ZONE": "DANGER",
	"ON_MULTI_ROTATE": "SPIN", "ON_HARD_DROP": "SLAM",
}
const TRIGGER_COLOR := {
	"ON_POP_RED": Color("ff4d6d"), "ON_POP_BLUE": Color("3fa9ff"), "ON_POP_GREEN_YELLOW": Color("9bd93f"),
	"ON_COMBO_4_PLUS": Color("ff9f1c"), "ON_CASCADE_2_PLUS": Color("2ee6d6"), "ON_TURN_END": Color("8a8fff"),
	"ON_GARBAGE_LAND": Color("9a8f86"), "ON_DANGER_ZONE": Color("ff3355"), "ON_MULTI_ROTATE": Color("ff6fb5"),
	"ON_HARD_DROP": Color("ffd23f"),
}
## How often each trigger tends to fire (higher = more often = lower rarity).
const TRIGGER_FREQ := {
	"ON_POP_RED": 3, "ON_POP_BLUE": 3, "ON_POP_GREEN_YELLOW": 4, "ON_COMBO_4_PLUS": 2, "ON_CASCADE_2_PLUS": 1,
	"ON_TURN_END": 3, "ON_GARBAGE_LAND": 1, "ON_DANGER_ZONE": 0, "ON_MULTI_ROTATE": 2, "ON_HARD_DROP": 4,
}

const EFFECTS := [
	"ZAP_BOTTOM_ROW", "COLOR_CONVERT", "CRUSH_GARBAGE", "SLOW_GRAVITY", "DELAY_BOSS",
	"SPAWN_GEMS", "BOOST_MULTIPLIER", "SPAWN_BOMB", "NEXT_WILDCARD", "STUN_BOSS",
	"CLEAR_COLUMN_EDGE", "SHIELD_BLOCK", "TWIN_POP", "HEAL_OVERFLOW", "MEGA_STRIKE",
]
const EFFECT_TEXT := {
	"ZAP_BOTTOM_ROW": "Zap %d random bottom-row block(s)",
	"COLOR_CONVERT": "Turn %d block(s) into your most common color",
	"CRUSH_GARBAGE": "Crush %d garbage block(s)",
	"SLOW_GRAVITY": "Slow gravity 25%% for %d seconds",
	"DELAY_BOSS": "Delay the boss attack by +%d drop(s)",
	"SPAWN_GEMS": "Mine +%d bonus Gem(s) (max once per turn)",
	"BOOST_MULTIPLIER": "+%s x combo damage multiplier",
	"SPAWN_BOMB": "Turn %d block(s) into a 3x3 Bomb",
	"NEXT_WILDCARD": "Next %d piece(s) carry a Rainbow Wildcard",
	"STUN_BOSS": "Stun the boss (skips next attack)",
	"CLEAR_COLUMN_EDGE": "Destroy %d block(s) on the outer columns",
	"SHIELD_BLOCK": "Turn %d block(s) into a garbage Shield",
	"TWIN_POP": "Pop %d extra matching block(s)",
	"HEAL_OVERFLOW": "Clear %d block(s) from the top hazard zone",
	"MEGA_STRIKE": "Launch a Mega Strike for %d boss damage",
}
const EFFECT_SHORT := {
	"ZAP_BOTTOM_ROW": "ZAP!", "COLOR_CONVERT": "RECOLOR!", "CRUSH_GARBAGE": "CRUSH!", "SLOW_GRAVITY": "SLOW-MO!",
	"DELAY_BOSS": "DELAY!", "SPAWN_GEMS": "GEMS!", "BOOST_MULTIPLIER": "BOOST!", "SPAWN_BOMB": "BOMB!",
	"NEXT_WILDCARD": "WILD!", "STUN_BOSS": "STUN!", "CLEAR_COLUMN_EDGE": "EDGE CLEAR!", "SHIELD_BLOCK": "SHIELD!",
	"TWIN_POP": "TWIN POP!", "HEAL_OVERFLOW": "BREATHE!", "MEGA_STRIKE": "MEGA STRIKE!",
}
const EFFECT_ICON := {
	"ZAP_BOTTOM_ROW": "⚡", "COLOR_CONVERT": "◐", "CRUSH_GARBAGE": "✖", "SLOW_GRAVITY": "◷", "DELAY_BOSS": "⏸",
	"SPAWN_GEMS": "◆", "BOOST_MULTIPLIER": "×", "SPAWN_BOMB": "✹", "NEXT_WILDCARD": "✦", "STUN_BOSS": "★",
	"CLEAR_COLUMN_EDGE": "▮", "SHIELD_BLOCK": "⛨", "TWIN_POP": "❖", "HEAL_OVERFLOW": "▲", "MEGA_STRIKE": "✷",
}
## Effect strength (higher = rarer).
const EFFECT_POWER := {
	"ZAP_BOTTOM_ROW": 1, "COLOR_CONVERT": 2, "CRUSH_GARBAGE": 1, "SLOW_GRAVITY": 1, "DELAY_BOSS": 2,
	"SPAWN_GEMS": 2, "BOOST_MULTIPLIER": 3, "SPAWN_BOMB": 4, "NEXT_WILDCARD": 3, "STUN_BOSS": 5,
	"CLEAR_COLUMN_EDGE": 1, "SHIELD_BLOCK": 2, "TWIN_POP": 2, "HEAL_OVERFLOW": 3, "MEGA_STRIKE": 4,
}

const SILHOUETTES := [
	["Viking Helmet", "Wizard Cone", "Top Hat", "Propeller Beanie", "Royal Crown", "Chef Toque", "Traffic Cone", "Pirate Tricorn", "Bunny Ears", "Angel Halo"],
	["Groucho Glasses", "Neon Cyber-Visor", "Laser Monocle", "Pirate Eyepatch", "Handlebar Mustache", "Star Shades", "Clown Nose", "Ski Goggles", "3D Glasses", "Hero Mask"],
	["Giant Foam Finger", "Rubber Chicken", "Magic Wand", "Squeaky Hammer", "Lollipop Sword", "Fish Slapper", "Golden Plunger", "Bubble Blaster", "Battle Baguette", "Banana Phone"],
]
const PALETTE_NAMES := ["Molten", "Frosty", "Toxic", "Royal", "Bubblegum"]
## [main, secondary, accent] per palette.
const PALETTES := [
	[Color("ff5a36"), Color("ffb02e"), Color("fff27a")],
	[Color("6fd6ff"), Color("e8f8ff"), Color("3b7bff")],
	[Color("6cf03c"), Color("2f9e44"), Color("e7ff5a")],
	[Color("8a4dff"), Color("ffd23f"), Color("ff6fb5")],
	[Color("ff7ac8"), Color("7af0ff"), Color("fff0a8")],
]

var items: Array = []   # Array[Dictionary]


func _ready() -> void:
	_generate()
	SaveManager.ensure_starter_kit(starter_items())


func _generate() -> void:
	items.clear()
	# Deterministic permutation of the 150 (trigger, effect) pairs.
	var combos: Array = []
	for c in 150:
		combos.append(c)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20251113
	for i in range(combos.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = combos[i]
		combos[i] = combos[j]
		combos[j] = tmp
	var scores: Array = []
	for id in 150:
		var slot := id / 50
		var local := id % 50
		var combo := int(combos[id])
		var trig: String = TRIGGERS[combo % 10]
		var eff: String = EFFECTS[combo / 10]
		var sil := local % 10
		var pal := local / 10
		var item := {
			"id": id,
			"slot": slot,
			"slot_key": SLOT_KEYS[slot],
			"name": "%s %s" % [PALETTE_NAMES[pal], SILHOUETTES[slot][sil]],
			"silhouette": sil,
			"palette": pal,
			"trigger": trig,
			"effect": eff,
			"rarity": Rarity.COMMON,
		}
		items.append(item)
		var score := float(EFFECT_POWER[eff]) * 2.0 + (4 - int(TRIGGER_FREQ[trig])) * 1.2 + rng.randf() * 1.5
		scores.append([score, id])
	# Rank into rarity buckets: 60 Common, 50 Rare, 28 Epic, 12 Legendary.
	scores.sort_custom(func(a, b): return a[0] < b[0])
	for rank in scores.size():
		var id2 := int(scores[rank][1])
		var r := Rarity.COMMON
		if rank >= 138:
			r = Rarity.LEGENDARY
		elif rank >= 110:
			r = Rarity.EPIC
		elif rank >= 60:
			r = Rarity.RARE
		items[id2]["rarity"] = r


# --- Queries --------------------------------------------------------------

func get_item(id: int) -> Dictionary:
	if id < 0 or id >= items.size():
		return {}
	return items[id]


func items_for_slot(slot: int) -> Array:
	return items.filter(func(it): return it["slot"] == slot)


## One Common item per slot for brand-new players.
func starter_items() -> Array:
	var out: Array = []
	for slot in 3:
		var best := -1
		for it in items_for_slot(slot):
			if it["rarity"] == Rarity.COMMON and (it["trigger"] in ["ON_POP_RED", "ON_POP_BLUE", "ON_POP_GREEN_YELLOW", "ON_HARD_DROP", "ON_TURN_END"]):
				best = it["id"]
				break
		if best == -1:
			best = items_for_slot(slot)[0]["id"]
		out.append(best)
	return out


## Chance (0..1) an item fires when its trigger happens.
func proc_chance(item: Dictionary, level: int) -> float:
	return clampf(0.45 + 0.1 * level + 0.05 * int(item["rarity"]), 0.0, 1.0)


## Strength multiplier: Lv1-2 -> 1, Lv3-4 -> 2, Lv5 -> 3.
func potency(level: int) -> int:
	return 1 + int((clampi(level, 1, 5) - 1) / 2)


func effect_amount(effect: String, level: int) -> float:
	var p := potency(level)
	match effect:
		"SLOW_GRAVITY":
			return 4.0 + 2.0 * p
		"SPAWN_GEMS":
			return float(p)
		"BOOST_MULTIPLIER":
			return 0.5 * p
		"MEGA_STRIKE":
			return 10.0 + 8.0 * level
		"STUN_BOSS":
			return 1.0
		"HEAL_OVERFLOW":
			return 1.0 + p
		_:
			return float(p)


func describe(item: Dictionary, level: int = 1) -> String:
	var eff: String = item["effect"]
	var amt := effect_amount(eff, max(level, 1))
	var fmt: String = EFFECT_TEXT[eff]
	var eff_text := ""
	if eff == "BOOST_MULTIPLIER":
		eff_text = fmt % ("%.1f" % amt)
	elif eff == "STUN_BOSS":
		eff_text = fmt
	else:
		eff_text = fmt % int(amt)
	return "WHEN: %s\nDO: %s\n%d%% chance  ·  Lv.%d" % [TRIGGER_TEXT[item["trigger"]], eff_text, int(round(proc_chance(item, max(level, 1)) * 100)), max(level, 1)]


func rarity_color(r: int) -> Color:
	return UIKit.RARITY_COLORS[clampi(r, 0, 3)]


func rarity_name(r: int) -> String:
	return UIKit.RARITY_NAMES[clampi(r, 0, 3)]


# --- Loot rolls -----------------------------------------------------------

## Rolls a random item. `premium` = gem chest (better odds). Applies pity.
func roll_item(premium: bool, force_epic: bool = false) -> int:
	var odds := [35, 40, 18, 7] if premium else [62, 28, 8, 2]
	var r := 0
	var x := randi() % 100
	var acc := 0
	for i in 4:
		acc += odds[i]
		if x < acc:
			r = i
			break
	if force_epic and r < Rarity.EPIC:
		r = Rarity.LEGENDARY if randf() < 0.25 else Rarity.EPIC
	var pool := items.filter(func(it): return it["rarity"] == r)
	return int(pool[randi() % pool.size()]["id"])
