#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bash scripts/record-demos.sh [all|search|git|markdown|themes]

Record four highlights and write GIFs to examples/media/.
Uses a disposable clone of ~/code/Mooncake for Git, symbols, and the homepage.
Requires VHS, ttyd, FFmpeg/ffprobe, Git, Neovim, and installed BeckNvim plugins.
Set BECKNVIM_DEMO_PROJECT to another local Mooncake checkout.
The Git recording reads public PR #3704 and requires GitHub connectivity.
See examples/README.md for the font and headless browser setup.

Set BECKNVIM_DEMO_KEEP=1 to retain frames and the sample project for inspection.
EOF
}

case "${1:-all}" in
  -h|--help) usage; exit 0 ;;
  all) scenes=(search git markdown themes) ;;
  search|git|markdown|themes) scenes=("$1") ;;
  *) usage >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { usage >&2; exit 2; }

for tool in vhs ttyd ffmpeg ffprobe git nvim awk; do
  command -v "$tool" >/dev/null || { echo "Missing dependency: $tool" >&2; exit 1; }
done

BECKNVIM_DEMO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
framerate=$(awk '$1 == "Set" && $2 == "Framerate" { print $3 }' "$BECKNVIM_DEMO_ROOT/examples/tapes/common.tape")
[[ "$framerate" =~ ^[1-9][0-9]*$ ]] || { echo 'Invalid Framerate in examples/tapes/common.tape' >&2; exit 1; }
BECKNVIM_DEMO_WORK=$(mktemp -d "${TMPDIR:-/tmp}/becknvim-demos.XXXXXXXX")
export BECKNVIM_DEMO_ROOT BECKNVIM_DEMO_WORK
cleanup() {
  if [[ "${BECKNVIM_DEMO_KEEP:-0}" == 1 ]]; then
    echo "Recording files: $BECKNVIM_DEMO_WORK"
  else
    rm -rf -- "$BECKNVIM_DEMO_WORK"
  fi
}
trap cleanup EXIT

# Reuse the saved HTTP proxy, keeping the recording's editor preferences isolated.
export BECKNVIM_DEMO_PROXY_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/nvim/proxy.json"
notes="$BECKNVIM_DEMO_WORK/WorkspaceNotes"
cp -R "$BECKNVIM_DEMO_ROOT/examples/fixtures/project" "$notes"
git -C "$notes" -c init.templateDir= init -q -b main

if [[ "${scenes[*]}" != markdown ]]; then
  source_project="${BECKNVIM_DEMO_PROJECT:-$HOME/code/Mooncake}"
  git -C "$source_project" rev-parse --show-toplevel >/dev/null || {
    echo 'Set BECKNVIM_DEMO_PROJECT to a local Mooncake checkout.' >&2
    exit 1
  }
  source_head=$(git -C "$source_project" rev-parse HEAD)
  source_branch=$(git -C "$source_project" symbolic-ref --quiet --short HEAD || echo review-demo)
  project="$BECKNVIM_DEMO_WORK/Mooncake"
  # Share immutable objects, but keep HEAD, refs, index, and worktree independent.
  git -c core.hooksPath=/dev/null clone -q --shared --no-checkout --origin recording-source "$source_project" "$project"
  git -C "$project" config core.hooksPath /dev/null
  git -C "$project" checkout -q -B "$source_branch" "$source_head"
  git -C "$project" remote remove recording-source
  git -C "$source_project" for-each-ref --format='update %(refname) %(objectname)' refs/remotes |
    git -C "$project" update-ref --stdin
  while IFS= read -r remote; do
    git -C "$project" remote add "$remote" "$(git -C "$source_project" remote get-url "$remote")"
  done < <(git -C "$source_project" remote)
  if [[ " ${scenes[*]} " == *' git '* ]]; then
    git -C "$project" rev-parse --verify refs/remotes/upstream/codex/placement-mechanism >/dev/null
    git -C "$project" cat-file -e '48b3ca329f01bb7c2d1ca27cfdeb59e28a8685e9^{commit}'
  fi
  echo "Mooncake snapshot: $source_head ($source_branch)"
fi

mkdir -p "$BECKNVIM_DEMO_ROOT/examples/media"
for scene in "${scenes[@]}"; do
  export BECKNVIM_DEMO_SCENE="$scene"
  if [[ "$scene" == markdown ]]; then
    export BECKNVIM_DEMO_CWD="$notes"
  else
    export BECKNVIM_DEMO_CWD="$project"
    # Each scene begins at the original snapshot, including after detached review.
    git -C "$project" checkout -q "$source_branch"
  fi
  recording="$BECKNVIM_DEMO_WORK/$scene"
  mkdir -p "$recording"
  cp "$BECKNVIM_DEMO_ROOT/examples/tapes/common.tape" "$recording/common.tape"
  # Use relative paths in tapes, so checkouts containing spaces work too.
  {
    echo 'Output "frames/"'
    cat "$BECKNVIM_DEMO_ROOT/examples/tapes/$scene.tape"
  } > "$recording/scene.tape"
  echo "Recording $scene..."
  (cd "$recording" && vhs scene.tape)

  if [[ "$scene" == git ]]; then
    [[ "$(git -C "$project" rev-parse HEAD)" == 48b3ca329f01bb7c2d1ca27cfdeb59e28a8685e9 ]] || {
      echo 'Git demo did not reach its review commit.' >&2; exit 1;
    }
    if git -C "$project" symbolic-ref --quiet HEAD; then
      echo 'Git demo did not detach HEAD.' >&2; exit 1
    fi
  fi

  # VHS 0.12.0 can finish without a GIF. Export frames and encode explicitly;
  # a failed encoder must fail this script rather than leave a broken README.
  ffmpeg -v error -y \
    -framerate "$framerate" -i "$recording/frames/frame-text-%05d.png" \
    -framerate "$framerate" -i "$recording/frames/frame-cursor-%05d.png" \
    -filter_complex '[0:v][1:v]overlay=shortest=1,split[a][b];[a]palettegen[p];[b][p]paletteuse=dither=none' \
    -loop 0 "$recording/$scene.gif"
  ffprobe -v error -select_streams v:0 -show_entries stream=width,height:format=duration,size \
    -of default=noprint_wrappers=1 "$recording/$scene.gif"
  cp "$recording/$scene.gif" "$BECKNVIM_DEMO_ROOT/examples/media/$scene.gif"
done
