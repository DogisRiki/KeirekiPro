#!/bin/bash
# =====================================================================
# PostToolUse(Edit|Write) hook: UTF-8文字化け検知
#
# 書き込まれたテキストファイルに不正なUTF-8バイト列、または
# 置換文字(U+FFFD)が含まれる場合にブロックする(exit 2)。
# 日本語×Windows環境での文字化けの機械的検知。
# 前提: Git for Windows(Git Bash同梱)。JSON解析は同梱perl(JSON::PP)を使用。
# =====================================================================
set -u

payload=$(cat)

file_path=$(printf '%s' "$payload" | perl -MJSON::PP -e '
    local $/; my $d = eval { JSON::PP::decode_json(<STDIN>) };
    exit 0 unless ref $d;
    my $v = eval { $d->{tool_input}{file_path} };
    print $v if defined $v && !ref $v;
' 2>/dev/null)
[ -z "$file_path" ] && exit 0

file_path=${file_path//\\//}
[ -f "$file_path" ] || exit 0
[ -s "$file_path" ] || exit 0

# 対象拡張子のみ検査(小文字化して判定)
ext=$(printf '%s' "${file_path##*.}" | tr '[:upper:]' '[:lower:]')
case ".$ext" in
    .ts | .tsx | .js | .jsx | .java | .md | .json | .yaml | .yml | \
        .sql | .gradle | .xml | .html | .css | .sh | .ps1 | .txt | \
        .pu | .properties | .toml | .tf | .tfvars | .hcl | .ftl | .mjs | .cjs) ;;
    *) exit 0 ;;
esac

# 不正なUTF-8バイト列の検知
if ! iconv -f UTF-8 -t UTF-8 "$file_path" >/dev/null 2>&1; then
    {
        echo "不正なUTF-8バイト列を検出しました: $file_path"
        echo "文字化けした内容を保存しないでください。ファイルをUTF-8で書き直してください。判読できない場合は推測せず停止して報告してください。"
    } >&2
    exit 2
fi

# 置換文字(U+FFFD)の検知
if LC_ALL=C grep -q "$(printf '\xef\xbf\xbd')" "$file_path"; then
    {
        echo "置換文字(U+FFFD)を検出しました: $file_path"
        echo "文字化けの痕跡です。正しい日本語に修正してから保存してください。"
    } >&2
    exit 2
fi

exit 0
