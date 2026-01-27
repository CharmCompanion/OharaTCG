# CardDatabase.gd
# Auto-generated One Piece TCG Card Database
# Add this script as an AutoLoad in Project Settings

extends Node

# Card database loaded from JSON
var cards: Dictionary = {}
var sets: Dictionary = {}
var metadata: Dictionary = {}

func _ready():
        load_database()

func load_database():
        var file = FileAccess.open("res://godot_card_database.json", FileAccess.READ)
        if file:
                var json_text = file.get_as_text()
                file.close()
                
                var json = JSON.new()
                var parse_result = json.parse(json_text)
                
                if parse_result == OK:
                        var data = json.data
                        cards = data.get("cards", {})
                        sets = data.get("sets", {})
                        metadata = data.get("metadata", {})
                        print("Loaded ", cards.size(), " cards from ", sets.size(), " sets")
                else:
                        print("Error parsing card database JSON")
        else:
                print("Error loading card database file")

# Get card by ID
func get_card(card_id: String) -> Dictionary:
        return cards.get(card_id, {})

# Get all cards from a set
func get_cards_by_set(set_id: String) -> Array:
        var set_cards = []
        for card_id in cards:
                var card = cards[card_id]
                if card.get("set_id", "") == set_id:
                        set_cards.append(card)
        return set_cards

# Get cards by type
func get_cards_by_type(card_type: String) -> Array:
        var type_cards = []
        for card_id in cards:
                var card = cards[card_id]
                if card.get("type", "").to_lower() == card_type.to_lower():
                        type_cards.append(card)
        return type_cards

# Get cards by rarity
func get_cards_by_rarity(rarity: String) -> Array:
        var rarity_cards = []
        for card_id in cards:
                var card = cards[card_id]
                if card.get("rarity", "").to_lower() == rarity.to_lower():
                        rarity_cards.append(card)
        return rarity_cards

# Search cards by name
func search_cards(query: String) -> Array:
        var results = []
        query = query.to_lower()
        for card_id in cards:
                var card = cards[card_id]
                var name = card.get("name", "").to_lower()
                if query in name:
                        results.append(card)
        return results

# Get set information
func get_set(set_id: String) -> Dictionary:
        return sets.get(set_id, {})

# Get all available sets
func get_all_sets() -> Dictionary:
        return sets

# Get promo cards
func get_promo_cards() -> Array:
        var promos = []
        for card_id in cards:
                var card = cards[card_id]
                if card.get("is_promo", false):
                        promos.append(card)
        return promos

# Get tournament cards
func get_tournament_cards() -> Array:
        var tournaments = []
        for card_id in cards:
                var card = cards[card_id]
                if card.get("is_tournament", false):
                        tournaments.append(card)
        return tournaments

# Get alternate art cards
func get_alt_art_cards() -> Array:
        var alt_arts = []
        for card_id in cards:
                var card = cards[card_id]
                if card.get("is_alternate_art", false):
                        alt_arts.append(card)
        return alt_arts
