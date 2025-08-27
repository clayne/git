#!/bin/sh

usage () {
	echo "Description:"
	echo "  Validate that a Git tag reference is formatted correctly and is annotated."
	echo
	echo "Usage:"
	echo "  $0 [options] <tag-ref>"
	echo
	echo "Arguments:"
	echo "  <tag-ref>  Tag reference. [Required]"
	echo
	echo "Options:"
	echo "  -C <path>  Path to the Git repository. (default: .)"
}

if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
	usage
	exit 0
fi

while [ $# -gt 0 ]; do
	case "$1" in
	-C)
		REPO_PATH="$2"
		shift 2
		;;
	*)
		# end of options
		break
		;;
	esac
done

if [ -z "$REPO_PATH" ]; then
	REPO_PATH="."
fi

REF_NAME=$1
if [ -z "$REF_NAME" ]; then
	echo "❌ No tag reference provided!" >&2
	usage
	exit 1
fi

TAG_NAME=${REF_NAME#refs/tags/}

#
# The build version is the same as the tag name, except:
#  - strip the "v" prefix,
#  - replace the "-" with "." in the version string for release candidates.
#
BUILD_VERSION=${TAG_NAME#v}
BUILD_VERSION=$(echo "$BUILD_VERSION" | sed 's/-/./g')

echo "ℹ️ Tag reference: $REF_NAME"
echo "ℹ️ Tag name:      $TAG_NAME"
echo "ℹ️ Build version: $BUILD_VERSION"
echo

#
# Note that the VFS major version must always be zero to indicate compatibility
# with the currently released version of VFS for Git (at time of writing).
#
# If a repository format breaking change is introduced, the VFS major version
# must be incremented, and VFS for Git must be updated to handle the new
# repository format version accordingly.
#
echo "$REF_NAME" |
	grep -qE '^refs/tags/v2\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-rc[0-9]+)?\.vfs\.0\.(0|[1-9][0-9]*)$' || {
	echo "❌ Tag reference format is invalid. Expected 'refs/tags/v2.<X>.<Y>[-rc<N>].vfs.0.<W>' but got: $REF_NAME" >&2
	exit 1
}

echo "✅ Reference format is valid." >&2

#
# Verify that the tag is annotated.
#
test "$(git cat-file -t "$REF_NAME")" = "tag" || {
	echo "❌ Tag is not annotated!" >&2
	exit 1
}

echo "✅ Tag is annotated." >&2

#
# Check that the GIT-VERSION-GEN output matches our build name.
#
echo "⏳ Generating GIT-VERSION-FILE"
make -C "$REPO_PATH" GIT-VERSION-FILE || {
	echo "❌ Failed to generate GIT-VERSION-FILE" >&2
	exit 1
}

test "$BUILD_VERSION" = "$(sed -n 's/^GIT_VERSION *= *//p' < GIT-VERSION-FILE)" || {
	echo "❌ GIT-VERSION-FILE ($(cat GIT-VERSION-FILE)) does not match $BUILD_VERSION" >&2
	exit 1
}

echo "✅ Build version matches generated version." >&2
