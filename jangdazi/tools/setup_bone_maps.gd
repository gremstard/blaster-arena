extends SceneTree
# Writes humanoid BoneMaps into the .import settings of the operator models and the
# animation library so Godot retargets them all onto the standard humanoid profile.
# Usage: Godot --headless --path . --script tools/setup_bone_maps.gd   (then run --import)

const SIDES := {"Left": "l", "Right": "r"}
const FINGERS := {"Thumb": "thumb", "Index": "index", "Middle": "middle", "Ring": "ring", "Little": "pinky"}

static func ue_map(head: String, chest: String, upper_chest: String, root: String) -> Dictionary:
	var m := {"Hips": "pelvis", "Spine": "spine_01", "Chest": chest, "UpperChest": upper_chest, "Neck": "neck_01", "Head": head}
	if not root.is_empty():
		m["Root"] = root
	for side in SIDES:
		var s: String = SIDES[side]
		m[side + "Shoulder"] = "clavicle_" + s
		m[side + "UpperArm"] = "upperarm_" + s
		m[side + "LowerArm"] = "lowerarm_" + s
		m[side + "Hand"] = "hand_" + s
		m[side + "UpperLeg"] = "thigh_" + s
		m[side + "LowerLeg"] = "calf_" + s
		m[side + "Foot"] = "foot_" + s
		m[side + "Toes"] = "ball_" + s
		for f in FINGERS:
			var b: String = FINGERS[f]
			if f == "Thumb":
				m[side + "ThumbMetacarpal"] = "thumb_01_" + s
				m[side + "ThumbProximal"] = "thumb_02_" + s
				m[side + "ThumbDistal"] = "thumb_03_" + s
			else:
				m[side + f + "Proximal"] = b + "_01_" + s
				m[side + f + "Intermediate"] = b + "_02_" + s
				m[side + f + "Distal"] = b + "_03_" + s
	return m

static func mixamo_map() -> Dictionary:
	var p := "mixamorig_"
	var m := {"Hips": p + "Hips", "Spine": p + "Spine", "Chest": p + "Spine1", "UpperChest": p + "Spine2", "Neck": p + "Neck", "Head": p + "Head"}
	for side in SIDES:
		m[side + "Shoulder"] = p + side + "Shoulder"
		m[side + "UpperArm"] = p + side + "Arm"
		m[side + "LowerArm"] = p + side + "ForeArm"
		m[side + "Hand"] = p + side + "Hand"
		m[side + "UpperLeg"] = p + side + "UpLeg"
		m[side + "LowerLeg"] = p + side + "Leg"
		m[side + "Foot"] = p + side + "Foot"
		m[side + "Toes"] = p + side + "ToeBase"
		for f in ["Thumb", "Index", "Middle", "Ring", "Little"]:
			var mf: String = "Pinky" if f == "Little" else f
			var names: Array = ["Metacarpal", "Proximal", "Distal"] if f == "Thumb" else ["Proximal", "Intermediate", "Distal"]
			for i in 3:
				m[side + f + names[i]] = p + side + "Hand" + mf + str(i + 1)
	return m

func _init():
	var jobs := {
		"res://assets/animations/UAL1_Standard.glb": ["Armature/Skeleton3D", ue_map("Head", "spine_02", "spine_03", "root")],
		"res://assets/FBX/SKM_Character.fbx": ["root/Skeleton3D", ue_map("head", "spine_03", "spine_05", "")],
		"res://assets/fsb-operator/fsb.glb": ["Armature/Skeleton3D", mixamo_map()],
	}
	for path in jobs:
		var skel_path: String = jobs[path][0]
		var mapping: Dictionary = jobs[path][1]
		var bm := BoneMap.new()
		bm.profile = SkeletonProfileHumanoid.new()
		for profile_bone in mapping:
			bm.set_skeleton_bone_name(profile_bone, mapping[profile_bone])
		var cfg := ConfigFile.new()
		var err := cfg.load(path + ".import")
		if err != OK:
			print("no .import for ", path); continue
		var subs = cfg.get_value("params", "_subresources", {})
		if not subs.has("nodes"):
			subs["nodes"] = {}
		subs["nodes"]["PATH:" + skel_path] = {
			"retarget/bone_map": bm,
			"retarget/bone_renamer/rename_bones": true,
			"retarget/bone_renamer/unique_node/make_unique": true,
			"retarget/rest_fixer/apply_node_transforms": true,
			"retarget/rest_fixer/normalize_position_tracks": true,
			"retarget/rest_fixer/reset_all_bone_poses_after_import": true,
			"retarget/rest_fixer/overwrite_axis": true,
			"retarget/rest_fixer/keep_global_rest_on_leftovers": true,
			"retarget/rest_fixer/fix_silhouette/enable": true,
			"retarget/rest_fixer/fix_silhouette/threshold": 15.0,
			"retarget/remove_tracks/except_bone_transform": false,
			"retarget/remove_tracks/unimportant_positions": true,
			"retarget/remove_tracks/unmapped_bones": false,
		}
		cfg.set_value("params", "_subresources", subs)
		cfg.save(path + ".import")
		print("bone map written for ", path, " (", mapping.size(), " bones)")
	quit()
