extends Node

func sanitize_card_data(data: Dictionary) -> Dictionary:
	data["count"] = data.get("count", 1)
	data["alt_index"] = data.get("alt_index", 0)

	if data.has("effect") and typeof(data["effect"]) == TYPE_STRING:
		var effect_text: String = data["effect"]
		if effect_text.strip_edges().to_upper() == "NULL":
			effect_text = ""
		var html_regex := RegEx.new()
		html_regex.compile("<[^>]+>")
		effect_text = html_regex.sub(effect_text, "", true)
		var disclaimer_index = effect_text.find("Disclaimer:")
		if disclaimer_index >= 0:
			effect_text = effect_text.substr(0, disclaimer_index)
		data["effect"] = effect_text.strip_edges()

	return data
