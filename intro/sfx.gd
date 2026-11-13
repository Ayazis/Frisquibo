extends RefCounted
## Procedurally synthesised sound effects (no audio files): bell, clank, whoosh, thud, wind loop.

const RATE := 22050


static func _wav(s: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(s.size() * 2)
	for i in s.size():
		data.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = s.size()
	return w


static func bell() -> AudioStreamWAV:
	var n := RATE * 4
	var s := PackedFloat32Array()
	s.resize(n)
	var ratio := PackedFloat32Array([0.5, 1.0, 1.19, 1.5, 2.0, 2.74, 3.0, 4.07])
	var amp := PackedFloat32Array([0.5, 1.0, 0.6, 0.45, 0.5, 0.3, 0.2, 0.15])
	var decay := PackedFloat32Array([2.5, 1.8, 1.3, 1.0, 0.8, 0.5, 0.4, 0.25])
	var f0 := 196.0
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for k in ratio.size():
			v += sin(TAU * f0 * ratio[k] * t) * amp[k] * exp(-t / decay[k])
		s[i] = v * 0.22 * minf(t * 300.0, 1.0)
	return _wav(s)


static func clank() -> AudioStreamWAV:
	var n := int(RATE * 0.6)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	for i in n:
		var t := float(i) / RATE
		var v := (sin(TAU * 520.0 * t) + sin(TAU * 1370.0 * t) * 0.6 + sin(TAU * 2210.0 * t) * 0.4) * exp(-t * 9.0)
		v += rng.randf_range(-1, 1) * exp(-t * 40.0)
		s[i] = v * 0.35
	return _wav(s)


static func chain() -> AudioStreamWAV:
	var n := RATE * 3
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var click := 1.0 if fmod(t, 0.09) < 0.004 else 0.0
		lp = lerpf(lp, rng.randf_range(-1, 1), 0.3)
		s[i] = (click * rng.randf_range(0.3, 1.0) + lp * 0.25) * 0.4 * minf((3.0 - t) * 3.0, 1.0)
	return _wav(s)


static func whoosh() -> AudioStreamWAV:
	var n := int(RATE * 0.3)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	var lp := 0.0
	for i in n:
		var t := float(i) / n
		lp = lerpf(lp, rng.randf_range(-1, 1), 0.05 + 0.4 * t)
		s[i] = lp * sin(PI * t) * 1.2
	return _wav(s)


static func thud() -> AudioStreamWAV:
	var n := int(RATE * 0.35)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp = lerpf(lp, rng.randf_range(-1, 1), 0.25)
		s[i] = (sin(TAU * 85.0 * t) * exp(-t * 14.0) + lp * exp(-t * 22.0)) * 0.7
	return _wav(s)


static func wind() -> AudioStreamWAV:
	var n := RATE * 8
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / n
		lp = lerpf(lp, rng.randf_range(-1, 1), 0.02)
		lp2 = lerpf(lp2, lp, 0.1)
		s[i] = lp2 * (0.6 + 0.4 * sin(TAU * t * 2.0)) * 3.0
	# crossfade the loop seam
	var xf := RATE / 2
	for i in xf:
		var a := float(i) / xf
		s[i] = s[i] * a + s[n - xf + i] * (1.0 - a)
	s.resize(n - xf)
	return _wav(s, true)
