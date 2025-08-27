#!/bin/sh

usage () {
	echo "Description:"
	echo "  Install the Git for Windows SDK."
	echo
	echo "Usage:"
	echo "  $0 --arch <arch> --path <path>"
	echo
	echo "Options:"
	echo "  --arch <arch>  Architecture of the SDK to install. [Required] (x86_64, aarch64)"
	echo "  --path <path>  Path to install the SDK. (default: ~/git-sdk)"
}

clone () {
	git clone \
		-c "checkout.workers=56" \
		--depth=1 \
		--single-branch \
		--branch="main" \
		$*
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
	--path)
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

if [ -z "$ARCH" ]; then
	echo "❌ Architecture must be provided!" >&2
	usage
	exit 1
fi

if [ -z "$OUT_PATH" ]; then
	OUT_PATH=~/git-sdk
fi

OUT_PATH=$(realpath "$OUT_PATH")

# TODO: locate this!
GIT_ROOT="C:/Program Files/Git"
USR_BIN_PATH="${GIT_ROOT}/usr/bin"

#
# Validate the architecture is correct. Must be one of x86_64 or aarch64
#
case "$ARCH" in
	x86_64)
		REPO="git-sdk-64"
		BIN_PATH="${GIT_ROOT}/mingw64/bin"
		;;
	aarch64)
		REPO="git-sdk-arm64"
		BIN_PATH="${GIT_ROOT}/clangarm64/bin"
		;;
	*)
		echo "❌ Invalid architecture: $ARCH" >&2
		usage
		exit 1
		;;
esac

TEMP_DIR=$(mktemp -d)
SDK_FLAVOR=build-installers

OWNER="git-for-windows"
SDK_URL="https://github.com/${OWNER}/${REPO}"
SDK_PATH="${TEMP_DIR}/sdk"

BUILD_EXTRA_URL="https://github.com/${OWNER}/build-extra"
BUILD_EXTRA_PATH="${TEMP_DIR}/build-extra"

echo "ℹ️ SDK Architecture:  ${ARCH}"
echo "ℹ️ SDK URL:           ${SDK_URL}"
echo "ℹ️ build-extra URL:   ${BUILD_EXTRA_URL}"
echo "ℹ️ Installation Path: ${OUT_PATH}"
echo

#
# Clone the SDK and build-extra repositories.
#
echo "⏳ Cloning SDK repository..."
clone --filter=blob:none --bare "${SDK_URL}" "${SDK_PATH}" || {
	echo "❌ Failed to clone SDK repository!" >&2
	exit 1
}

# Output the current HEAD commit of the SDK
SDK_HEAD=$(git --git-dir "${SDK_PATH}" rev-parse HEAD)
echo
echo "✅ SDK checked out with HEAD: $SDK_HEAD"
echo

# Clone build-extra
echo "⏳ Cloning build-extra repository..."
clone "${BUILD_EXTRA_URL}" "${BUILD_EXTRA_PATH}" || {
	echo "❌ Failed to clone build-extra repository!" >&2
	exit 1
}

# Output the current HEAD commit of build-extra
BUILD_EXTRA_HEAD=$(git --git-dir "${BUILD_EXTRA_PATH}/.git" rev-parse HEAD)
echo
echo "✅ build-extra checked out with HEAD: $BUILD_EXTRA_HEAD"
echo

# Create artifact
echo "⏳ Creating SDK artifact..."

COMSPEC="$WINDIR\\System32\\cmd.exe" \
LC_CTYPE="C.UTF-8" \
CHERE_INVOKING=1 \
MSYSTEM="MINGW64" \
PATH="${BIN_PATH};${PATH}" \
GIT_CONFIG_PARAMETERS="'checkout.workers=56'" \
"${USR_BIN_PATH}/bash.exe" \
	"$(cygpath -w "${BUILD_EXTRA_PATH}/please.sh")" \
	create-sdk-artifact \
	--architecture="${ARCH}" \
	--out="$(cygpath -w "${OUT_PATH}")" \
	--sdk="$(cygpath -w "${SDK_PATH}")" \
	"$SDK_FLAVOR" || {
	echo "❌ Failed to create SDK artifact!" >&2
	exit 1
}

# Clean up temporary repositories
rm -rf "${TEMP_DIR}"

echo
echo "✅ Git for Windows SDK is ready at: ${SDK_PATH}"
