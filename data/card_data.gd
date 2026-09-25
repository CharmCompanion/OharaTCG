@tool
extends Resource

class_name CardData

@export var card_id: String = ""
@export var card_name: String = ""
@export var card_type: String = "" # LEADER, CHARACTER, EVENT, STAGE
@export var color: Array[String] = []
@export var cost: int = 0
@export var power: int = -1
@export var counter: int = 0
@export var rarity: String = ""
@export var attribute: String = ""
@export var traits: Array[String] = []
@export var effect_text: String = ""
