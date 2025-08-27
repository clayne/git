#!/bin/sh

usage () {
	echo "Description:"
	echo "  Apply customizations to the Git for Windows installer for Microsoft Git."
	echo
	echo "Usage:"
	echo "  $0 --<arch> --build-extra <path>"
	echo
	echo "Options:"
	echo "  --arch <arch>         Architecture to build. [Required] (x86_64, aarch64)"
	echo "  --build-extra <path>  Path to build-extra repository. [Required]"
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
	--build-extra)
		BUILD_EXTRA="$2"
		shift 2
		;;
	*)
		echo "Unknown option: $1" >&2
		usage
		exit 1
		;;
	esac
done

if [ -z "$ARCH" ] || [ -z "$BUILD_EXTRA" ]; then
	echo "❌ Architecture, and build-extra path must be provided!" >&2
	usage
	exit 1
fi


BUILD_EXTRA=$(realpath "$BUILD_EXTRA")

#
# Validate the architecture is correct. Must be one of x86_64 or aarch64
#
case "$ARCH" in
	x86_64)
		MINGW_PREFIX="mingw64"
		;;
	aarch64)
		MINGW_PREFIX="clangarm64"
		;;
	*)
		echo "❌ Invalid architecture: $ARCH" >&2
		usage
		exit 1
		;;
esac

echo "ℹ️ build-extra: ${BUILD_EXTRA}"
echo "ℹ️ MinGW Prefix: ${MINGW_PREFIX}"
echo

#
# Retarget the auto-updater to microsoft/git.
#
echo "⏳ Retargeting auto-updater..."

UPDATER_CONFIG_FILE="${BUILD_EXTRA}/git-update-git-for-windows.config"

tr % '\t' >"$UPDATER_CONFIG_FILE" <<-EOF &&
[update]
%fromFork = microsoft/git
EOF

sed -i -e '/^#include "file-list.iss"/a\
Source: {#SourcePath}\\..\\git-update-git-for-windows.config; DestDir: {app}\\${MINGW_PREFIX}\\bin; Flags: replacesameversion; AfterInstall: DeleteFromVirtualStore' \
	-e '/^Type: dirifempty; Name: {app}\\{#MINGW_BITNESS}$/i\
Type: files; Name: {app}\\{#MINGW_BITNESS}\\bin\\git-update-git-for-windows.config\
Type: dirifempty; Name: {app}\\{#MINGW_BITNESS}\\bin' \
	"$BUILD_EXTRA/installer/install.iss"  || {
	echo "❌ Failed to retarget auto-updater!" >&2
	exit 1
}

echo "✅ Done."
echo

#
# Set update alerts to continue until upgrade is taken
#
echo "⏳ Forcing updater to always prompt..."

sed -i -e '6 a use_recently_seen=no' \
	/${MINGW_PREFIX}/bin/git-update-git-for-windows || {
	echo "❌ Failed to change updater prompt behavior!" >&2
	exit 1
}

echo "✅ Done."
echo

#
# Update the installer publisher.
#
echo "⏳ Update publisher..."

sed -i -e 's/^\(AppPublisher=\).*/\1The Git Client Team at Microsoft/' \
	"${BUILD_EXTRA}/installer/install.iss" || {
	echo "❌ Failed to update publisher!" >&2
	exit 1
}

echo "✅ Done."
echo

#
# Configure Visual Studio to use the installed Git.
#
echo "⏳ Configuring Visual Studio to use the installed Git..."

sed -i "# First, find the autoupdater parts in the install/uninstall steps
/if IsComponentInstalled('autoupdate')/{
  # slurp in the next two lines, where the call to InstallAutoUpdater()/UninstallAutoUpdater() happens
  N
  N
  # insert the corresponding CustomPostInstall()/CustomPostUninstall() call before that block
  s/^\\([ \t]*\\)\(.*\\)\\(Install\\|Uninstall\\)\\(AutoUpdater\\)/\\1CustomPost\\3();\\n\\1\\2\\3\\4/
}" "${BUILD_EXTRA}/installer/install.iss" &&
grep -q CustomPostInstall "${BUILD_EXTRA}/installer/install.iss" &&
grep -q CustomPostUninstall "${BUILD_EXTRA}/installer/install.iss" &&

cat >>"${BUILD_EXTRA}/installer/helpers.inc.iss" <<'EOF' &&

procedure CustomPostInstall();
begin
if not RegWriteStringValue(HKEY_CURRENT_USER,'Software\Microsoft\VSCommon\15.0\TeamFoundation\GitSourceControl','GitPath',ExpandConstant('{app}')) or
not RegWriteStringValue(HKEY_CURRENT_USER,'Software\Microsoft\VSCommon\16.0\TeamFoundation\GitSourceControl','GitPath',ExpandConstant('{app}')) or
not RegWriteStringValue(HKEY_CURRENT_USER,'Software\Microsoft\VSCommon\17.0\TeamFoundation\GitSourceControl','GitPath',ExpandConstant('{app}')) or
not RegWriteStringValue(HKEY_CURRENT_USER,'Software\Microsoft\VSCommon\18.0\TeamFoundation\GitSourceControl','GitPath',ExpandConstant('{app}')) or
not RegWriteStringValue(HKEY_CURRENT_USER,'Software\Microsoft\VSCommon\19.0\TeamFoundation\GitSourceControl','GitPath',ExpandConstant('{app}')) or
not RegWriteStringValue(HKEY_CURRENT_USER,'Software\Microsoft\VSCommon\20.0\TeamFoundation\GitSourceControl','GitPath',ExpandConstant('{app}')) then
  LogError('Could not register TeamFoundation\GitSourceControl');
end;

procedure CustomPostUninstall();
begin
if not RegDeleteValue(HKEY_CURRENT_USER,'Software\Microsoft\VSCommon\15.0\TeamFoundation\GitSourceControl','GitPath') or
not RegDeleteValue(HKEY_CURRENT_USER,'Software\Microsoft\VSCommon\16.0\TeamFoundation\GitSourceControl','GitPath') or
not RegDeleteValue(HKEY_CURRENT_USER,'Software\Microsoft\VSCommon\17.0\TeamFoundation\GitSourceControl','GitPath') or
not RegDeleteValue(HKEY_CURRENT_USER,'Software\Microsoft\VSCommon\18.0\TeamFoundation\GitSourceControl','GitPath') or
not RegDeleteValue(HKEY_CURRENT_USER,'Software\Microsoft\VSCommon\19.0\TeamFoundation\GitSourceControl','GitPath') or
not RegDeleteValue(HKEY_CURRENT_USER,'Software\Microsoft\VSCommon\20.0\TeamFoundation\GitSourceControl','GitPath') then
  LogError('Could not register TeamFoundation\GitSourceControl');
end;
EOF

if [ $? -ne 0 ]; then
	echo "❌ Failed to update install.iss" >&2
	exit 1
fi

echo "✅ Done."
echo

#
# Enable Scalar and the auto-updater in the installer.
#
echo "⏳ Enabling Scalar and auto-updater..."

sed -i -e "/ChosenOptions:=''/a\\
if (ExpandConstant('{param:components|/}')='/') then begin\n\
  WizardSelectComponents('autoupdate');\n\
#ifdef WITH_SCALAR\n\
  WizardSelectComponents('scalar');\n\
#endif\n\
end;" "${BUILD_EXTRA}/installer/install.iss" || {
	echo "❌ Failed to update install.iss" >&2
	exit 1
}

echo "✅ Done."
echo

echo "🎉 All customizations are complete."
