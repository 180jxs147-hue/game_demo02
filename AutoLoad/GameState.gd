extends Node

var selected_level_index: int = 0

const USER_LIBRARY_PATH := "user://PlayerLibrary.tres"
const DEFAULT_LIBRARY_PATH := "res://Resources/PlayerLibrary.tres"

func load_player_library() -> CardLibrary:
	if FileAccess.file_exists(USER_LIBRARY_PATH):
		var user_lib = load(USER_LIBRARY_PATH)
		if user_lib is CardLibrary:
			return user_lib
	var default_lib = load(DEFAULT_LIBRARY_PATH)
	return default_lib as CardLibrary

func save_player_library(library: CardLibrary) -> int:
	if not library:
		return ERR_INVALID_DATA
	return ResourceSaver.save(library, USER_LIBRARY_PATH)

func clear_save() -> int:
	selected_level_index = 0
	var lib = load_player_library()
	if not lib:
		return ERR_CANT_OPEN
	lib.collected_cards.clear()
	return save_player_library(lib)
