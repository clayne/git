#!/bin/sh

usage () {
	echo "Description:"
	echo "  Create mingw-w64-git package bundle."
	echo
	echo "Usage:"
	echo "  $0 --version <version> --output <path>"
	echo
	echo "Options:"
	echo "  --version <version>  Version string. [Required]"
	echo "  --pkg-dir <path>     Path to the directory containing mingw-w64-git packages. [Required]"
	echo "  --output <path>      Output directory. (default: ~/artifacts)"
	echo
}

if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
	usage
	exit 0
fi

while [ $# -gt 0 ]; do
	case "$1" in
	--version)
		VERSION="$2"
		shift 2
		;;
	--pkg-dir)
		PKG_DIR="$2"
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

if [ -z "$VERSION" ] || [ -z "$PKG_DIR" ]; then
	echo "❌ Version and package directory must be provided!" >&2
	usage
	exit 1
fi

OUT_PATH="$(realpath "$OUT_PATH")"
PKG_DIR="$(realpath "$PKG_DIR")"

BUNDLE_PATH="${OUT_PATH}/MINGW-packages.bundle"

echo "ℹ️ Package Dir:  ${PKG_DIR}"
echo "ℹ️ Bundle Path:  ${BUNDLE_PATH}"
echo

echo "⏳ Creating bundle..."
(
	cd "$PKG_DIR" &&
	cp PKGBUILD.${VERSION} PKGBUILD &&
	git commit -s -m "mingw-w64-git: new version \($VERSION\)" PKGBUILD &&
	git bundle create "$BUNDLE_PATH" origin/main..main
) || {
	echo "❌ Failed to create bundle!" >&2
	exit 1
}

echo "✅ Bundle created: ${BUNDLE_PATH}"
