class_name SPMImportPlugin
extends EditorImportPlugin


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
	return [{}]


func _get_priority() -> float:
	return 1.0


func _import(source_file: String, save_path: String, options: Dictionary, platform_variants: Array[String], gen_files: Array[String]) -> Error:
	# TODO: Actually import the SPM file here.
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1, 1, 1)

	return ResourceSaver.save(mesh, "%s.%s" % [save_path, _get_save_extension()])
