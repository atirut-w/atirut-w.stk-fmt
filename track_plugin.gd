class_name TrackImportPlugin
extends EditorImportPlugin

func _get_importer_name() -> String:
	return "atirut-w.track_plugin"


func _get_visible_name() -> String:
	return "STK Scene"


func _get_recognized_extensions() -> PackedStringArray:
	return ["xml"]


func _get_save_extension() -> String:
	return "tscn"


func _get_resource_type() -> String:
	return "PackedScene"


func _get_preset_count() -> int:
	return 1


func _get_preset_name(preset: int) -> String:
	return "Default"


func _get_import_options(path: String, preset_index: int) -> Array[Dictionary]:
	return [{}]


func _get_priority() -> float:
	return 100.0


func _get_import_order() -> int:
	return 0


func _import(source_file: String, save_path: String, options: Dictionary, platform_variants: Array[String], gen_files: Array[String]) -> Error:
	# Only import files named scene.xml
	if source_file.get_file() != "scene.xml":
		printerr("Only scene.xml files can be imported with this importer")
		return ERR_FILE_UNRECOGNIZED
	
	# Parse track directory from source_file path
	var track_dir = source_file.get_base_dir()
	
	# Parse scene.xml
	var scene_data = _parse_scene_xml(source_file)
	if not scene_data:
		printerr("Failed to parse scene.xml")
		return ERR_FILE_CORRUPT
	
	# Parse track.xml if it exists (for environment settings)
	var track_data = {}
	var track_xml_path = track_dir.path_join("track.xml")
	if FileAccess.file_exists(track_xml_path):
		track_data = _parse_track_xml(track_xml_path)
	
	# Parse materials.xml if it exists
	var materials_data = {}
	var materials_xml_path = track_dir.path_join("materials.xml")
	if FileAccess.file_exists(materials_xml_path):
		materials_data = _parse_materials_xml(materials_xml_path)
	
	# Create the root node for the track scene
	var track_scene = Node3D.new()
	
	# Use the directory name as the scene name if track.xml doesn't exist
	if track_data.has("name"):
		track_scene.name = track_data.get("name")
	else:
		track_scene.name = track_dir.get_file()
	
	# Setup environment settings from track.xml if available
	if not track_data.is_empty():
		_setup_environment(track_scene, track_data)
	else:
		# Create a basic environment if track.xml doesn't exist
		var env = Environment.new()
		var world_env = WorldEnvironment.new()
		world_env.environment = env
		world_env.name = "WorldEnvironment"
		track_scene.add_child(world_env)
		world_env.owner = track_scene
		
		# Add a basic directional light
		var sun = DirectionalLight3D.new()
		sun.name = "SunLight"
		sun.light_energy = 1.0
		sun.rotation = Vector3(-PI/4, PI/4, 0)
		track_scene.add_child(sun)
		sun.owner = track_scene
	
	# Import the main track model and objects from scene.xml
	_import_scene_objects(track_scene, scene_data, track_dir, materials_data)
	
	# Save the scene
	var packed_scene = PackedScene.new()
	var result = packed_scene.pack(track_scene)
	if result != OK:
		return result
	
	return ResourceSaver.save(packed_scene, "%s.%s" % [save_path, _get_save_extension()])


func _parse_track_xml(path: String) -> Dictionary:
	var parser = XMLParser.new()
	var err = parser.open(path)
	if err != OK:
		printerr("Failed to open track.xml: ", err)
		return {}
	
	var track_data = {}
	
	# Find the track element
	while parser.read() == OK:
		if parser.get_node_type() == XMLParser.NODE_ELEMENT and parser.get_node_name() == "track":
			# Get all attributes of the track element
			for i in range(parser.get_attribute_count()):
				var attr_name = parser.get_attribute_name(i)
				var attr_value = parser.get_attribute_value(i)
				track_data[attr_name] = attr_value
			
			# Parse child elements
			while parser.read() == OK:
				if parser.get_node_type() == XMLParser.NODE_ELEMENT:
					var node_name = parser.get_node_name()
					
					# Handle color elements
					if node_name in ["sky-color", "sun-color", "ambient-color"]:
						var color = {
							"r": _get_attribute_value_safe(parser, "r").to_int(),
							"g": _get_attribute_value_safe(parser, "g").to_int(),
							"b": _get_attribute_value_safe(parser, "b").to_int()
						}
						track_data[node_name] = color
					
					# Handle fog element
					elif node_name == "fog":
						var fog = {
							"density": _get_attribute_value_safe(parser, "density").to_float(),
							"start": _get_attribute_value_safe(parser, "start").to_float(),
							"end": _get_attribute_value_safe(parser, "end").to_float(),
							"r": _get_attribute_value_safe(parser, "r").to_int(),
							"g": _get_attribute_value_safe(parser, "g").to_int(),
							"b": _get_attribute_value_safe(parser, "b").to_int()
						}
						track_data["fog"] = fog
				
				elif parser.get_node_type() == XMLParser.NODE_ELEMENT_END and parser.get_node_name() == "track":
					break
			
			break
	
	return track_data


func _parse_scene_xml(path: String) -> Dictionary:
	var parser = XMLParser.new()
	var err = parser.open(path)
	if err != OK:
		printerr("Failed to open scene.xml: ", err)
		return {}
	
	var scene_data = {
		"objects": [],
		"checkpoints": [],
		"particle_emitters": []
	}
	
	# Find the scene element
	while parser.read() == OK:
		if parser.get_node_type() == XMLParser.NODE_ELEMENT and parser.get_node_name() == "scene":
			# Parse child elements of scene
			while parser.read() == OK:
				if parser.get_node_type() == XMLParser.NODE_ELEMENT:
					var node_name = parser.get_node_name()
					
					# Handle track element
					if node_name == "track":
						var track = {
							"model": _get_attribute_value_safe(parser, "model"),
							"x": _get_attribute_value_safe(parser, "x", "0").to_float(),
							"y": _get_attribute_value_safe(parser, "y", "0").to_float(),
							"z": _get_attribute_value_safe(parser, "z", "0").to_float()
						}
						scene_data["track"] = track
					
					# Handle object elements
					elif node_name == "object":
						var obj = {
							"type": _get_attribute_value_safe(parser, "type"),
							"id": _get_attribute_value_safe(parser, "id"),
							"model": _get_attribute_value_safe(parser, "model"),
							"xyz": _parse_vector3(_get_attribute_value_safe(parser, "xyz")),
							"hpr": _parse_vector3(_get_attribute_value_safe(parser, "hpr")),
							"scale": _parse_vector3(_get_attribute_value_safe(parser, "scale"), Vector3(1, 1, 1))
						}
						
						# Check for skeletal animation
						if _get_attribute_value_safe(parser, "skeletal-animation") == "true":
							obj["skeletal_animation"] = true
						
						# Handle animation curves (might be child elements)
						var has_animation = false
						var animation_depth = 0
						var current_depth = 0
						
						while parser.read() == OK:
							if parser.get_node_type() == XMLParser.NODE_ELEMENT:
								current_depth += 1
								
								if parser.get_node_name() == "curve" and current_depth == 1:
									has_animation = true
									
									if not obj.has("animations"):
										obj["animations"] = []
									
									var curve = {
										"channel": _get_attribute_value_safe(parser, "channel"),
										"interpolation": _get_attribute_value_safe(parser, "interpolation"),
										"extend": _get_attribute_value_safe(parser, "extend"),
										"points": []
									}
									
									# Read curve points
									while parser.read() == OK:
										if parser.get_node_type() == XMLParser.NODE_ELEMENT and parser.get_node_name() == "p":
											var point = {
												"c": _get_attribute_value_safe(parser, "c"),
												"h1": _get_attribute_value_safe(parser, "h1"),
												"h2": _get_attribute_value_safe(parser, "h2")
											}
											curve["points"].append(point)
										elif parser.get_node_type() == XMLParser.NODE_ELEMENT_END and parser.get_node_name() == "curve":
											break
									
									obj["animations"].append(curve)
							
							elif parser.get_node_type() == XMLParser.NODE_ELEMENT_END:
								current_depth -= 1
								if parser.get_node_name() == "object" and current_depth < 0:
									break
						
						if not has_animation:
							scene_data["objects"].append(obj)
					
					# Handle checkpoints
					elif node_name.begins_with("check-"):
						var check_type = node_name
						
						if check_type == "check-line":
							var checkpoint = {
								"type": "line",
								"kind": _get_attribute_value_safe(parser, "kind"),
								"p1": _parse_vector3(_get_attribute_value_safe(parser, "p1")),
								"p2": _parse_vector3(_get_attribute_value_safe(parser, "p2")),
								"min_height": _get_attribute_value_safe(parser, "min-height").to_float(),
							}
							scene_data["checkpoints"].append(checkpoint)
						
						elif check_type == "check-sphere":
							var checkpoint = {
								"type": "sphere",
								"kind": _get_attribute_value_safe(parser, "kind"),
								"center": _parse_vector3(_get_attribute_value_safe(parser, "center")),
								"radius": _get_attribute_value_safe(parser, "radius").to_float()
							}
							scene_data["checkpoints"].append(checkpoint)
						
						elif check_type == "check-trigger":
							var checkpoint = {
								"type": "trigger",
								"kind": _get_attribute_value_safe(parser, "kind"),
								"p1": _parse_vector3(_get_attribute_value_safe(parser, "p1")),
								"p2": _parse_vector3(_get_attribute_value_safe(parser, "p2")),
								"p3": _parse_vector3(_get_attribute_value_safe(parser, "p3")),
								"p4": _parse_vector3(_get_attribute_value_safe(parser, "p4"))
							}
							scene_data["checkpoints"].append(checkpoint)
					
					# Handle particle emitters
					elif node_name == "particle-emitter":
						var emitter = {
							"kind": _get_attribute_value_safe(parser, "kind"),
							"origin": _parse_vector3(_get_attribute_value_safe(parser, "origin"))
						}
						scene_data["particle_emitters"].append(emitter)
					
					# Handle sky-box
					elif node_name == "sky-box":
						scene_data["sky_box"] = _get_attribute_value_safe(parser, "texture").split(" ")
					
					# Handle camera settings
					elif node_name == "camera":
						scene_data["camera"] = {
							"far": _get_attribute_value_safe(parser, "far").to_float()
						}
					
					# Handle sun
					elif node_name == "sun":
						scene_data["sun"] = {
							"xyz": _parse_vector3(_get_attribute_value_safe(parser, "xyz")),
							"ambient": _get_attribute_value_safe(parser, "ambient").to_float()
						}
				
				elif parser.get_node_type() == XMLParser.NODE_ELEMENT_END and parser.get_node_name() == "scene":
					break
			
			break
	
	return scene_data


func _parse_materials_xml(path: String) -> Dictionary:
	var parser = XMLParser.new()
	var err = parser.open(path)
	if err != OK:
		printerr("Failed to open materials.xml: ", err)
		return {}
	
	var materials_data = {}
	
	# Find the materials element
	while parser.read() == OK:
		if parser.get_node_type() == XMLParser.NODE_ELEMENT and parser.get_node_name() == "materials":
			# Parse child elements
			while parser.read() == OK:
				if parser.get_node_type() == XMLParser.NODE_ELEMENT and parser.get_node_name() == "material":
					var material_name = _get_attribute_value_safe(parser, "name")
					var material = {}
					
					for i in range(parser.get_attribute_count()):
						var attr_name = parser.get_attribute_name(i)
						var attr_value = parser.get_attribute_value(i)
						
						if attr_name != "name":
							# Convert some value types
							if attr_value in ["Y", "true"]:
								material[attr_name] = true
							elif attr_value in ["N", "false"]:
								material[attr_name] = false
							elif attr_value.is_valid_float():
								material[attr_name] = attr_value.to_float()
							else:
								material[attr_name] = attr_value
					
					materials_data[material_name] = material
				
				elif parser.get_node_type() == XMLParser.NODE_ELEMENT_END and parser.get_node_name() == "materials":
					break
	
	return materials_data


func _setup_environment(track_scene: Node3D, track_data: Dictionary) -> void:
	# Create WorldEnvironment node
	var env = Environment.new()
	var world_env = WorldEnvironment.new()
	world_env.environment = env
	world_env.name = "WorldEnvironment"
	track_scene.add_child(world_env)
	world_env.owner = track_scene
	
	# Apply environment settings from track_data
	if track_data.has("sky-color"):
		var sky_color = Color(
			float(track_data["sky-color"].r) / 255.0,
			float(track_data["sky-color"].g) / 255.0,
			float(track_data["sky-color"].b) / 255.0
		)
		# Setup sky background
		env.background_mode = Environment.BG_COLOR
		env.background_color = sky_color
	
	if track_data.has("fog"):
		# Setup fog
		env.fog_enabled = true
		env.fog_density = track_data.fog.density
		env.fog_aerial_perspective = 0.5
		env.fog_sky_affect = 0.5
		
		var fog_color = Color(
			float(track_data.fog.r) / 255.0,
			float(track_data.fog.g) / 255.0,
			float(track_data.fog.b) / 255.0
		)
		env.fog_light_color = fog_color
	
	# Create a sun light if we have sun color
	if track_data.has("sun-color"):
		var sun_color = Color(
			float(track_data["sun-color"].r) / 255.0,
			float(track_data["sun-color"].g) / 255.0,
			float(track_data["sun-color"].b) / 255.0
		)
		
		var sun = DirectionalLight3D.new()
		sun.name = "SunLight"
		sun.light_color = sun_color
		sun.light_energy = 1.0
		
		# Default sun direction (will be overridden if scene.xml has sun position)
		sun.rotation = Vector3(-PI/4, PI/4, 0)
		
		track_scene.add_child(sun)
		sun.owner = track_scene
	
	# Apply ambient light if specified
	if track_data.has("ambient-color"):
		var ambient_color = Color(
			float(track_data["ambient-color"].r) / 255.0, 
			float(track_data["ambient-color"].g) / 255.0,
			float(track_data["ambient-color"].b) / 255.0
		)
		env.ambient_light_color = ambient_color
		env.ambient_light_energy = 1.0


func _import_scene_objects(track_scene: Node3D, scene_data: Dictionary, track_dir: String, materials_data: Dictionary) -> void:
	# Import the main track model
	if scene_data.has("track"):
		var track_model_path = track_dir.path_join(scene_data.track.model)
		var mesh = null
		
		# First try to load the .tres if it already exists (processed by SPM importer)
		var spm_resource_path = track_model_path.get_basename() + ".tres"
		if ResourceLoader.exists(spm_resource_path):
			mesh = ResourceLoader.load(spm_resource_path)
		# Otherwise, try to import the SPM file directly if it exists
		elif FileAccess.file_exists(track_model_path) and track_model_path.get_extension().to_lower() == "spm":
			# Create a ResourceImporter instance
			var importer = SPMImportPlugin.new()
			var save_path = track_model_path.get_basename()
			var result = importer._import(track_model_path, save_path, {"unwrap_uv2": false}, [], [])
			
			if result == OK:
				# Now try to load the newly created resource
				mesh = ResourceLoader.load(save_path + ".tres")
			else:
				printerr("Failed to import SPM file: ", track_model_path)
		
		if mesh:
			var mesh_instance = MeshInstance3D.new()
			mesh_instance.mesh = mesh
			mesh_instance.name = "TrackModel"
			
			# Apply position from scene_data
			mesh_instance.position = Vector3(
				scene_data.track.x,
				scene_data.track.y,
				-scene_data.track.z  # Convert STK to Godot coordinates
			)
			
			track_scene.add_child(mesh_instance)
			mesh_instance.owner = track_scene
	
	# Import objects
	if scene_data.has("objects") and not scene_data.objects.is_empty():
		var objects_node = Node3D.new()
		objects_node.name = "Objects"
		track_scene.add_child(objects_node)
		objects_node.owner = track_scene
		
		for obj in scene_data.objects:
			_import_object(obj, objects_node, track_dir, materials_data)
		
		# Set ownership recursively for all children
		_set_owner_recursive(objects_node, track_scene)
	
	# Import checkpoints
	if scene_data.has("checkpoints") and not scene_data.checkpoints.is_empty():
		var checkpoints_node = Node3D.new()
		checkpoints_node.name = "Checkpoints"
		track_scene.add_child(checkpoints_node)
		checkpoints_node.owner = track_scene
		
		for checkpoint in scene_data.checkpoints:
			_import_checkpoint(checkpoint, checkpoints_node)
		
		# Set ownership recursively for all children
		_set_owner_recursive(checkpoints_node, track_scene)
	
	# Import particle emitters - disabled for now
	# Particle systems would require more specific setup for Godot
	if false and scene_data.has("particle_emitters") and not scene_data.particle_emitters.is_empty():
		var emitters_node = Node3D.new()
		emitters_node.name = "ParticleEmitters"
		track_scene.add_child(emitters_node)
		emitters_node.owner = track_scene
		
		for emitter in scene_data.particle_emitters:
			_import_particle_emitter(emitter, emitters_node)
			
		# Set ownership recursively for all children
		_set_owner_recursive(emitters_node, track_scene)
	
	# Set up sun position if defined in scene
	if scene_data.has("sun") and track_scene.has_node("SunLight"):
		var sun = track_scene.get_node("SunLight")
		var sun_pos = Vector3(
			scene_data.sun.xyz[0],
			scene_data.sun.xyz[1],
			-scene_data.sun.xyz[2]  # Convert STK to Godot coordinates
		)
		
		# Look at origin from sun position
		sun.global_transform = sun.global_transform.looking_at(Vector3.ZERO, Vector3.UP)
		sun.position = sun_pos


func _import_object(obj_data: Dictionary, parent: Node3D, track_dir: String, materials_data: Dictionary) -> void:
	# Create node for the object
	var obj_node = MeshInstance3D.new()
	obj_node.name = obj_data.get("id", "Object")
	
	# Set position, rotation, scale
	obj_node.position = Vector3(
		obj_data.xyz[0],
		obj_data.xyz[1],
		-obj_data.xyz[2]  # Convert STK to Godot coordinates
	)
	
	# Handle HPR (heading, pitch, roll) to Godot rotation
	# STK uses HPR (degrees) - heading is yaw around Y, pitch around X, roll around Z
	var heading_rad = deg_to_rad(obj_data.hpr[0])
	var pitch_rad = deg_to_rad(obj_data.hpr[1])
	var roll_rad = deg_to_rad(obj_data.hpr[2])
	
	# Create rotation basis - note that Z axis is flipped
	var basis = Basis()
	basis = basis.rotated(Vector3.UP, heading_rad)
	basis = basis.rotated(Vector3.RIGHT, pitch_rad)
	basis = basis.rotated(Vector3.FORWARD, -roll_rad)  # Negate for Z flip
	
	obj_node.basis = basis
	
	# Set scale
	obj_node.scale = Vector3(obj_data.scale[0], obj_data.scale[1], obj_data.scale[2])
	
	# Load mesh if specified
	if obj_data.has("model"):
		var model_path = track_dir.path_join(obj_data.model)
		var mesh = null
		
		# First try to load the .tres if it already exists (processed by SPM importer)
		var spm_resource_path = model_path.get_basename() + ".tres"
		if ResourceLoader.exists(spm_resource_path):
			mesh = ResourceLoader.load(spm_resource_path)
		# Otherwise, try to import the SPM file directly if it exists
		elif FileAccess.file_exists(model_path) and model_path.get_extension().to_lower() == "spm":
			# Create a ResourceImporter instance
			var importer = SPMImportPlugin.new()
			var save_path = model_path.get_basename()
			var result = importer._import(model_path, save_path, {"unwrap_uv2": false}, [], [])
			
			if result == OK:
				# Now try to load the newly created resource
				mesh = ResourceLoader.load(save_path + ".tres")
			else:
				printerr("Failed to import SPM file: ", model_path)
				
		if mesh:
			obj_node.mesh = mesh
	
	# Handle animations if present
	if obj_data.has("animations") and not obj_data.animations.is_empty():
		var anim_player = AnimationPlayer.new()
		anim_player.name = "AnimationPlayer"
		obj_node.add_child(anim_player)
		
		# Create animation
		var animation = Animation.new()
		animation.length = 1.0  # Default animation length
		
		anim_player.add_animation("Anim", animation)
		
		# Process curves to create animation tracks
		# This is simplified - a real implementation would need more complex animation support
		for curve in obj_data.animations:
			var track_path = ""
			var track_idx = -1
			
			# Determine which property to animate based on channel
			if curve.channel.begins_with("Loc"):
				if curve.channel == "LocX":
					track_path = ":position:x"
				elif curve.channel == "LocY":
					track_path = ":position:y"
				elif curve.channel == "LocZ":
					track_path = ":position:z"
			elif curve.channel.begins_with("Rot"):
				if curve.channel == "RotX":
					track_path = ":rotation:x"
				elif curve.channel == "RotY":
					track_path = ":rotation:y"
				elif curve.channel == "RotZ":
					track_path = ":rotation:z"
			elif curve.channel.begins_with("Scale"):
				if curve.channel == "ScaleX":
					track_path = ":scale:x"
				elif curve.channel == "ScaleY":
					track_path = ":scale:y"
				elif curve.channel == "ScaleZ":
					track_path = ":scale:z"
			
			if track_path != "":
				track_idx = animation.add_track(Animation.TYPE_VALUE)
				animation.track_set_path(track_idx, track_path)
				
				# Add keyframes
				for point in curve.points:
					var keyframe = point.c.split(" ")
					if keyframe.size() >= 2:
						var time = float(keyframe[0])
						var value = float(keyframe[1])
						
						# Adjust Z value for coordinate system conversion if needed
						if curve.channel == "LocZ":
							value = -value
						
						animation.track_insert_key(track_idx, time, value)
	
	# Add object node to parent 
	parent.add_child(obj_node)


func _import_checkpoint(checkpoint: Dictionary, parent: Node3D) -> void:
	var check_node = Node3D.new()
	check_node.name = "Checkpoint_" + checkpoint.kind
	
	# Create appropriate node based on checkpoint type
	if checkpoint.type == "line":
		check_node.position = (
			Vector3(checkpoint.p1[0], checkpoint.p1[1], -checkpoint.p1[2]) + 
			Vector3(checkpoint.p2[0], checkpoint.p2[1], -checkpoint.p2[2])
		) / 2.0
		
		# Add a visual representation for the line
		var mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "Visual"
		
		var line_length = (
			Vector3(checkpoint.p1[0], checkpoint.p1[1], -checkpoint.p1[2]) - 
			Vector3(checkpoint.p2[0], checkpoint.p2[1], -checkpoint.p2[2])
		).length()
		
		var box_mesh = BoxMesh.new()
		box_mesh.size = Vector3(0.2, 5.0, line_length)
		mesh_instance.mesh = box_mesh
		
		# Orient the line in the right direction
		var start = Vector3(checkpoint.p1[0], checkpoint.p1[1], -checkpoint.p1[2])
		var end = Vector3(checkpoint.p2[0], checkpoint.p2[1], -checkpoint.p2[2])
		mesh_instance.look_at_from_position(Vector3.ZERO, end - start, Vector3.UP)
		
		mesh_instance.position = Vector3.ZERO
		
		# Make it semi-transparent
		var material = StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(1, 0, 0, 0.5)
		box_mesh.material = material
		
		check_node.add_child(mesh_instance)
		# Owner will be set recursively
	
	elif checkpoint.type == "sphere":
		check_node.position = Vector3(
			checkpoint.center[0],
			checkpoint.center[1],
			-checkpoint.center[2]
		)
		
		# Add a visual representation for the sphere
		var mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "Visual"
		
		var sphere_mesh = SphereMesh.new()
		sphere_mesh.radius = checkpoint.radius
		sphere_mesh.height = checkpoint.radius * 2
		mesh_instance.mesh = sphere_mesh
		
		# Make it semi-transparent
		var material = StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(0, 1, 0, 0.3)
		sphere_mesh.material = material
		
		check_node.add_child(mesh_instance)
		# Owner will be set recursively
	
	elif checkpoint.type == "trigger":
		# Calculate center position of the quad
		var center = (
			Vector3(checkpoint.p1[0], checkpoint.p1[1], -checkpoint.p1[2]) +
			Vector3(checkpoint.p2[0], checkpoint.p2[1], -checkpoint.p2[2]) +
			Vector3(checkpoint.p3[0], checkpoint.p3[1], -checkpoint.p3[2]) +
			Vector3(checkpoint.p4[0], checkpoint.p4[1], -checkpoint.p4[2])
		) / 4.0
		
		check_node.position = center
		
		# Add a visual representation (simplified as a box)
		var mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "Visual"
		
		# Estimate size from points
		var size_x = (
			Vector3(checkpoint.p1[0], checkpoint.p1[1], -checkpoint.p1[2]) - 
			Vector3(checkpoint.p2[0], checkpoint.p2[1], -checkpoint.p2[2])
		).length()
		
		var size_y = (
			Vector3(checkpoint.p1[0], checkpoint.p1[1], -checkpoint.p1[2]) - 
			Vector3(checkpoint.p4[0], checkpoint.p4[1], -checkpoint.p4[2])
		).length()
		
		var box_mesh = BoxMesh.new()
		box_mesh.size = Vector3(size_x, size_y, 0.2)
		mesh_instance.mesh = box_mesh
		
		# Make it semi-transparent
		var material = StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(0, 0, 1, 0.3)
		box_mesh.material = material
		
		check_node.add_child(mesh_instance)
		# Owner will be set recursively
	
	# Add to parent now, but we'll set the owner at the end of the import process
	parent.add_child(check_node)


func _import_particle_emitter(emitter: Dictionary, parent: Node3D) -> void:
	var emitter_node = GPUParticles3D.new()
	emitter_node.name = "Emitter_" + emitter.kind
	
	# Set emitter position
	emitter_node.position = Vector3(
		emitter.origin[0],
		emitter.origin[1],
		-emitter.origin[2]  # Convert STK to Godot coordinates
	)
	
	# Setup particle system based on emitter kind
	var particle_material = ParticleProcessMaterial.new()
	
	if emitter.kind == "smoke":
		particle_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		particle_material.emission_sphere_radius = 0.5
		particle_material.direction = Vector3(0, 1, 0)
		particle_material.spread = 15.0
		particle_material.gravity = Vector3(0, 0.2, 0)
		particle_material.initial_velocity_min = 0.5
		particle_material.initial_velocity_max = 1.0
		particle_material.color = Color(0.7, 0.7, 0.7, 0.5)
		
		emitter_node.lifetime = 3.0
		emitter_node.preprocess = 1.0
		emitter_node.local_coords = false
	
	# Add a default mesh
	var mesh = QuadMesh.new()
	mesh.size = Vector2(0.5, 0.5)
	emitter_node.draw_pass_1 = mesh
	
	emitter_node.process_material = particle_material
	
	parent.add_child(emitter_node)
	# Owner will be set recursively at the end of import


# Helper function to parse vector3 from string like "10.0 0.0 5.0"
func _parse_vector3(text: String, default_value: Vector3 = Vector3.ZERO) -> Array:
	if text.is_empty():
		return [default_value.x, default_value.y, default_value.z]
	
	var parts = text.split(" ")
	var result = [default_value.x, default_value.y, default_value.z]
	
	for i in range(min(parts.size(), 3)):
		if parts[i].is_valid_float():
			result[i] = parts[i].to_float()
	
	return result


# Helper function to safely get attribute value with a default
func _get_attribute_value_safe(parser: XMLParser, attr_name: String, default_value: String = "") -> String:
	for i in range(parser.get_attribute_count()):
		if parser.get_attribute_name(i) == attr_name:
			return parser.get_attribute_value(i)
	
	return default_value


# Helper function to recursively set the owner of nodes
func _set_owner_recursive(node: Node, owner: Node) -> void:
	for child in node.get_children():
		if child.owner != owner:
			child.owner = owner
		
		# Recursively process the children
		_set_owner_recursive(child, owner)
