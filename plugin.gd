@tool
extends EditorPlugin


var _spm_plugin : SPMImportPlugin
var _track_importer : TrackImportPlugin


func _enter_tree() -> void:
	_spm_plugin = SPMImportPlugin.new()
	add_import_plugin(_spm_plugin)
	
	_track_importer = TrackImportPlugin.new()
	add_scene_format_importer_plugin(_track_importer)


func _exit_tree() -> void:
	remove_import_plugin(_spm_plugin)
	_spm_plugin = null
	
	remove_scene_format_importer_plugin(_track_importer)
	_track_importer = null