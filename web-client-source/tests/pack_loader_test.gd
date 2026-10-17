extends SceneTree

const DubPack = preload("res://dub_pack.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var root := ProjectSettings.globalize_path(args[0]) if not args.is_empty() else ""
	if root.is_empty() or not DirAccess.dir_exists_absolute(root):
		printerr("PACK_TEST_FAIL missing pack root")
		quit(2)
		return
	var failures := 0
	var tested := 0
	for folder_name in DirAccess.get_directories_at(root):
		var folder := root.path_join(folder_name)
		# The regular tutorial voice pack is intentionally not a Video Dub.
		if _find_video(folder).is_empty():
			continue
		tested += 1
		var loaded := DubPack.load_from_folder(folder)
		if not bool(loaded.get("ok", false)):
			failures += 1
			printerr("PACK_TEST_FAIL %s: %s" % [folder_name, loaded.get("error", "unknown")])
		else:
			print("PACK_TEST_OK %s (%d timed lines)" % [folder_name, loaded.lines.size()])
	print("PACK_TEST_SUMMARY tested=%d failures=%d" % [tested, failures])
	quit(1 if failures else 0)


func _find_video(folder: String) -> String:
	for file_name in DirAccess.get_files_at(folder):
		if file_name.get_basename().to_lower() == "dub_video" and file_name.get_extension().to_lower() == "ogv":
			return folder.path_join(file_name)
	return ""
