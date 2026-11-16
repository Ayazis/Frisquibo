#[compute]
#version 450
// Box-filters one mip level of the three ocean texture arrays into the next. Averaging squared slopes
// keeps the slope variance of distant, sub-pixel waves, which the surface shader turns into roughness.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba16f) uniform restrict readonly image2D src_displacement;
layout(set = 0, binding = 1, rgba16f) uniform restrict readonly image2D src_slope;
layout(set = 0, binding = 2, rgba16f) uniform restrict readonly image2D src_moments;
layout(set = 0, binding = 3, rgba16f) uniform restrict writeonly image2D dst_displacement;
layout(set = 0, binding = 4, rgba16f) uniform restrict writeonly image2D dst_slope;
layout(set = 0, binding = 5, rgba16f) uniform restrict writeonly image2D dst_moments;

layout(push_constant, std430) uniform Params {
	int dst_size;
	int pad0;
	int pad1;
	int pad2;
} p;

void main() {
	ivec2 d = ivec2(gl_GlobalInvocationID.xy);
	if (d.x >= p.dst_size || d.y >= p.dst_size) {
		return;
	}
	ivec2 s = d * 2;
	ivec2 dx = ivec2(1, 0);
	ivec2 dy = ivec2(0, 1);
	imageStore(dst_displacement, d, 0.25 * (imageLoad(src_displacement, s) + imageLoad(src_displacement, s + dx)
			+ imageLoad(src_displacement, s + dy) + imageLoad(src_displacement, s + dx + dy)));
	imageStore(dst_slope, d, 0.25 * (imageLoad(src_slope, s) + imageLoad(src_slope, s + dx)
			+ imageLoad(src_slope, s + dy) + imageLoad(src_slope, s + dx + dy)));
	imageStore(dst_moments, d, 0.25 * (imageLoad(src_moments, s) + imageLoad(src_moments, s + dx)
			+ imageLoad(src_moments, s + dy) + imageLoad(src_moments, s + dx + dy)));
}
