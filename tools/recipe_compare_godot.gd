@tool
extends EditorScript
## Recipe Comparison Tool - Run from Godot Editor
## 
## This script compares your recipe files against scraped API data
## and shows differences so you can decide which to use.
##
## How to use:
## 1. Open this script in Godot Editor
## 2. Go to Script menu -> Run (Ctrl+Shift+X)
## 3. Check Output panel for results
## 4. Full report saved to output/reports/recipe_comparison.json

func _run() -> void:
	print("="*60)
	print("RECIPE COMPARISON TOOL")
	print("="*60)
	print("")
	
	var project_root := ProjectSettings.globalize_path("res://")
	var python_script := project_root + "tools/recipe_compare.py"
	var report_path := project_root + "output/reports/recipe_comparison.json"
	
	# Run the Python comparison script
	print("Running comparison script...")
	var output := []
	var exit_code := OS.execute("python3", [python_script], output, true)
	
	if exit_code != 0:
		push_error("Failed to run recipe_compare.py. Exit code: " + str(exit_code))
		for line in output:
			print(line)
		return
	
	# Print Python script output
	for line in output:
		print(line)
	
	# Load and display the report
	print("")
	print("="*60)
	print("LOADING DETAILED REPORT...")
	print("="*60)
	
	var file := FileAccess.open(report_path, FileAccess.READ)
	if not file:
		push_error("Could not open report file: " + report_path)
		return
	
	var json_text := file.get_as_text()
	file.close()
	
	var json := JSON.new()
	var error := json.parse(json_text)
	if error != OK:
		push_error("Failed to parse JSON report")
		return
	
	var report: Dictionary = json.data
	_display_report(report)


func _display_report(report: Dictionary) -> void:
	var summary: Dictionary = report.get("summary", {})
	var decks: Dictionary = report.get("decks", {})
	
	print("")
	print("DECKS WITH DIFFERENCES:")
	print("-"*40)
	
	var issues_found := false
	for deck_id in decks:
		var deck: Dictionary = decks[deck_id]
		var missing: Array = deck.get("missing_from_api", [])
		var extra: Array = deck.get("extra_in_api", [])
		
		if missing.size() > 0 or extra.size() > 0:
			issues_found = true
			print("")
			print("[%s] - %d cards in recipe" % [deck_id, deck.get("recipe_total", 0)])
			
			if missing.size() > 0:
				print("  MISSING FROM API (%d):" % missing.size())
				for card in missing:
					print("    - %s (qty: %d)" % [card.get("card_code", "?"), card.get("recipe_qty", 0)])
			
			if extra.size() > 0:
				print("  EXTRA IN API (%d):" % extra.size())
				for card in extra:
					print("    + %s - %s" % [card.get("card_code", "?"), card.get("name", "Unknown")])
	
	if not issues_found:
		print("All recipes match scraped data!")
	
	print("")
	print("="*60)
	print("Full report: res://output/reports/recipe_comparison.json")
	print("="*60)
