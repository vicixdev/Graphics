#include <metal_stdlib>

using namespace metal;

constant uint computeScale [[function_constant(0)]];

[[host_name("main")]] kernel void computeMain() {
	if (computeScale > 0) {}
}
