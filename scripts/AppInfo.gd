extends Node
## AppInfo — works out the game's display title.
##
## The title on the title screen follows the name of the file the game was
## launched from, so renaming the game file renames the game:
##   * Windows : hefland.exe            -> "hefland"
##   * Linux   : hefland.x86_64         -> "hefland"
##   * macOS   : hefland.app            -> "hefland"
##   * Android / iOS : the OS renames installed packages (every APK becomes
##     "base.apk"), so the name is baked in at export time instead:
##         ./build.sh hefland android      -> hefland.apk titled "hefland"
##     build.sh writes the name into project.godot (application/config/name).
##   * Any platform: launching with `-- --title=Whatever` overrides everything.
## When running from the Godot editor the project name is used.

const DEFAULT_TITLE := "BlockLoot: Face-Off"
const GENERIC_NAMES := ["godot", "blockloot", "game", "base", "main", "launcher", "app", "blockloot-face-off", "blockloot_face-off"]
const STRIP_SUFFIXES := [".exe", ".x86_64", ".x86_32", ".arm64", ".arm32", ".universal", ".console", ".apk", ".aab", ".ipa", ".app", ".appimage", ".pck"]

var title: String = DEFAULT_TITLE
var title_source: String = "default"


func _ready() -> void:
	title = resolve_title()
	DisplayServer.window_set_title(title)


func resolve_title() -> String:
	# 1) Explicit command-line override: `-- --title=Name`
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--title="):
			var t := clean_name(arg.substr(8))
			if t != "":
				title_source = "cmdline"
				return t
	# 2) Exported desktop builds: use the executable / bundle filename.
	if OS.has_feature("template") and not OS.has_feature("mobile") and not OS.has_feature("web"):
		var from_file := name_from_path(OS.get_executable_path())
		if from_file != "" and not GENERIC_NAMES.has(from_file.to_lower()):
			title_source = "filename"
			return from_file
	# 3) Mobile / editor: the project name (build.sh sets this to the file name).
	var project_name := str(ProjectSettings.get_setting("application/config/name", DEFAULT_TITLE))
	title_source = "project"
	return project_name if project_name.strip_edges() != "" else DEFAULT_TITLE


## Turns a full executable path into a display name.
static func name_from_path(path: String) -> String:
	if path == "":
		return ""
	var p := path.replace("\\", "/")
	# macOS: /Applications/hefland.app/Contents/MacOS/BlockLoot -> hefland
	var app_idx := p.find(".app/Contents/MacOS")
	if app_idx != -1:
		p = p.substr(0, app_idx)
	return clean_name(p.get_file())


## Strips platform suffixes like ".exe" / ".x86_64" and tidies the result.
static func clean_name(raw: String) -> String:
	var n := raw.strip_edges()
	var changed := true
	while changed:
		changed = false
		for suf in STRIP_SUFFIXES:
			if n.to_lower().ends_with(suf):
				n = n.substr(0, n.length() - suf.length())
				changed = true
	n = n.replace("_", " ").strip_edges()
	return n.substr(0, 28)
