#!/bin/sh

usage () {
	echo "Description:"
	echo "  Create installer/portable packages."
	echo
	echo "Usage:"
	echo "  $0 --arch <arch> --version <version> --build-extra <path> --pkg-dir <path> --type <type> --output <path>"
	echo
	echo "Options:"
	echo "  --arch <arch>         Architecture of the SDK to install. [Required] (x86_64, aarch64)"
	echo "  --version <version>   Version string. [Required]"
	echo "  --build-extra <path>  Path to build-extra repository. [Required]"
	echo "  --pkg-dir <path>      Path to the directory containing mingw-w64-git packages. [Required]"
	echo "  --type <type>         Type of package to create. [Required] (installer, portable)"
	echo "  --output <path>       Path to the output directory. (default: ~/publish)"
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
	--pkg-dir)
		PKG_DIR="$2"
		shift 2
		;;
	--type)
		PKG_TYPE="$2"
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

if [ -z "$ARCH" ] || [ -z "$VERSION" ] || [ -z "$PKG_DIR" ] || [ -z "$PKG_TYPE" ]; then
	echo "❌ Architecture, version, package directory, and package type must be provided!" >&2
	usage
	exit 1
fi

if [ -z "$OUT_PATH" ]; then
	OUT_PATH=~/publish
fi

OUT_PATH=$(realpath "$OUT_PATH")

#
# Validate the architecture is correct. Must be one of x86_64 or aarch64
#
case "$ARCH" in
	x86_64)
		TOOLCHAIN="x86_64"
		;;
	aarch64)
		TOOLCHAIN="clang-aarch64"
		;;
	*)
		echo "❌ Invalid architecture: $ARCH" >&2
		usage
		exit 1
		;;
esac

#
# Validate the package type. Must be one of installer or portable.
#
case "$PKG_TYPE" in
	installer)
		PLEASE_FLAGS="--installer"
		;;
	portable)
		PLEASE_FLAGS="--portable"
		;;
	*)
		echo "❌ Invalid package type: $PKG_TYPE" >&2
		usage
		exit 1
		;;
esac

echo "ℹ️ Architecture:       ${ARCH}"
echo "ℹ️ Package Type:       ${PKG_TYPE}"
echo "ℹ️ Version:            ${VERSION}"
echo "ℹ️ Package Directory:  ${PKG_DIR}"
echo "ℹ️ Output Path:        ${OUT_PATH}"
echo

#
# Copy PDBs to the directory where `--include-pdbs` expects.
#
echo "⏳ Copying PDBs..."
mkdir -p "${BUILD_EXTRA}/cached-source-packages" &&
	cp ${{matrix.arch.artifact}}/*-pdb* "${BUILD_EXTRA}/cached-source-packages/" || {
	echo "❌ Failed to copy PDBs" >&2
	exit 1
}

echo "✅ Done."
echo

echo "⏳ Creating ${PKG_TYPE} package..."
eval "${BUILD_EXTRA}/please.sh" make_installers_from_mingw_w64_git \
	--include-pdbs \
	--version="$VERSION" \
	-o "$OUT_PATH" \
	"$PLEASE_FLAGS" \
	--pkg="${PKG_DIR}/mingw-w64-${TOOLCHAIN}-git-[0-9]*.tar.xz" \
	--pkg="${PKG_DIR}/mingw-w64-${TOOLCHAIN}-git-doc-html-[0-9]*.tar.xz" || {
	echo "❌ Failed to create ${PKG_TYPE} package" >&2
	exit 1
}

echo "✅ Done."
