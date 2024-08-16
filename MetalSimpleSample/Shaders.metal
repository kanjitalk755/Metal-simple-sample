#include <metal_stdlib>

using namespace metal;

struct Prim {
	float2 position;
	float hue, angle;
};

struct Vtx {
	float2 position;
	float4 color;
};

struct ShaderData {
	float4 position [[position]];
	float4 color;
};

kernel void geometryShader(constant Prim *in [[ buffer(0) ]], device Vtx *out [[ buffer(1) ]], uint id [[ thread_position_in_grid ]]) {
	const float SIZE = 10, T = 2 * M_PI_F / 3;
	constant Prim &i = in[id];
	uint oid = 3 * id;
	out[oid    ].position = i.position + float2(SIZE * cos(i.angle),     SIZE * sin(i.angle));
	out[oid + 1].position = i.position + float2(SIZE * cos(i.angle + T), SIZE * sin(i.angle + T));
	out[oid + 2].position = i.position + float2(SIZE * cos(i.angle - T), SIZE * sin(i.angle - T));
	out[oid].color = out[oid + 1].color = out[oid + 2].color = float4(.5 + .5 * sin(i.hue), .5 + .5 * sin(i.hue + T), .5 + .5 * sin(i.hue - T), 1);
}

vertex ShaderData VertexShader(const device Vtx *vtx [[buffer(0)]], constant float2 *size [[buffer(1)]], uint id [[vertex_id]]) {
	ShaderData data;
	data.position = float4(vtx[id].position.x / (.5 * size->x) - 1, vtx[id].position.y / (.5 * size->y) - 1, 0, 1);
	data.color = vtx[id].color;
	return data;
}

fragment float4 FragmentShader(ShaderData in [[stage_in]]) {
	return in.color;
}
