class_name SPMImportPlugin
extends EditorImportPlugin

enum MeshType {
	SPMS = 0, # Space partitioned mesh (not supported)
	SPMA = 1, # Animated/skinned mesh
	SPMN = 2  # Normal mesh
}

func _get_importer_name() -> String:
	return "atirut-w.spm_plugin"


func _get_visible_name() -> String:
	return "SPM Mesh"


func _get_recognized_extensions() -> PackedStringArray:
	return ["spm"]


func _get_save_extension() -> String:
	return "tres"


func _get_resource_type() -> String:
	return "Mesh"


func _get_preset_count() -> int:
	return 1


func _get_preset_name(preset: int) -> String:
	return "Default"


func _get_import_options(path: String, preset_index: int) -> Array[Dictionary]:
	return [
		{
			"name": "unwrap_uv2",
			"default_value": false,
			"hint_string": "Unwrap UV2 coordinates for lightmap baking."
		},
		{
			"name": "uv2_texel_size",
			"default_value": 0.2,
			"hint_string": "The size of a texel",
		}
	]


func _get_option_visibility(path: String, option_name: StringName, options: Dictionary) -> bool:
	if option_name == "uv2_texel_size":
		return options.get("unwrap_uv2", false)
	return true


func _get_priority() -> float:
	return 1.0


func _get_import_order() -> int:
	return 0


func _import(source_file: String, save_path: String, options: Dictionary, platform_variants: Array[String], gen_files: Array[String]) -> Error:
	var file := FileAccess.open(source_file, FileAccess.READ)
	if not file:
		return FileAccess.get_open_error()
	
	# Read header
	var magic := file.get_buffer(2).get_string_from_ascii()
	if magic != "SP":
		printerr("Invalid SPM file: incorrect magic signature")
		return ERR_FILE_CORRUPT
	
	var version_type := file.get_8()
	var version := version_type >> 3
	var mesh_type := version_type & ~0x08
	
	if version != 1:
		printerr("Unsupported SPM version: ", version)
		return ERR_FILE_UNRECOGNIZED
	
	var mesh_properties := file.get_8()
	var has_normals := bool(mesh_properties & 1)
	var has_colors := bool(mesh_properties & 2)
	var has_tangents := bool(mesh_properties & 4)
	
	# Read bounding box
	# Convert from STK to Godot coordinate system
	var bbox_min := Vector3(file.get_float(), file.get_float(), -file.get_float())
	# Convert from STK to Godot coordinate system
	var bbox_max := Vector3(file.get_float(), file.get_float(), -file.get_float())
	
	# Read materials
	var num_materials := file.get_16()
	var materials: Array[Dictionary] = []
	
	for i in range(num_materials):
		var texture1_len := file.get_8()
		var texture1 := file.get_buffer(texture1_len).get_string_from_ascii()
		
		var texture2_len := file.get_8()
		var texture2 := file.get_buffer(texture2_len).get_string_from_ascii()
		
		materials.append({
			"texture1": texture1,
			"texture2": texture2
		})
	
	# Create the result mesh
	var result_mesh: ArrayMesh
	
	if mesh_type == MeshType.SPMA:
		result_mesh = _import_animated_mesh(file, has_normals, has_colors, has_tangents, materials, source_file)
	elif mesh_type == MeshType.SPMN:
		result_mesh = _import_normal_mesh(file, has_normals, has_colors, has_tangents, materials, source_file)
	else:
		printerr("Unsupported mesh type: ", mesh_type)
		return ERR_FILE_UNRECOGNIZED

	if options["unwrap_uv2"]:
		result_mesh.lightmap_unwrap(Transform3D.IDENTITY, options["uv2_texel_size"])
	
	return ResourceSaver.save(result_mesh, "%s.%s" % [save_path, _get_save_extension()])


func _import_normal_mesh(file: FileAccess, has_normals: bool, has_colors: bool, has_tangents: bool, materials: Array, source_file: String) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	
	# Read number of mesh sections
	var num_mesh_sections := file.get_16()
	
	for section_idx in range(num_mesh_sections):
		var num_submeshes := file.get_16()
		
		for submesh_idx in range(num_submeshes):
			var vertex_count := file.get_32()
			var index_count := file.get_32()
			var material_id := file.get_16()
			
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			
			# Read vertex data
			for i in range(vertex_count):
				# Position (always present)
				# Convert from STK (X+Y+Z+) to Godot (X+Y+Z-) coordinate system
				var position := Vector3(file.get_float(), file.get_float(), -file.get_float())
				
				# Normal (optional)
				var normal := Vector3.ZERO
				if has_normals:
					normal = _decode_10_10_10_2(file.get_32())
				
				# Color (optional)
				var color := Color.WHITE
				if has_colors:
					var color_id := file.get_8()
					if color_id == 128:
						color = Color.WHITE
					else:
						color = Color(file.get_8() / 255.0, file.get_8() / 255.0, file.get_8() / 255.0)
				
				# UV coordinates (always present in STK models)
				var uv := Vector2(_half_to_float(file.get_16()), _half_to_float(file.get_16()))
				
				# Second UV set (skipping for now)
				if materials[material_id].get("texture2", "") != "":
					file.get_16() # u2
					file.get_16() # v2
				
				# Tangent (optional)
				if has_tangents:
					var tangent_data := file.get_32()
					var tangent := _decode_10_10_10_2(tangent_data)
					var binormal_dir := (tangent_data >> 30) & 0x03
					
					if has_normals:
						st.set_normal(normal)
						st.set_tangent(Plane(tangent.x, tangent.y, tangent.z, float(binormal_dir)))
				elif has_normals:
					st.set_normal(normal)
				
				if has_colors:
					st.set_color(color)
				
				st.set_uv(uv)
				st.add_vertex(position)
			
			# Read indices
			var use_16bit_indices := vertex_count > 255
			
			# Process triangles (3 indices at a time) with reversed winding order
			for i in range(0, index_count, 3):
				var i1 := file.get_16() if use_16bit_indices else file.get_8()
				var i2 := file.get_16() if use_16bit_indices else file.get_8()
				var i3 := file.get_16() if use_16bit_indices else file.get_8()
				
				st.add_index(i1)
				st.add_index(i2)
				st.add_index(i3)
			
			var surface_arrays = st.commit_to_arrays()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_arrays)
			
			# Create and apply material if valid material ID
			if material_id < len(materials):
				var mat = _create_material(materials[material_id], source_file)
				mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	
	return mesh


func _import_animated_mesh(file: FileAccess, has_normals: bool, has_colors: bool, has_tangents: bool, materials: Array, source_file: String) -> ArrayMesh:
	# First import the normal mesh part
	var mesh := _import_normal_mesh(file, has_normals, has_colors, has_tangents, materials, source_file)
	
	# Read armature data
	var armature_count := file.get_8()
	var bind_frame := file.get_16()
	
	for armature_idx in range(armature_count):
		var used_joints := file.get_16()
		var total_joints := file.get_16()
		
		# Read joint names
		var joint_names := []
		for i in range(total_joints):
			var name_len := file.get_8()
			var joint_name := file.get_buffer(name_len).get_string_from_ascii()
			joint_names.append(joint_name)
		
		# Read joint matrices
		var joint_transforms := []
		for i in range(total_joints):
			# Convert from STK to Godot coordinate system
			var location := Vector3(file.get_float(), file.get_float(), -file.get_float())
			var rotation := Quaternion(file.get_float(), file.get_float(), file.get_float(), file.get_float())
			var scale := Vector3(file.get_float(), file.get_float(), file.get_float())
			
			var transform := Transform3D.IDENTITY
			transform = transform.scaled(scale)
			transform.basis = Basis(rotation)
			transform.origin = location
			
			joint_transforms.append(transform)
		
		# Read joint hierarchy
		var joint_parents := []
		for i in range(total_joints):
			var parent_id := file.get_16() # Actually int16, but Godot doesn't have signed get
			if parent_id >= 32768: # Convert from signed 16-bit
				parent_id = parent_id - 65536
			joint_parents.append(parent_id)
		
		# Read animation frames
		var frame_count := file.get_16()
		var animation_frames := []
		
		for frame_idx in range(frame_count):
			var frame_index := file.get_16()
			var frame_data := []
			
			for joint_idx in range(total_joints):
				# Convert from STK to Godot coordinate system
				var loc := Vector3(file.get_float(), file.get_float(), -file.get_float())
				var rot := Quaternion(file.get_float(), file.get_float(), file.get_float(), file.get_float())
				var scl := Vector3(file.get_float(), file.get_float(), file.get_float())
				
				frame_data.append({
					"location": loc,
					"rotation": rot,
					"scale": scl
				})
			
			animation_frames.append({
				"index": frame_index,
				"joints": frame_data
			})
	
	# Animated meshes would need to be processed further to create a proper Godot skeleton
	# This requires creating a Skeleton3D and attaching the mesh to it
	# For now, we're just returning the mesh without animation data
	
	return mesh


# Helper functions for decoding compressed data formats

# Decode a 10-10-10-2 format packed normal/tangent vector
func _decode_10_10_10_2(packed: int) -> Vector3:
	# Extract 10-bit components (bits 0-9 for x, 10-19 for y, 20-29 for z)
	var x_raw := int((packed >> 0) & 0x3FF)
	var y_raw := int((packed >> 10) & 0x3FF)
	var z_raw := int((packed >> 20) & 0x3FF)
	
	# Convert 10-bit signed format to float
	# Format is usually implemented as a 2's complement with range [-512, 511]
	# Each component is mapped to [-1, 1]
	var x: float
	var y: float
	var z: float
	
	# Check for negative numbers (bit 9 is sign bit)
	if x_raw & 0x200:
		x = float(x_raw - 1024) / 511.0 # Map [-512, -1] to [-1, -1/511]
	else:
		x = float(x_raw) / 511.0 # Map [0, 511] to [0, 1]
		
	if y_raw & 0x200:
		y = float(y_raw - 1024) / 511.0
	else:
		y = float(y_raw) / 511.0
		
	if z_raw & 0x200:
		z = float(z_raw - 1024) / 511.0
	else:
		z = float(z_raw) / 511.0
	
	# Convert from STK to Godot coordinate system
	return Vector3(x, y, -z).normalized()


# Convert a 16-bit half float to a 32-bit float
func _half_to_float(half: int) -> float:
	var sign := ((half >> 15) & 0x1) * -2.0 + 1.0
	var exp := (half >> 10) & 0x1F
	var mant := half & 0x3FF
	
	if exp == 0:
		if mant == 0:
			return 0.0
		else:
			return sign * pow(2.0, -14.0) * (mant / 1024.0)
	elif exp == 31:
		if mant == 0:
			return sign * INF
		else:
			return NAN
	
	return sign * pow(2.0, exp - 15.0) * (1.0 + mant / 1024.0)


# Create a material based on the SPM material data
func _create_material(material_data: Dictionary, source_file: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()

	# Set up basic material properties
	material.vertex_color_use_as_albedo = true

	# Get the directory of the source file
	var source_dir = source_file.get_base_dir()
	
	# Extract the texture names
	var texture1_path = material_data.get("texture1", "")
	var texture2_path = material_data.get("texture2", "")
	var texture1_name = texture1_path.get_file()
	var texture2_name = texture2_path.get_file()
	
	# XML material properties (to be filled later)
	var xml_material_props = {}
	
	# Search priority for materials.xml:
	# 1. Track directory (where the .spm file is)
	# 2. res://textures/materials.xml (Godot project global file)
	# 3. SuperTuxKart-1.4-linux-x86_64/data/textures/materials.xml (STK global file)
	var track_xml_path = source_dir.path_join("materials.xml")
	var global_xml_path = ""
	
	# Check if global materials.xml exists in the Godot project
	var godot_global_xml = "res://textures/materials.xml"
	if ResourceLoader.exists(godot_global_xml):
		global_xml_path = ProjectSettings.globalize_path(godot_global_xml)
	
	# If not found, try to find the SuperTuxKart soft link
	if global_xml_path.is_empty() or !FileAccess.file_exists(global_xml_path):
		var addon_dir = source_dir
		while !addon_dir.ends_with("addons") and addon_dir != addon_dir.get_base_dir():
			addon_dir = addon_dir.get_base_dir()
		
		if addon_dir.ends_with("addons"):
			var stk_dir = addon_dir.path_join("atirut-w.stk-fmt/SuperTuxKart-1.4-linux-x86_64") 
			if DirAccess.dir_exists_absolute(stk_dir):
				global_xml_path = stk_dir.path_join("data/textures/materials.xml")
	
	# First check track-specific materials.xml
	if FileAccess.file_exists(track_xml_path) and !texture1_name.is_empty():
		var track_props = _load_material_properties_from_xml(track_xml_path, texture1_name)
		if !track_props.is_empty():
			xml_material_props = track_props
		
	# If not found in track materials.xml, check global materials.xml
	if xml_material_props.is_empty() and FileAccess.file_exists(global_xml_path) and !texture1_name.is_empty():
		var global_props = _load_material_properties_from_xml(global_xml_path, texture1_name)
		if !global_props.is_empty():
			xml_material_props = global_props
	
	# Determine texture search paths
	var texture_search_paths = [
		source_dir, # First look in the track directory
		source_dir.path_join("textures"), # Then look in textures subdirectory
	]
	
	# Add Godot's project textures directory
	var project_textures_dir = ProjectSettings.globalize_path("res://textures")
	if DirAccess.dir_exists_absolute(project_textures_dir):
		texture_search_paths.append(project_textures_dir)
	
	# Add STK textures directory if available
	if FileAccess.file_exists(global_xml_path):
		var textures_dir = global_xml_path.get_base_dir()
		texture_search_paths.append(textures_dir)
	
	# Load and assign the main texture if available
	if texture1_path != "":
		var texture = _load_texture(texture1_path, texture_search_paths)
		if texture:
			material.albedo_texture = texture

	# Process second texture
	if texture2_path != "":
		var texture = _load_texture(texture2_path, texture_search_paths)
		if texture:
			# Check if this is a normal map according to materials.xml
			if xml_material_props.has("normal-map") and xml_material_props["normal-map"] == texture2_name:
				material.normal_enabled = true
				material.normal_texture = texture
			else:
				# In STK, second texture is often used as normal map if not specified
				material.normal_enabled = true
				material.normal_texture = texture

	# Apply material properties from materials.xml if available
	if not xml_material_props.is_empty():
		_apply_xml_material_properties(material, xml_material_props, texture_search_paths)

	return material


# Load material properties from materials.xml file
func _load_material_properties_from_xml(xml_path: String, material_name: String) -> Dictionary:
	var material_props := {}
	var xml := XMLParser.new()
	var error := xml.open(xml_path)

	if error != OK:
		push_error("Failed to open materials.xml: ", error)
		return material_props
	
	# Track when we've found the matching material
	var in_target_material := false
	var current_material_name := ""
	
	# Get just the filename part if it's a path
	var material_filename := material_name.get_file()
	if material_filename.is_empty():
		material_filename = material_name

	# Parse the XML
	while xml.read() == OK:
		var node_type := xml.get_node_type()

		if node_type == XMLParser.NODE_ELEMENT:
			var node_name := xml.get_node_name()

			# Look for material nodes
			if node_name == "material":
				# Reset material state
				current_material_name = ""
				in_target_material = false
				
				# Check all attributes for name match
				for i in range(xml.get_attribute_count()):
					var attr_name := xml.get_attribute_name(i)
					var attr_value := xml.get_attribute_value(i)

					if attr_name == "name":
						current_material_name = attr_value
						var current_filename := current_material_name.get_file()
						if current_filename.is_empty():
							current_filename = current_material_name
						
						# Try exact match first, then filename-only match
						if current_material_name == material_name || current_filename == material_filename:
							in_target_material = true
					
					# Only store the attribute if we're in the target material and we've confirmed the name match
					if in_target_material:
						material_props[attr_name] = attr_value
			
			# Child elements like <sfx>, <zipper>, <particles>, etc.
			elif in_target_material:
				# Store the element type (will be overwritten by attributes)
				material_props[node_name] = "yes"
				
				# Store any attributes of child elements
				for i in range(xml.get_attribute_count()):
					var attr_name := xml.get_attribute_name(i)
					var attr_value := xml.get_attribute_value(i)
					var prefixed_name = node_name + "-" + attr_name
					material_props[prefixed_name] = attr_value

		# Exit when we're done with the material
		elif node_type == XMLParser.NODE_ELEMENT_END and xml.get_node_name() == "material" and in_target_material:
			in_target_material = false
			break
		
	return material_props


# Apply properties from materials.xml to a Godot material
func _apply_xml_material_properties(material: StandardMaterial3D, props: Dictionary, search_dirs: Array) -> void:
	# Handle shader types
	if props.has("shader"):
		var shader_type = props["shader"].to_lower()
		match shader_type:
			"alphatest":
				material.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				material.alpha_scissor_threshold = 0.5
			"alphablend":
				material.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
			"additive":
				material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			"unlit":
				material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_:
				push_warning("Unknown shader type: %s" % shader_type)


# Helper function to load textures
func _load_texture(texture_path: String, search_dirs: Array) -> Texture2D:
	var texture_file = texture_path.get_file()
	
	for base_dir in search_dirs:
		# First try the exact path as provided
		var full_path = base_dir.path_join(texture_path)
		if ResourceLoader.exists(full_path):
			var texture = ResourceLoader.load(full_path)
			if texture is Texture2D:
				return texture
		
		# Then try with just the filename in each search dir
		full_path = base_dir.path_join(texture_file)
		if ResourceLoader.exists(full_path):
			var texture = ResourceLoader.load(full_path)
			if texture is Texture2D:
				return texture
	
	# Also try Godot's resource path
	var res_path = "res://textures/%s" % [texture_file]
	if ResourceLoader.exists(res_path):
		var texture = ResourceLoader.load(res_path)
		if texture is Texture2D:
			return texture

	push_warning("Texture not found: %s" % texture_path)
	return null
