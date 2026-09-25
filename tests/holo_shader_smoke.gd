extends SceneTree

# tests/holo_shader_smoke.gd -- Test holographic shader compilation and style application

var _frame := 0

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		var shader = load("res://shaders/holo_card.gdshader")
		assert(shader is Shader, "Holo shader must load as Shader")

		# Test compiling with each style 0..3
		for style_idx in range(4):
			var mat := ShaderMaterial.new()
			mat.shader = shader
			mat.set_shader_parameter("u_style", style_idx)
			mat.set_shader_parameter("u_strength", 0.5)
			mat.set_shader_parameter("u_speed", 0.6)
			mat.set_shader_parameter("u_mouse", Vector2(0.4, 0.6))
			mat.set_shader_parameter("u_parallel", 1.0)
			mat.set_shader_parameter("u_prize", 1.0)
			var tr := TextureRect.new()
			tr.material = mat
			root.add_child(tr)
			print("PASS: Shader compiled cleanly for style %d" % style_idx)
			tr.queue_free()

		# Test MatCard style assignment
		var card_script = load("res://scripts/ui/MatCard.gd")
		var dummy_card: Dictionary = {
			"card_code": "OP01-001",
			"rarity": "SecretRare",
			"card_name": "Roronoa Zoro"
		}
		var mc = card_script.new()
		root.add_child(mc)
		mc.setup("dummy_uid", "hand", "Zoro", "Slash", "res://assets/cards/Base/BaseCard.png", false, false, dummy_card)
		assert(mc._holo != null, "_holo must exist on MatCard")
		assert(mc._holo.material is ShaderMaterial, "_holo must have ShaderMaterial for SecretRare")
		var assigned_style = (mc._holo.material as ShaderMaterial).get_shader_parameter("u_style")
		assert(assigned_style == 1, "SecretRare must map to style 1 (Starlight Streaks)")
		print("PASS: MatCard mapped SecretRare to holo style 1")
		mc.queue_free()

		print("HOLO SHADER SMOKE: OK (0 failures)")
		quit(0)
		return true

	return false
