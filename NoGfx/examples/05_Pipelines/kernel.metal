#include <metal_stdlib>

using namespace metal;

struct Arguments {
	device const uint* left;
	device const uint* right;
	device uint* result;
};

[[host_name("main")]]
kernel void add(
	uint index [[thread_position_in_grid]],
	device const Arguments* arguments [[buffer(0)]]
) {
	arguments->result[index] = arguments->left[index] + arguments->right[index];
}
