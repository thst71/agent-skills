#!/usr/bin/env bash
# Lints the workflow snippets of the toolchain profiles (Pull Request and Release Build steps) with
# actionlint: each snippet goes into a job of a minimal workflow, after a job verify that provides
# needs.verify.outputs.version like the release template. actionlint also runs shellcheck on the
# run scripts when shellcheck is installed. Needs Go (actionlint runs pinned with go run).
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
actionlint=github.com/rhysd/actionlint/cmd/actionlint@v1.7.12

count=0
for profile in "$here"/../toolchain/*/PROFILE.md; do
	name=$(basename "$(dirname "$profile")")
	# Every yaml block that is a list of steps (indented as in a job) becomes one workflow.
	count=$((count + $(awk -v out="$work/$name" '
		/^```ya?ml$/ { inblock = 1; body = ""; next }
		inblock && /^```$/ {
			inblock = 0
			if (body ~ /^      - /) {
				n++
				file = out "-" n ".yml"
				print "name: snippet\non: push\njobs:\n  verify:\n    runs-on: ubuntu-latest" > file
				print "    outputs:\n      version: ${{ steps.tag.outputs.version }}\n    steps:" > file
				print "      - id: tag\n        run: echo version=0.0.0 >> \"$GITHUB_OUTPUT\"" > file
				print "  snippet:\n    needs: verify\n    runs-on: ubuntu-latest\n    steps:" > file
				printf "%s", body > file
				close(file)
			}
			next
		}
		inblock { body = body $0 "\n" }
		END { print n + 0 }
	' "$profile")))
done

if [ "$count" -eq 0 ]; then
	echo "no workflow snippets found in the profiles" >&2
	exit 1
fi
cd "$work"
if go run "$actionlint" -no-color ./*.yml; then
	echo "ok: $count workflow snippets of the profiles pass actionlint"
else
	echo "FAIL: workflow snippets of the profiles (file names: <profile>-<n>.yml, n counts the snippets of the profile)" >&2
	exit 1
fi
