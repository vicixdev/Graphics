#include <metal_stdlib>
using namespace metal;

[[host_name("main")]]
fragment float4 fragmentMain() {
        return float4(1.0, 1.0, 1.0, 1.0);
}
