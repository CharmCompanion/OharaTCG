class_name CardStateMachine
extends Node

@export var initial_state: CardState

var current_state: CardState
var states: Dictionary = {}


func _ready():
	var owner_card := get_parent() as Card
	for child in get_children():
		if child is CardState:
			states[child.name.to_lower()] = child
			child.transitioned.connect(on_child_transition)
			if owner_card and child.card == null:
				child.card = owner_card
			
			if child.get_children():
				for sub_child in child.get_children():
					states[child.name.to_lower() + '/' + sub_child.name.to_lower()] = sub_child
					sub_child.transitioned.connect(on_child_transition)
					if owner_card and sub_child is CardState and sub_child.card == null:
						sub_child.card = owner_card
	
	if initial_state:
		initial_state.call_deferred("_enter")
		current_state = initial_state


func on_input(event: InputEvent):
	if current_state:
		current_state.on_input(event)


func on_gui_input(event: InputEvent):
	if current_state:
		current_state.on_gui_input(event)


func on_mouse_entered():
	if current_state:
		current_state.on_mouse_entered()


func on_mouse_exited():
	if current_state:
		current_state.on_mouse_exited()


func on_child_transition(new_state_name):
	var new_state: CardState = states.get(new_state_name.to_lower())
	if !new_state:
		prints(current_state, "transition to no state")
		return
	
	if current_state:
		current_state._exit()
		
	new_state.call_deferred("_enter")
	
	current_state = new_state
	
	prints(get_parent() ,"current state", current_state)
	
func start(state_name: String):
	var state: CardState = states.get(state_name.to_lower())
	if !state:
		push_error("State %s not found!" % state_name)
		return
	current_state = state
	current_state.call_deferred("_enter")
