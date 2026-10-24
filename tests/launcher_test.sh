#!/usr/bin/env bash
# Tests spec-system/bin/validate-specs against a fake spec-validator repository and release on
# file://, with tags signed by throw-away keys. The user's git configuration is not read.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

export GIT_CONFIG_GLOBAL="$work/gitconfig" GIT_CONFIG_NOSYSTEM=1
git config --global user.name Me
git config --global user.email me@example.org
git config --global gpg.format ssh
git config --global gpg.ssh.program ssh-keygen
git config --global commit.gpgSign false
git config --global tag.gpgSign false
git config --global init.defaultBranch main

case $(uname -s) in Darwin) os=darwin ;; *) os=linux ;; esac
case $(uname -m) in arm64 | aarch64) arch=arm64 ;; *) arch=amd64 ;; esac

fake() { # dir, label, version printed by -version
	mkdir -p "$1"
	# shellcheck disable=SC2016 # $* belongs to the fake binary
	printf '#!/bin/sh\nif [ "${1:-}" = -version ]; then echo %s; exit 0; fi\necho "%s $*"\n' "$3" "$2" >"$1/spec-validator"
	chmod +x "$1/spec-validator"
}

# The validator's repository: v1.2.3 signed by me (the latest), v1.1.0 signed by another key,
# v1.0.0 annotated but unsigned, v0.9.0 lightweight.
ssh-keygen -q -t ed25519 -N '' -C me -f "$work/me"
ssh-keygen -q -t ed25519 -N '' -C other -f "$work/other"
echo "me@example.org namespaces=\"git\" $(cat "$work/me.pub")" >"$work/allowed_signers"
git init -q "$work/source"
git -C "$work/source" commit -q --allow-empty -m init
git -C "$work/source" -c user.signingkey="$work/me" tag -s v1.2.3 -m v1.2.3
git -C "$work/source" -c user.signingkey="$work/other" tag -s v1.1.0 -m v1.1.0
git -C "$work/source" tag -a v1.0.0 -m v1.0.0
git -C "$work/source" tag v0.9.0
mkdir -p "$work/srv"
git clone -q --bare "$work/source" "$work/srv/spec-validator.git"

# The release of v1.2.3: the archive for this platform and checksums.txt with other assets.
release="$work/srv/spec-validator/releases/download/v1.2.3"
archive="spec-validator_1.2.3_${os}_${arch}.tar.gz"
mkdir -p "$release"
fake "$work/build" release 1.2.3
tar -czf "$release/$archive" -C "$work/build" spec-validator
if command -v sha256sum >/dev/null 2>&1; then
	sum=$(sha256sum "$release/$archive" | cut -d ' ' -f 1)
else
	sum=$(shasum -a 256 "$release/$archive" | cut -d ' ' -f 1)
fi
zero=0000000000000000000000000000000000000000000000000000000000000000
{
	echo "$sum  $archive"
	echo "$zero  spec-validator_1.2.3_windows_amd64.zip"
	echo "$zero  docs-1.2.3.zip"
	echo "$zero  release-notes.html"
} >"$release/checksums.txt"
mkdir -p "$work/srv/spec-validator/releases/download/v1.1.0" "$work/srv/spec-validator/releases/download/v1.0.0"

# A project with the vendored launcher.
git init -q "$work/project"
mkdir -p "$work/project/.agents/skills/spec-system"
cp -R "$here/../spec-system/bin" "$work/project/.agents/skills/spec-system/bin"
launcher="$work/project/.agents/skills/spec-system/bin/validate-specs"
lock="$work/project/.agents/spec-validator.lock"

export SPEC_VALIDATOR_BASE_URL="file://$work/srv/spec-validator"
export SPEC_VALIDATOR_SIGNERS="$work/allowed_signers"
export XDG_CACHE_HOME="$work/cache"
unset SPEC_VALIDATOR
path=$PATH

check() { # name, expected exit code, expected output, command...
	local name=$1 code=$2 want=$3 output status=0
	shift 3
	output=$(cd "$work/project" && "$@" 2>&1) || status=$?
	if [[ $status -ne $code || "$output" != *"$want"* ]]; then
		echo "FAIL $name: want exit $code and '$want', got exit $status: $output"
		failures=$((failures + 1))
	else
		echo "ok   $name"
	fi
}

check "no lock" 2 "create it with: .agents/skills/spec-system/bin/validate-specs --update" "$launcher" -x
check "unsigned tag refused" 2 "v1.0.0 is not signed by an allowed signer" "$launcher" --update v1.0.0
check "other key refused" 2 "v1.1.0 is not signed by an allowed signer" "$launcher" --update v1.1.0
check "lightweight tag refused" 2 "v0.9.0 is not an annotated tag" "$launcher" --update v0.9.0
# A signed tag without a release: pushed for this case only, so v1.2.3 stays the latest.
git -C "$work/source" -c user.signingkey="$work/me" tag -s v1.2.4 -m v1.2.4
git -C "$work/source" push -q "$work/srv/spec-validator.git" v1.2.4
check "no checksums" 2 "cannot download the checksums of v1.2.4" "$launcher" --update v1.2.4
git -C "$work/source" push -q --delete "$work/srv/spec-validator.git" v1.2.4
check "bad version" 2 "usage: validate-specs --update" "$launcher" --update 1.2.3
check "missing signers" 2 "no allowed signers in" env SPEC_VALIDATOR_SIGNERS="$work/none" "$launcher" --update v1.2.3
[[ ! -e "$lock" ]] || { echo "FAIL refused updates left a lock"; failures=$((failures + 1)); }

# The latest is the newest tag with a release: v1.2.4 (signed, no release yet) is skipped.
git -C "$work/source" push -q "$work/srv/spec-validator.git" v1.2.4
check "latest skips a tag without release" 0 "skipping v1.2.4, it has no release" "$launcher" --update
grep -q '^version 1.2.3$' "$lock" || { echo "FAIL skipped tag pinned: $(cat "$lock")"; failures=$((failures + 1)); }
git -C "$work/source" push -q --delete "$work/srv/spec-validator.git" v1.2.4
git -C "$work/project" rm -q --cached .agents/spec-validator.lock && rm "$lock"
check "no release at all" 2 "no release found in" env SPEC_VALIDATOR_BASE_URL="file://$work/nowhere" "$launcher" --update
check "update to latest" 0 "pinned spec-validator 1.2.3 (was none), signed by me@example.org" "$launcher" --update
expected="# spec-validator pin, written by: .agents/skills/spec-system/bin/validate-specs --update
version 1.2.3
$sum  $archive
$zero  spec-validator_1.2.3_windows_amd64.zip"
if [[ "$(cat "$lock")" != "$expected" ]]; then
	echo "FAIL lock content: $(cat "$lock")"
	failures=$((failures + 1))
fi
check "lock staged" 0 "A  .agents/spec-validator.lock" git status --porcelain
check "update again" 0 "pinned spec-validator 1.2.3 (was 1.2.3)" "$launcher" --update v1.2.3

check "download and run" 0 "release -x --y" "$launcher" -x --y
[[ -x "$work/cache/spec-validator/1.2.3/spec-validator" ]] || { echo "FAIL not cached"; failures=$((failures + 1)); }
check "cached run" 0 "release cached" env SPEC_VALIDATOR_BASE_URL="file://$work/nowhere" "$launcher" cached

fake "$work/installed-match" installed v1.2.3
check "installed, same version" 0 "installed -x" env PATH="$work/installed-match:$path" "$launcher" -x
fake "$work/installed-other" installed 1.2.2
check "installed, other version" 0 "release -x" env PATH="$work/installed-other:$path" "$launcher" -x
fake "$work/installed-dev" installed v1.2.3-0.20261023073936-dd63307d722f
check "installed, development build" 0 "release -x" env PATH="$work/installed-dev:$path" "$launcher" -x

fake "$work/override" override 0.0.0
check "SPEC_VALIDATOR" 0 "override -x" env SPEC_VALIDATOR="$work/override/spec-validator" "$launcher" -x

rm -rf "$work/cache"
sed "s/^$sum/$zero/" "$lock" >"$lock.new" && mv "$lock.new" "$lock"
check "checksum mismatch" 2 "checksum mismatch for $archive" env PATH="/usr/bin:/bin" "$launcher" -x
sed '/^version/d' "$lock" >"$lock.new" && mv "$lock.new" "$lock"
check "no version line" 2 "no version line in" "$launcher" -x

[[ $failures -eq 0 ]] || { echo "$failures failure(s)"; exit 1; }
