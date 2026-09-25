# res://scripts/Log.gd
extends Node

# Toggle this at runtime if you want: Log.enabled = false
var enabled: bool = OS.is_debug_build()  # true in editor, false in export release

func d(msg: Variant) -> void:
	# Drop-in replacement for print() you can search/replace to.
	if enabled:
		print(msg)

# Optional: verbose-only logging
func v(msg: Variant) -> void:
	print_verbose(msg)
