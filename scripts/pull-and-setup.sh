#!/usr/bin/env bash
#
# pull-and-setup.sh - Clone or pull UnrealIRCd repo with recursive submodules (using GitHub token),
#                     optionally build the server with --setup.
#
# For Ubuntu. Run on the server to download/pull the repo. No root, no apt-get; build
# dependencies must already be installed (e.g. build-essential, libssl-dev, libpcre2-dev, etc.).
#
# Environment:
#   GITHUB_TOKEN or GITHUB_PAT  - Required for clone or submodule update (private repos).
#   REPO_URL                     - Optional. Repo URL for initial clone (e.g. https://github.com/blazium-games/unrealircd.git).
#                                  If omitted when cloning, script exits with usage.
#
# Usage:
#   From repo root:   ./scripts/pull-and-setup.sh [--setup]
#   From parent dir:  ./scripts/pull-and-setup.sh [DIR] [--setup]
#
#   --setup, -s  After clone/pull, fix execute bits and run extras/build-tests/nix/build
#                (installs to $HOME/unrealircd).
#
set -e

# Optional: fail on unset vars when we need them
# set -u

DO_SETUP=false
TARGET_DIR=""

while [[ $# -gt 0 ]]; do
	case "$1" in
		--setup|-s)
			DO_SETUP=true
			shift
			;;
		-*)
			echo "Unknown option: $1" >&2
			exit 1
			;;
		*)
			if [[ -z "$TARGET_DIR" ]]; then
				TARGET_DIR="$1"
			else
				echo "At most one directory argument allowed." >&2
				exit 1
			fi
			shift
			;;
	esac
done

# Resolve repo root: either we're inside the repo or we're given a directory.
get_repo_root() {
	local start
	start="${1:-.}"
	if [[ -n "$start" && -d "$start" ]]; then
		(cd "$start" && git rev-parse --show-toplevel 2>/dev/null) || echo ""
	else
		(git rev-parse --show-toplevel 2>/dev/null) || echo ""
	fi
}

# Need token for clone or submodule update.
need_token() {
	local token
	token="${GITHUB_TOKEN:-$GITHUB_PAT}"
	if [[ -z "$token" ]]; then
		echo "GITHUB_TOKEN or GITHUB_PAT must be set for clone or submodule update." >&2
		exit 1
	fi
	echo "$token"
}

# Configure repo-local URL rewrite so submodules use the token.
setup_token_url_rewrite() {
	local repo_root token
	repo_root="$1"
	token="$2"
	if [[ -z "$token" || -z "$repo_root" ]]; then return; fi
	(cd "$repo_root" && git config url."https://${token}@github.com/".insteadOf "https://github.com/")
}

# Fix execute bits (same as CI fix-permissions).
fix_permissions() {
	local repo_root
	repo_root="$1"
	cd "$repo_root"
	chmod +x Config configure autogen.sh
	chmod +x autoconf/install-sh autoconf/config.guess autoconf/config.sub
	chmod +x src/buildmod
	chmod +x extras/build-tests/nix/build extras/build-tests/nix/run-tests extras/build-tests/nix/select-config
	chmod +x extras/patches/patch_spamfilter_conf
	find extras -type f -name "*.sh" -exec chmod +x {} \;
	find extras/build-tests -type f ! -name "*.conf" ! -name "*.txt" -exec chmod +x {} \;
}

REPO_ROOT=""
CLONED_OR_PULLED=false

if [[ -n "$TARGET_DIR" ]]; then
	# Explicit directory: use it as repo root if it's a repo, else as clone target.
	if [[ -d "$TARGET_DIR" ]]; then
		REPO_ROOT=$(get_repo_root "$TARGET_DIR")
		if [[ -z "$REPO_ROOT" ]]; then
			echo "Directory '$TARGET_DIR' exists but is not a git repository." >&2
			exit 1
		fi
	else
		# Clone into TARGET_DIR.
		REPO_URL="${REPO_URL:-}"
		if [[ -z "$REPO_URL" ]]; then
			echo "REPO_URL must be set to clone into a new directory (e.g. REPO_URL=https://github.com/blazium-games/unrealircd.git)." >&2
			exit 1
		fi
		TOKEN=$(need_token)
		# Use token in URL for private repo clone; then set url rewrite and init submodules.
		CLONE_URL="${REPO_URL/https:\/\/github.com/https:\/\/${TOKEN}@github.com}"
		git clone "$CLONE_URL" "$TARGET_DIR"
		REPO_ROOT="$(cd "$TARGET_DIR" && pwd)"
		setup_token_url_rewrite "$REPO_ROOT" "$TOKEN"
		(cd "$REPO_ROOT" && git submodule update --init --recursive)
		CLONED_OR_PULLED=true
	fi
else
	# No directory: use current directory as repo root if it's a repo.
	REPO_ROOT=$(get_repo_root ".")
	if [[ -z "$REPO_ROOT" ]]; then
		# Not in a repo; clone into current dir (.) or default name.
		REPO_URL="${REPO_URL:-}"
		if [[ -z "$REPO_URL" ]]; then
			echo "Not inside a git repo and REPO_URL not set. Set REPO_URL or run from repo root." >&2
			exit 1
		fi
		# Clone into current directory (clone expects empty or non-existent; repo name from URL).
		TOKEN=$(need_token)
		base=$(basename "$REPO_URL" .git)
		if [[ -d "$base" ]]; then
			REPO_ROOT=$(get_repo_root "$base")
			if [[ -z "$REPO_ROOT" ]]; then
				echo "Directory '$base' exists but is not a git repository." >&2
				exit 1
			fi
		else
			CLONE_URL="${REPO_URL/https:\/\/github.com/https:\/\/${TOKEN}@github.com}"
			git clone "$CLONE_URL" "$base"
			REPO_ROOT="$(cd "$base" && pwd)"
			setup_token_url_rewrite "$REPO_ROOT" "$TOKEN"
			(cd "$REPO_ROOT" && git submodule update --init --recursive)
			CLONED_OR_PULLED=true
		fi
	else
		REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"
	fi
fi

# If we didn't just clone and we're in an existing repo, pull and update submodules (token for submodules).
if [[ "$CLONED_OR_PULLED" != true ]]; then
	TOKEN=$(need_token)
	setup_token_url_rewrite "$REPO_ROOT" "$TOKEN"
	(cd "$REPO_ROOT" && git pull && git submodule update --init --recursive)
fi

if [[ "$DO_SETUP" == true ]]; then
	fix_permissions "$REPO_ROOT"
	cd "$REPO_ROOT" && ./extras/build-tests/nix/build
fi
