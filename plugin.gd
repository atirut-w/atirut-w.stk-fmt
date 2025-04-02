@tool
extends EditorPlugin


var _spm_plugin : SPMImportPlugin


func _enter_tree() -> void:
	_spm_plugin = SPMImportPlugin.new()
	add_import_plugin(_spm_plugin)


func _exit_tree() -> void:
	remove_import_plugin(_spm_plugin)
	_spm_plugin = null
