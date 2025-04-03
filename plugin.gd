@tool
extends EditorPlugin


var _spm_plugin : SPMImportPlugin
var _track_plugin : TrackImportPlugin


func _enter_tree() -> void:
	_spm_plugin = SPMImportPlugin.new()
	add_import_plugin(_spm_plugin)
	
	_track_plugin = TrackImportPlugin.new()
	add_import_plugin(_track_plugin)


func _exit_tree() -> void:
	remove_import_plugin(_spm_plugin)
	_spm_plugin = null
	
	remove_import_plugin(_track_plugin)
	_track_plugin = null
