#!/usr/bin/env bash
# =====================================================================
# install-verified-claude.sh の自動テスト
#
# 偽の curl と gpg を PATH の先頭に置き、CLAUDE_DIST_BASE で配布元の URL の先頭を
# 偽の名前に差し替える。偽の curl は、その名前の URL を手元のフォルダのファイルに置き換える。
# ネットワークも GitHub の権限も使わない。
#
# 偽の gpg の決まり:
#   鍵のファイル: 「FPR <指紋>」の行を持つ。--import で取り込み、--list-keys で主鍵として出す
#   署名のファイル: 「SIG <指紋> <署名した中身の SHA-256>」の1行。--verify は、指紋が取り込んだ鍵にあり、
#                   SHA-256 が中身と合えば、本物の gpg と同じ形の GOODSIG と VALIDSIG を書いて 0 で終わる
#
# 失敗の場合は、終了コードに加えて、標準エラーの理由の文と、GITHUB_PATH に
# 何も足されていないことを確かめる。取りに行けなかったことでも終了コードは同じ 1 になり、
# 終了コードだけでは、どの確かめで止まったのかを区別できないため。
#
# 環境変数 KP_TEST_CASE に場合の名前を入れると、その場合だけを流す(例: KP_TEST_CASE=bad_sha)。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/install-verified-claude.sh"
CASE="${KP_TEST_CASE:-}"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0
VERSION=2.1.323
BASE=https://dist.example.invalid
CLAUDE_FPR=31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE
OTHER_FPR=0123456789ABCDEF0123456789ABCDEF01234567

# 偽の curl と gpg
mkdir -p "$WORK/bin"
cat >"$WORK/bin/curl" <<'EOF'
#!/usr/bin/env bash
out=""
url=""
while [ "$#" -gt 0 ]; do
    case "$1" in
    -o) out="$2"; shift 2 ;;
    --retry | --max-time) shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
    esac
done
case "$url" in "${FAKE_BASE}/"*) ;; *) echo "偽の curl: 知らない URL: $url" >&2; exit 6 ;; esac
src="${FAKE_ROOT}/${url#"${FAKE_BASE}/"}"
[ -f "$src" ] || exit 22
cp "$src" "$out"
EOF
cat >"$WORK/bin/gpg" <<'EOF'
#!/usr/bin/env bash
mode=""
status=""
args=()
while [ "$#" -gt 0 ]; do
    case "$1" in
    --import) mode=import; shift ;;
    --list-keys) mode=list; shift ;;
    --verify) mode=verify; shift ;;
    --status-file) status="$2"; shift 2 ;;
    -*) shift ;;
    *) args+=("$1"); shift ;;
    esac
done
keys="$GNUPGHOME/fake-keys"
touch "$keys"
case "$mode" in
import)
    grep -q '^FPR [0-9A-F]\{40\}$' "${args[0]}" || exit 2
    awk '$1 == "FPR" { print $2 }' "${args[0]}" >>"$keys"
    ;;
list)
    while read -r f; do
        echo "pub:-:255:22:${f:24}:1700000000:::-:::scESC::::::23::0:"
        echo "fpr:::::::::${f}:"
    done <"$keys"
    ;;
verify)
    read -r tag f sum <"${args[0]}"
    [ "$tag" = SIG ] || exit 2
    if ! grep -qx "$f" "$keys"; then
        [ -n "$status" ] && echo "[GNUPG:] NO_PUBKEY ${f:24}" >"$status"
        exit 2
    fi
    if [ "$(sha256sum "${args[1]}" | awk '{ print $1 }')" != "$sum" ]; then
        [ -n "$status" ] && echo "[GNUPG:] BADSIG ${f:24} fake" >"$status"
        exit 1
    fi
    [ -n "$status" ] && {
        echo "[GNUPG:] GOODSIG ${f:24} fake"
        echo "[GNUPG:] VALIDSIG ${f} 2026-11-12 1794514549 0 4 0 22 10 00 ${f}"
    } >"$status"
    ;;
*) exit 2 ;;
esac
exit 0
EOF
chmod +x "$WORK/bin/curl" "$WORK/bin/gpg"

# 使い方: sign <名前> <鍵の指紋>。manifest.json に、指定の鍵で署名し直す
sign() {
    local rel="$WORK/$1/root/claude-code-releases/${VERSION}"
    echo "SIG $2 $(sha256sum "$rel/manifest.json" | awk '{ print $1 }')" >"$rel/manifest.json.sig"
}

# 使い方: build <名前> [manifest の版]。偽の配布物と鍵を $WORK/<名前> に作り、配布元の鍵で署名する
build() {
    local d="$WORK/$1" rel
    rel="$d/root/claude-code-releases/${VERSION}"
    mkdir -p "$rel/linux-x64" "$d/root/keys"
    printf '#!/bin/sh\necho "%s (Claude Code)"\n' "$VERSION" >"$rel/linux-x64/claude"
    printf '{"version":"%s","platforms":{"linux-x64":{"binary":"claude","checksum":"%s","size":1}}}\n' \
        "${2:-$VERSION}" "$(sha256sum "$rel/linux-x64/claude" | awk '{ print $1 }')" >"$rel/manifest.json"
    sign "$1" "$CLAUDE_FPR"
    echo "FPR $CLAUDE_FPR" >"$d/root/keys/claude-code.asc"
}

# 使い方: run <名前> [版]。スクリプトを動かし、終了コードを RC に、標準エラーを $WORK/<名前>/err に置く
run() {
    local d="$WORK/$1"
    : >"$d/github_path"
    PATH="$WORK/bin:$PATH" FAKE_BASE="$BASE" FAKE_ROOT="$d/root" CLAUDE_DIST_BASE="$BASE" \
        CLAUDE_INSTALL_DIR="$d/install" GITHUB_PATH="$d/github_path" \
        bash "$SCRIPT" "${2:-$VERSION}" >/dev/null 2>"$d/err"
    RC=$?
}

ok() { echo "ok   $1"; }
ng() {
    echo "FAIL $1"
    FAILED=1
}

# 使い方: expect_fail <名前> <説明> <理由の文に含まれるはずの文字列>
expect_fail() {
    if [ "$RC" -eq 1 ] && grep -qF -- "$3" "$WORK/$1/err" && [ ! -s "$WORK/$1/github_path" ]; then
        ok "$2"
    else
        ng "$2 (exit=${RC} / 標準エラー: $(cat "$WORK/$1/err"))"
    fi
}

selected() { [ -z "$CASE" ] || [ "$CASE" = "$1" ]; }

if selected good; then
    build good
    run good
    if [ "$RC" -eq 0 ] && [ "$(cat "$WORK/good/github_path")" = "$WORK/good/install/${VERSION}" ] &&
        [ "$("$WORK/good/install/${VERSION}/claude")" = "${VERSION} (Claude Code)" ]; then
        ok "3つとも合えば PATH に足す"
    else
        ng "3つとも合えば PATH に足す (exit=${RC} / 標準エラー: $(cat "$WORK/good/err"))"
    fi
fi

if selected wrong_key; then
    # 鍵の置き場の鍵が別の者の鍵に差し替えられ、その者が manifest.json に署名した
    build wrong_key
    echo "FPR $OTHER_FPR" >"$WORK/wrong_key/root/keys/claude-code.asc"
    sign wrong_key "$OTHER_FPR"
    run wrong_key
    expect_fail wrong_key "指紋の違う鍵では PATH に足さずに失敗する" "公開鍵の指紋が、配布元の鍵の指紋(${CLAUDE_FPR})と違います"
fi

if selected bad_sig; then
    # 署名したあとに manifest.json の SHA-256 が書き換えられた
    build bad_sig
    rel="$WORK/bad_sig/root/claude-code-releases/${VERSION}"
    echo extra >>"$rel/linux-x64/claude"
    printf '{"version":"%s","platforms":{"linux-x64":{"binary":"claude","checksum":"%s","size":1}}}\n' \
        "$VERSION" "$(sha256sum "$rel/linux-x64/claude" | awk '{ print $1 }')" >"$rel/manifest.json"
    run bad_sig
    expect_fail bad_sig "合わない署名では PATH に足さずに失敗する" "manifest.json の署名が正しくありません"
fi

if selected bad_sha; then
    # 署名したあとに実行ファイルが差し替えられた
    build bad_sha
    echo extra >>"$WORK/bad_sha/root/claude-code-releases/${VERSION}/linux-x64/claude"
    run bad_sha
    expect_fail bad_sha "合わない SHA-256 では PATH に足さずに失敗する" "linux-x64/claude の SHA-256 が、署名された manifest.json の値と違います"
fi

if selected other_version; then
    # 配布元の鍵で署名された別の版の manifest.json が、入れる版の場所に置かれた
    build other_version 2.1.300
    run other_version
    expect_fail other_version "署名された manifest.json の版が違えば失敗する" "署名された manifest.json の版(2.1.300)が、入れる版(${VERSION})と違います"
fi

if selected bad_version; then
    build bad_version
    run bad_version "2.1.323;rm"
    expect_fail bad_version "版の形が違えば失敗する" "版の形が違います"
fi

if [ "$FAILED" -ne 0 ]; then
    echo "install-verified-claude.sh のテストに失敗しました"
    exit 1
fi
echo "install-verified-claude.sh のテストはすべて通りました"
