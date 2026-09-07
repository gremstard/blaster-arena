class_name OperatorAnimator
extends Node
# Drives retargeted humanoid animations on an operator model. Clips come from the
# Universal Animation Library (CC0, Quaternius); track paths are rewritten to the
# model's own Skeleton3D so one library serves every operator.

const LIBRARY_PATH := "res://assets/animations/UAL1_Standard.glb"
const BLEND := 0.15

static var _clips := {} # name -> Animation (paths relative to "Skeleton3D:Bone")
static var _loaded := false

var player: AnimationPlayer
var skeleton: Skeleton3D
var current := ""
var dead := false


static func _load_clips() -> void:
	if _loaded:
		return
	_loaded = true
	if not ResourceLoader.exists(LIBRARY_PATH):
		return
	var scene: Node = load(LIBRARY_PATH).instantiate()
	for ap in scene.find_children("*", "AnimationPlayer", true, false):
		for name in ap.get_animation_list():
			_clips[name] = ap.get_animation(name)
	scene.free()


# Attach to a model instance. Returns false if the model has no compatible skeleton.
func setup(model: Node3D) -> bool:
	_load_clips()
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	skeleton = skeletons[0] as Skeleton3D if skeletons.size() > 0 else null
	if skeleton == null or _clips.is_empty() or skeleton.find_bone("Hips") < 0:
		return false
	# Drop any animation baked into the model (usually a pose)
	for ap in model.find_children("*", "AnimationPlayer", true, false):
		ap.stop()
		ap.queue_free()
	player = AnimationPlayer.new()
	model.add_child(player)
	player.root_node = player.get_path_to(model)
	var lib := AnimationLibrary.new()
	var skel_path := model.get_path_to(skeleton)
	for name in _clips:
		lib.add_animation(name, _retarget(_clips[name], skel_path))
	player.add_animation_library("ual", lib)
	return true


static func _retarget(src: Animation, skel_path: NodePath) -> Animation:
	var anim: Animation = src.duplicate(true)
	for i in anim.get_track_count():
		var p := anim.track_get_path(i)
		if p.get_subname_count() > 0:
			anim.track_set_path(i, NodePath(String(skel_path) + ":" + p.get_subname(0)))
	return anim


func play(name: String, loop := true, speed := 1.0) -> void:
	if player == null or not player.has_animation("ual/" + name):
		return
	var anim := player.get_animation("ual/" + name)
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	if current != name:
		current = name
		player.play("ual/" + name, BLEND, speed)
	else:
		player.speed_scale = speed


# Pick a clip from movement state
func update(speed: float, grounded: bool, is_dead: bool, sidearm: bool) -> void:
	if player == null:
		return
	if is_dead:
		if not dead:
			dead = true
			play("Death01", false)
		return
	dead = false
	if not grounded:
		play("Jump", false)
	elif speed > 7.5:
		play("Sprint", true, clamp(speed / 9.0, 0.8, 1.4))
	elif speed > 3.0:
		play("Jog_Fwd", true, clamp(speed / 5.5, 0.7, 1.4))
	elif speed > 0.3:
		play("Walk", true, clamp(speed / 2.0, 0.6, 1.5))
	else:
		play("Pistol_Idle" if sidearm else "Idle")


func right_hand_attachment() -> BoneAttachment3D:
	if skeleton == null:
		return null
	var att := BoneAttachment3D.new()
	att.bone_name = "RightHand"
	skeleton.add_child(att)
	return att
