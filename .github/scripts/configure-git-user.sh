#!/bin/sh

usage () {
	echo "Description:"
	echo "  Configure Git user information."
	echo
	echo "Usage:"
	echo "  $0 --name <name> --email <email>"
	echo
	echo "Options:"
	echo "  --name <name>    User name. [Required]"
	echo "  --email <email>  User email. [Required]"
}

if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
	usage
	exit 0
fi

while [ $# -gt 0 ]; do
	case "$1" in
	--name)
		NAME="$2"
		shift 2
		;;
	--email)
		EMAIL="$2"
		shift 2
		;;
	*)
		echo "Unknown option: $1" >&2
		usage
		exit 1
		;;
	esac
done

if [ -z "$NAME" ] || [ -z "$EMAIL" ]; then
	echo "❌ Name and email must be provided!" >&2
	usage
	exit 1
fi

git config --global user.name "$NAME" || {
	echo "❌ Failed to set user.name" >&2
	exit 1
}

git config --global user.email "$EMAIL" || {
	echo "❌ Failed to set user.email" >&2
	exit 1
}

echo "✅ Git user configured: $NAME <$EMAIL>" >&2
