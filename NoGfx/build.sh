#!/usr/bin/env sh
set -e

########################################################################################################################
# BUILD CONFIG
########################################################################################################################
CPP=c++
AR=ar
METAL="xcrun -sdk macosx metal"
METALLIB="xcrun -sdk macosx metallib"
BUILD_FOLDER="./build"

SHADER_SOURCES=("./src/lib/metal4/shader/acquire_icb_range.metal" "./src/lib/metal4/shader/prep_multidrawindirect.metal")
SHADER_REFLECTED_NAMES=("gMtl4AcquireIcbRangeBytecode" "gMtl4PrepareMultidrawIndirectIcbsBytecode")
DBG_METAL_ARGS=("-frecord-sources" "-gline-tables-only")
REL_METAL_ARGS=("-O2")

BUILD_FILE="./src/_build/build.cpp"
ARTIFACT="libgpu.a"
INCLUDE_FOLDERS=("./include" "./src")
DBG_CPP_ARGS=(																\
	"-std=c++11" "-xobjective-c++" "-fno-objc-arc"							\
	"-Wall" "-Wextra" "-Wpedantic"											\
	"-fvisibility-inlines-hidden" "-fvisibility=hidden"						\
	"-fno-exceptions" "-fno-rtti" "-nostdlib++"								\
	"-fno-unwind-tables" "-fno-asynchronous-unwind-tables"					\
	"-g"																	\
)
REL_CPP_ARGS=(																\
	"-std=c++11" "-xobjective-c++" "-fno-objc-arc"							\
	"-Wall" "-Wextra" "-Wpedantic"											\
	"-fvisibility-inlines-hidden" "-fvisibility=hidden"						\
	"-fno-exceptions" "-fno-rtti" "-nostdlib++"								\
	"-fno-unwind-tables" "-fno-asynchronous-unwind-tables"					\
	"-O2"																	\
)


########################################################################################################################
# BUILD
########################################################################################################################
if [[ "$1" = "rel" ]]; then
	METAL_ARGS=("${REL_METAL_ARGS[@]}")
	CPP_ARGS=("${REL_CPP_ARGS[@]}")
else
	METAL_ARGS=("${DBG_METAL_ARGS[@]}")
	CPP_ARGS=("${DBG_CPP_ARGS[@]}")
fi


for i in "${!SHADER_SOURCES[@]}"; do
	shaderSource="${SHADER_SOURCES[$i]}"
	shaderFile=$(basename "$shaderSource")
	shaderName="${SHADER_REFLECTED_NAMES[$i]}"
	airFile="$BUILD_FOLDER"/"$shaderFile.air"
	metallibFile="$BUILD_FOLDER"/"$shaderFile.metal"

	$METAL "${METAL_ARGS[@]}" -c "$shaderSource" -o "$BUILD_FOLDER"/"$shaderFile.air"
	$METALLIB "$airFile" -o "$metallibFile"
	./tools/bin2cpp.py "$metallibFile" -o "$shaderSource".cpp -H "$shaderSource".h -v "$shaderName"
done

for include in "${INCLUDE_FOLDERS[@]}"; do
	CPP_ARGS+=("-I$include")
done

$CPP "${CPP_ARGS[@]}" -c "$BUILD_FILE" -o "$BUILD_FOLDER"/"$ARTIFACT".o 
$AR rcs "$BUILD_FOLDER"/"$ARTIFACT" "$BUILD_FOLDER"/"$ARTIFACT".o

