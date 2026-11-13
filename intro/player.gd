extends CharacterBody3D
## Third-person knight: WASD move, Shift sprint, Space jump, mouse look, click to swing.
## The camera rides a SpringArm3D so it never clips through castle walls.

signal swung

const B := preload("res://intro/build.gd")
const SPEED := 4.5
const SPRINT := 8.0
const JUMP := 5.6
const GRAVITY := 14.0

var controls_enabled := false
var yaw := 0.0
var pitch := -0.28
var pivot: Node3D
var arm: SpringArm3D
var cam: Camera3D
var visual: Node3D
var body: Node3D
var sword: Node3D
var want_jump := false
var swinging := false
var walk_t := 0.0
var spawn := Vector3.ZERO


func _ready() -> void:
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	floor_snap_length = 0.4

	visual = Node3D.new()
	add_child(visual)
	body = B.knight(Color(0.12, 0.2, 0.5), Color(0.85, 0.1, 0.1))
	visual.add_child(body)
	# sword in the right hand
	sword = Node3D.new()
	sword.position = Vector3(0.4, 0.9, -0.05)
	sword.rotation.x = -0.45
	body.add_child(sword)
	var steel := B.mat(Color(0.85, 0.87, 0.9), 0.2, 0.95)
	B.box(sword, Vector3(0, 0.55, 0), Vector3(0.06, 0.95, 0.015), steel, false)
	B.box(sword, Vector3(0, 0.07, 0), Vector3(0.28, 0.05, 0.05), B.mat(Color(0.8, 0.65, 0.2), 0.3, 0.9), false)
	B.box(sword, Vector3(0, -0.06, 0), Vector3(0.05, 0.2, 0.05), B.mat(Color(0.25, 0.14, 0.06)), false)
	# shield on the left arm
	var shield := B.box(body, Vector3(-0.5, 1.1, -0.08), Vector3(0.05, 0.62, 0.46), B.mat(Color(0.12, 0.2, 0.5)), false)
	B.sphere(shield, Vector3(-0.03, 0, 0), 0.08, B.mat(Color(0.9, 0.75, 0.3), 0.3, 0.9))
	# cape
	B.banner(body, Vector3(0, 1.5, 0.3), Vector2(0.62, 1.25), B.cloth(Color(0.5, 0.05, 0.07), false, 0.07))

	pivot = Node3D.new()
	pivot.top_level = true
	add_child(pivot)
	arm = SpringArm3D.new()
	arm.spring_length = 5.0
	arm.margin = 0.3
	var ball := SphereShape3D.new()
	ball.radius = 0.25
	arm.shape = ball
	arm.add_excluded_object(get_rid())
	pivot.add_child(arm)
	cam = Camera3D.new()
	cam.fov = 68
	cam.far = 400
	arm.add_child(cam)
	spawn = global_position


func facing() -> Vector3:
	return -visual.global_basis.z


func face(dir: Vector3) -> void:
	visual.rotation.y = atan2(-dir.x, -dir.z)


func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * 0.004
		pitch = clampf(pitch - event.relative.y * 0.004, -1.2, 0.45)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				swing()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			arm.spring_length = maxf(arm.spring_length - 0.5, 2.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			arm.spring_length = minf(arm.spring_length + 0.5, 9.0)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			want_jump = true
		elif event.keycode == KEY_F:
			swing()


func swing() -> void:
	if swinging:
		return
	swinging = true
	var tw := create_tween()
	tw.tween_property(sword, "rotation", Vector3(0.6, 0.0, 0.5), 0.12)
	tw.tween_callback(func(): swung.emit())
	tw.tween_property(sword, "rotation", Vector3(-2.0, 0.0, -0.6), 0.14).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(sword, "rotation", Vector3(-0.45, 0.0, 0.0), 0.3).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func(): swinging = false)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	var dir := Vector3.ZERO
	var sprint := false
	if controls_enabled:
		var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
		var right := Vector3(cos(yaw), 0, -sin(yaw))
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): dir += fwd
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): dir -= fwd
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): dir += right
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): dir -= right
		dir = dir.normalized()
		sprint = Input.is_key_pressed(KEY_SHIFT)
		if want_jump and is_on_floor():
			velocity.y = JUMP
	want_jump = false
	var target := dir * (SPRINT if sprint else SPEED)
	var accel := 12.0 if is_on_floor() else 3.0
	velocity.x = lerpf(velocity.x, target.x, 1.0 - exp(-accel * delta))
	velocity.z = lerpf(velocity.z, target.z, 1.0 - exp(-accel * delta))
	if dir != Vector3.ZERO:
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-dir.x, -dir.z), 1.0 - exp(-12.0 * delta))
	move_and_slide()
	# shove crates and barrels we walk into
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var rb := c.get_collider() as RigidBody3D
		if rb:
			rb.apply_central_impulse(-c.get_normal() * 0.6)
	if global_position.y < -15.0:
		global_position = spawn
		velocity = Vector3.ZERO

	var hspeed := Vector2(velocity.x, velocity.z).length()
	walk_t += hspeed * delta * 2.2
	body.position.y = absf(sin(walk_t)) * 0.06 * clampf(hspeed / SPEED, 0.0, 1.0)
	body.rotation.z = sin(walk_t) * 0.04 * clampf(hspeed / SPEED, 0.0, 1.0)


func _process(delta: float) -> void:
	var tgt := global_position + Vector3(0, 1.7, 0)
	pivot.global_position = pivot.global_position.lerp(tgt, 1.0 - exp(-14.0 * delta))
	pivot.rotation = Vector3(pitch, yaw, 0)
