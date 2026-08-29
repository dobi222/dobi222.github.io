#!/usr/bin/env bash
#
# 포스트 이미지 최적화
#
# VS Code에서 _posts 안의 글(하위 폴더 포함)로 사진을 드래그하면
#   1) assets/img/posts/<글이름>/ 아래로 원본이 복사되고
#   2) 본문에는 문서 기준 상대경로(../assets/...)가 삽입된다.
#
# 이 스크립트는 그 두 가지를 블로그에 맞게 바로잡는다.
#   - 원본을 긴 변 1600px WebP 로 변환하고 원본은 지운다
#   - 본문 경로를 사이트 루트 기준(/assets/...) + .webp 로 고쳐 쓴다
#
# 사용법:
#   bash tools/optimize-images.sh           변환만
#   bash tools/optimize-images.sh --stage   변환 후 git add (pre-commit 훅용)

set -eu

MAX_EDGE=1600
QUALITY=80
IMG_ROOT="assets/img/posts"

cd "$(dirname "$0")/.."

STAGE=no
[ "${1:-}" = "--stage" ] && STAGE=yes

command -v cwebp >/dev/null 2>&1 || {
  echo "optimize-images: cwebp 가 없습니다. 'brew install webp' 후 다시 시도하세요." >&2
  exit 1
}

converted=0

if [ -d "$IMG_ROOT" ]; then
  while IFS= read -r -d '' src; do
    dst="${src%.*}.webp"
    ext=$(printf '%s' "${src##*.}" | tr '[:upper:]' '[:lower:]')

    # 긴 변만 줄인다. 이미 작은 사진은 확대하지 않는다.
    dims=$(sips -g pixelWidth -g pixelHeight "$src" 2>/dev/null |
      awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w" "h}')
    w=${dims% *}
    h=${dims#* }
    resize=""
    if [ -n "$w" ] && [ -n "$h" ]; then
      if [ "$w" -ge "$h" ] && [ "$w" -gt "$MAX_EDGE" ]; then
        resize="-resize $MAX_EDGE 0"
      elif [ "$h" -gt "$w" ] && [ "$h" -gt "$MAX_EDGE" ]; then
        resize="-resize 0 $MAX_EDGE"
      fi
    fi

    # cwebp 는 HEIC 를 못 읽으므로 sips 로 한 번 거친다.
    tmp=""
    input="$src"
    if [ "$ext" = "heic" ] || [ "$ext" = "heif" ]; then
      tmp="${TMPDIR:-/tmp}/optimg-$$-$(basename "${src%.*}").jpg"
      sips -s format jpeg -s formatOptions 95 "$src" --out "$tmp" >/dev/null 2>&1
      input="$tmp"
    fi

    before=$(wc -c <"$src" | tr -d ' ')
    # shellcheck disable=SC2086
    cwebp -quiet -q "$QUALITY" $resize "$input" -o "$dst"
    after=$(wc -c <"$dst" | tr -d ' ')
    [ -n "$tmp" ] && rm -f "$tmp"

    rm -f "$src"
    converted=$((converted + 1))
    echo "  $(basename "$src") → $(basename "$dst")  $((before / 1024))KB → $((after / 1024))KB"
  done < <(find "$IMG_ROOT" -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \
    -o -iname '*.heic' -o -iname '*.heif' -o -iname '*.tif' -o -iname '*.tiff' \) -print0)
fi

# 본문 경로 교정. 변환 여부와 무관하게 항상 훑는다.
rewrote=0
while IFS= read -r -d '' md; do
  cp "$md" "$md.bak"

  # ../assets, ./assets, assets → /assets
  # 파일명에 공백이 있으면 VS Code 가 ](<...>) 꺾쇠 형태로 넣으므로 그것도 처리한다.
  sed -E -i '' \
    -e 's#\]\(<(\.\./)+assets/#](</assets/#g' \
    -e 's#\]\(<\./assets/#](</assets/#g' \
    -e 's#\]\(<assets/#](</assets/#g' \
    -e 's#\]\((\.\./)+assets/#](/assets/#g' \
    -e 's#\]\(\./assets/#](/assets/#g' \
    -e 's#\]\(assets/#](/assets/#g' \
    -e 's#src="(\.\./)+assets/#src="/assets/#g' \
    -e 's#src="\./assets/#src="/assets/#g' \
    -e 's#src="assets/#src="/assets/#g' \
    "$md"

  # assets/img/posts 아래 이미지는 전부 webp 이므로 확장자를 맞춘다.
  sed -E -i '' \
    -e 's#(/assets/img/posts/[^")]*)\.(jpe?g|png|heic|heif|tiff?|JPE?G|PNG|HEIC|HEIF|TIFF?)#\1.webp#g' \
    "$md"

  if cmp -s "$md" "$md.bak"; then
    rm -f "$md.bak"
  else
    rm -f "$md.bak"
    rewrote=$((rewrote + 1))
    echo "  경로 교정: $md"
    [ "$STAGE" = yes ] && git add -- "$md"
  fi
done < <(find _posts -type f -name '*.md' -print0)

if [ "$STAGE" = yes ] && [ -d "$IMG_ROOT" ]; then
  git add -A -- "$IMG_ROOT"
fi

if [ "$converted" -gt 0 ] || [ "$rewrote" -gt 0 ]; then
  echo "optimize-images: 사진 ${converted}장 변환, 글 ${rewrote}편 경로 교정"
fi
