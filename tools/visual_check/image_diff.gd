class_name ImageDiff
extends RefCounted
## Compares a baseline render with a new render of the same shot.

## Renders are compared at this width: fast enough in GDScript, and it ignores sub-pixel noise.
const COMPARE_WIDTH := 800
const CHANGED_COLOR := Color(1.0, 0.1, 0.1)
## Unchanged pixels are drawn as dimmed greyscale in the diff, for context.
const CONTEXT_DIM := 0.35


class Result extends RefCounted:
	## Fraction of pixels that differ by more than the threshold (0..1).
	var changed_ratio: float = 0.0
	## Largest per-channel difference found (0..1).
	var max_difference: float = 0.0
	## Baseline | actual | diff, side by side.
	var composite: Image


static func compare(baseline: Image, actual: Image, pixel_threshold: float) -> Result:
	var size := _compare_size(baseline)
	var expected := _prepared(baseline, size)
	var rendered := _prepared(actual, size)
	var diff := Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	var result := Result.new()
	var changed := 0
	for y in range(size.y):
		for x in range(size.x):
			var a := expected.get_pixel(x, y)
			var b := rendered.get_pixel(x, y)
			var difference := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
			result.max_difference = maxf(result.max_difference, difference)
			if difference > pixel_threshold:
				changed += 1
				diff.set_pixel(x, y, CHANGED_COLOR)
			else:
				var grey := b.get_luminance() * CONTEXT_DIM
				diff.set_pixel(x, y, Color(grey, grey, grey))
	result.changed_ratio = float(changed) / float(size.x * size.y)
	result.composite = _side_by_side([expected, rendered, diff])
	return result


static func _compare_size(image: Image) -> Vector2i:
	var height := roundi(float(COMPARE_WIDTH) * image.get_height() / image.get_width())
	return Vector2i(COMPARE_WIDTH, height)


static func _prepared(image: Image, size: Vector2i) -> Image:
	var copy := image.duplicate() as Image
	copy.convert(Image.FORMAT_RGB8)
	copy.resize(size.x, size.y, Image.INTERPOLATE_BILINEAR)
	return copy


static func _side_by_side(images: Array[Image]) -> Image:
	var width := images[0].get_width()
	var height := images[0].get_height()
	var composite := Image.create(width * images.size(), height, false, Image.FORMAT_RGB8)
	for i in range(images.size()):
		composite.blit_rect(images[i], Rect2i(0, 0, width, height), Vector2i(width * i, 0))
	return composite
