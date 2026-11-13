extends Node
## SaveManager — persistent progression stored in user://save_data.json.

signal currency_changed
signal loadout_changed

const SAVE_PATH := "user://save_data.json"
const SAVE_VERSION := 2

var data: Dictionary = {}


func _ready() -> void:
	load_game()


func default_data() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"coins": 300,
		"gems": 20,
		"items": {},            # item_id (String) -> level (int 1..5)
		"loadout": {"head": -1, "face": -1, "hand": -1},
		"high_score": 0,
		"best_floor": 0,
		"boss_wins": 0,
		"boss_streak": 0,
		"best_streak": 0,
		"runs": 0,
		"pity": 0,              # pulls since last Epic+ item
		"total_pulls": 0,
		"last_daily": "",
		"hero_face": "builtin_0",
		"volume": 0.8,
		"muted": false,
	}


func load_game() -> void:
	data = default_data()
	if FileAccess.file_exists(SAVE_PATH):
		var txt := FileAccess.get_file_as_string(SAVE_PATH)
		var parsed = JSON.parse_string(txt)
		if parsed is Dictionary:
			for k in parsed.keys():
				data[k] = parsed[k]
	# JSON numbers come back as floats; normalise the important ones.
	for k in ["coins", "gems", "high_score", "best_floor", "boss_wins", "boss_streak", "best_streak", "runs", "pity", "total_pulls"]:
		data[k] = int(data.get(k, 0))
	var items: Dictionary = {}
	var raw_items = data.get("items", {})
	if raw_items is Dictionary:
		for k in raw_items.keys():
			items[str(k)] = clampi(int(raw_items[k]), 1, 5)
	data["items"] = items
	var lo = data.get("loadout", {})
	if not (lo is Dictionary):
		lo = {}
	data["loadout"] = {"head": int(lo.get("head", -1)), "face": int(lo.get("face", -1)), "hand": int(lo.get("hand", -1))}


## Gives brand-new players one starter item per slot (called once GearDatabase exists).
func ensure_starter_kit(starters: Array) -> void:
	if not data["items"].is_empty():
		return
	var slots := ["head", "face", "hand"]
	for i in range(starters.size()):
		var id := int(starters[i])
		data["items"][str(id)] = 1
		data["loadout"][slots[i]] = id
	save_game()


func save_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()


# --- Currency -------------------------------------------------------------

func coins() -> int:
	return int(data["coins"])


func gems() -> int:
	return int(data["gems"])


func add_coins(n: int) -> void:
	data["coins"] = max(0, coins() + n)
	currency_changed.emit()


func add_gems(n: int) -> void:
	data["gems"] = max(0, gems() + n)
	currency_changed.emit()


func spend(coin_cost: int, gem_cost: int) -> bool:
	if coins() < coin_cost or gems() < gem_cost:
		return false
	data["coins"] = coins() - coin_cost
	data["gems"] = gems() - gem_cost
	currency_changed.emit()
	return true


# --- Items ----------------------------------------------------------------

func owns(item_id: int) -> bool:
	return data["items"].has(str(item_id))


func item_level(item_id: int) -> int:
	return int(data["items"].get(str(item_id), 0))


## Adds an item or levels it up. Returns {"new": bool, "level": int, "maxed": bool}.
func grant_item(item_id: int) -> Dictionary:
	var key := str(item_id)
	if not data["items"].has(key):
		data["items"][key] = 1
		return {"new": true, "level": 1, "maxed": false}
	var lv := int(data["items"][key])
	if lv >= 5:
		return {"new": false, "level": 5, "maxed": true}
	data["items"][key] = lv + 1
	return {"new": false, "level": lv + 1, "maxed": false}


func owned_count() -> int:
	return data["items"].size()


func equipped(slot_name: String) -> int:
	return int(data["loadout"].get(slot_name, -1))


func equip(slot_name: String, item_id: int) -> void:
	data["loadout"][slot_name] = item_id
	save_game()
	loadout_changed.emit()


# --- Daily chest ----------------------------------------------------------

func today() -> String:
	return Time.get_date_string_from_system()


func daily_available() -> bool:
	return str(data.get("last_daily", "")) != today()


func claim_daily() -> void:
	data["last_daily"] = today()
	save_game()


# --- Run results ----------------------------------------------------------

## Records a finished run. Returns true when a new high score was set.
func record_run(score: int, floor_reached: int) -> bool:
	data["runs"] = int(data["runs"]) + 1
	var is_best := score > int(data["high_score"])
	if is_best:
		data["high_score"] = score
	data["best_floor"] = max(int(data["best_floor"]), floor_reached)
	data["boss_streak"] = 0
	save_game()
	return is_best


func record_boss_win() -> void:
	data["boss_wins"] = int(data["boss_wins"]) + 1
	data["boss_streak"] = int(data["boss_streak"]) + 1
	data["best_streak"] = max(int(data["best_streak"]), int(data["boss_streak"]))
	save_game()
