#!/bin/sh

usage () {
	echo "Description:"
	echo "  Build mingw-w64-git packages."
	echo
	echo "Usage:"
	echo "  $0 --arch <arch> --version <version> --build-extra <path> --output <path>"
	echo
	echo "Options:"
	echo "  --arch <arch>         Architecture to build. [Required] (x86_64, aarch64)"
	echo "  --version <version>   Version string. [Required]"
	echo "  --build-extra <path>  Path to build-extra repository. [Required]"
	echo "  --output <path>       Output directory. (default: ~/artifacts)"
	echo
}

if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
	usage
	exit 0
fi

while [ $# -gt 0 ]; do
	case "$1" in
	--arch)
		ARCH="$2"
		shift 2
		;;
	--version)
		VERSION="$2"
		shift 2
		;;
	--build-extra)
		BUILD_EXTRA="$2"
		shift 2
		;;
	--output)
		OUT_PATH="$2"
		shift 2
		;;
	*)
		echo "Unknown option: $1" >&2
		usage
		exit 1
		;;
	esac
done

if [ -z "$ARCH" ] || [ -z "$VERSION" ] || [ -z "$BUILD_EXTRA" ]; then
	echo "❌ Architecture, version, and build-extra path must be provided!" >&2
	usage
	exit 1
fi

if [ -z "$OUT_PATH" ]; then
	OUT_PATH=~/artifacts
fi

BUILD_EXTRA=$(realpath "$BUILD_EXTRA")
OUT_PATH=$(realpath "$OUT_PATH")

#
# Validate the architecture is correct. Must be one of x86_64 or aarch64
#
case "$ARCH" in
	x86_64)
		ARCH_FLAG="--only-x86_64"
		TOOLCHAIN="x86_64"
		MINGW_PREFIX="mingw64"
		;;
	aarch64)
		ARCH_FLAG="--only-aarch64"
		TOOLCHAIN="clang-aarch64"
		MINGW_PREFIX="clangarm64"
		;;
	*)
		echo "❌ Invalid architecture: $ARCH" >&2
		usage
		exit 1
		;;
esac

echo "ℹ️ build-extra:  ${BUILD_EXTRA}"
echo "ℹ️ Toolchain:    ${TOOLCHAIN}"
echo "ℹ️ MinGW Prefix: ${MINGW_PREFIX}"
echo "ℹ️ Output Path:  ${OUT_PATH}"
echo

PKG_NAME="mingw-w64-${TOOLCHAIN}-git"

echo "⏳ Building ${PKG_NAME} (${VERSION})..."
sh -x "${BUILD_EXTRA}/please.sh" build-mingw-w64-git ${ARCH_FLAG} --build-src-pkg -o "$OUT_PATH" HEAD || {
	echo "❌ Failed to build ${PKG_NAME}!" >&2
	exit 1
}

echo "✅ ${PKG_NAME} build complete!"
