#!/bin/bash
# =====================================================================
# Claude の手元の gh に GitHub App のインストールトークンを入れるスクリプト(refresh-token.sh)
#
# 呼び方: refresh-token.sh [--force]
# 入力:   $GH_CONFIG_DIR/github-app.env(APP_CLIENT_ID・INSTALLATION_ID・PRIVATE_KEY_FILE の3行。KEY=VALUE の形)
# 状態:   $GH_CONFIG_DIR/github-app-token.expires(トークンの期限の UNIX 時刻)
# 出力:   $GH_CONFIG_DIR/hosts.yml(gh が読むトークン。git の push も gh auth git-credential を通して使う)
#
# GH_CONFIG_DIR か github-app.env が無ければ、何もせずに終了コード0で終える。
# 期限まで600秒以上あり、--force も無ければ、何もせずに終了コード0で終える。
# そうでなければ、App の秘密鍵で署名した JWT でインストールトークンを発行し、
# hosts.yml と期限のファイルを、同じディレクトリの一時ファイルに書いてから名前の付け替えで置き換える。
#
# 終了コード: 0 成功か何もしなかった / 1 発行に失敗した(理由を標準エラーに出し、hosts.yml は書き換えない)/ 64 呼び方の誤り
# 前提: bash・openssl・curl・perl(JSON::PP)。Windows では Git for Windows(Git Bash 同梱)がこれらを提供する。
# JWT は、ほかのプロセスから見えるコマンドの引数に載せず、標準入力で curl に渡す。
# =====================================================================
set -u

# 期限までこの秒数を切ったら発行し直す
REFRESH_BEFORE_SECONDS=600

usage() {
    echo "使い方: refresh-token.sh [--force]" >&2
    exit 64
}

fail() {
    printf 'refresh-token.sh: %s\n' "$*" >&2
    exit 1
}

force=0
case "$#:${1:-}" in
    0:) ;;
    1:--force) force=1 ;;
    *) usage ;;
esac

# Windows の区切り(\)を / に直し、openssl と curl に渡せる形(Windows では C:/...)の絶対パスにする
native_dir() {
    (cd "${1//\\//}" 2>/dev/null && { pwd -W 2>/dev/null || pwd; })
}

[ -n "${GH_CONFIG_DIR:-}" ] || exit 0
[ -d "${GH_CONFIG_DIR//\\//}" ] || exit 0
CFG=$(native_dir "$GH_CONFIG_DIR") || exit 0
ENV_FILE="$CFG/github-app.env"
[ -f "$ENV_FILE" ] || exit 0
EXPIRES_FILE="$CFG/github-app-token.expires"
HOSTS_FILE="$CFG/hosts.yml"

now=$(date +%s)
if [ "$force" -eq 0 ] && [ -f "$EXPIRES_FILE" ]; then
    expires=$(tr -d ' \r\n' <"$EXPIRES_FILE")
    case "$expires" in
        '' | *[!0-9]*) ;;
        *) [ $((expires - now)) -lt "$REFRESH_BEFORE_SECONDS" ] || exit 0 ;;
    esac
fi

# --- github-app.env を読む(source せず、決まった3つのキーだけを受け取る。CRLF の行末も受け付ける)
APP_CLIENT_ID=
INSTALLATION_ID=
PRIVATE_KEY_FILE=
while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    case "$line" in
        APP_CLIENT_ID=*) APP_CLIENT_ID=${line#*=} ;;
        INSTALLATION_ID=*) INSTALLATION_ID=${line#*=} ;;
        PRIVATE_KEY_FILE=*) PRIVATE_KEY_FILE=${line#*=} ;;
    esac
done <"$ENV_FILE"
[ -n "$APP_CLIENT_ID" ] || fail "github-app.env に APP_CLIENT_ID が無い"
case "$INSTALLATION_ID" in
    '' | *[!0-9]*) fail "github-app.env の INSTALLATION_ID が数字でない" ;;
esac
[ -n "$PRIVATE_KEY_FILE" ] || fail "github-app.env に PRIVATE_KEY_FILE が無い"
PRIVATE_KEY_FILE=${PRIVATE_KEY_FILE//\\//}
[ -f "$PRIVATE_KEY_FILE" ] || fail "秘密鍵のファイルが無い: $PRIVATE_KEY_FILE"
key_dir=$(native_dir "$(dirname "$PRIVATE_KEY_FILE")") || fail "秘密鍵のディレクトリを開けない: $PRIVATE_KEY_FILE"
KEY="$key_dir/$(basename "$PRIVATE_KEY_FILE")"

# --- JWT を作って署名する(iat は60秒前、exp は540秒後、iss は App の Client ID)
b64url() {
    perl -MMIME::Base64 -e 'binmode STDIN; local $/; $_ = encode_base64(<STDIN>, ""); tr{+/}{-_}; s/=+$//; print'
}
jwt_header=$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)
jwt_payload=$(perl -MJSON::PP -e 'print JSON::PP->new->canonical->encode({iat => $ARGV[0] - 60, exp => $ARGV[0] + 540, iss => $ARGV[1]})' \
    "$now" "$APP_CLIENT_ID" | b64url) || fail "JWT の中身を作れない"
signing_input="$jwt_header.$jwt_payload"
signature=$(set -o pipefail; printf '%s' "$signing_input" | openssl dgst -sha256 -sign "$KEY" -binary | b64url) \
    && [ -n "$signature" ] || fail "秘密鍵で JWT に署名できない: $KEY"
jwt="$signing_input.$signature"

# --- インストールトークンを発行する
url="https://api.github.com/app/installations/$INSTALLATION_ID/access_tokens"
response=$(printf 'Authorization: Bearer %s\nAccept: application/vnd.github+json\nX-GitHub-Api-Version: 2022-11-28\n' "$jwt" \
    | curl --silent --show-error --fail-with-body --max-time 20 -X POST -H @- "$url") \
    || fail "インストールトークンを発行できない: ${response:-応答なし}"

# 応答の token と expires_at を読む。hosts.yml を壊さないよう、トークンは英数字と _ だけを受け付ける
parsed=$(printf '%s' "$response" | perl -MJSON::PP -MTime::Local=timegm -e '
    local $/;
    my $d = eval { decode_json(<STDIN>) } or exit 1;
    ref $d eq "HASH" or exit 1;
    my $t = $d->{token} // "";
    $t =~ /\A[A-Za-z0-9_]+\z/ or exit 1;
    my ($Y, $M, $D, $h, $m, $s) = ($d->{expires_at} // "") =~ /\A(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)(?:\.\d+)?Z\z/ or exit 1;
    print "$t ", timegm($s, $m, $h, $D, $M - 1, $Y), "\n";
') || fail "発行の応答から token と expires_at を読めない(応答はトークンを含みうるので出さない)"
token=${parsed% *}
expires_at=${parsed#* }

# --- 一時ファイルに書いてから置き換える(名前の付け替えなので、同時に呼ばれても hosts.yml が途中で壊れない)
umask 077
tmp_hosts=$(mktemp "$CFG/.hosts.yml.XXXXXX") || fail "一時ファイルを作れない: $CFG"
tmp_expires=$(mktemp "$CFG/.github-app-token.expires.XXXXXX") || { rm -f "$tmp_hosts"; fail "一時ファイルを作れない: $CFG"; }
trap 'rm -f "$tmp_hosts" "$tmp_expires"' EXIT
printf 'github.com:\n    oauth_token: %s\n    git_protocol: https\n    user: x-access-token\n' "$token" >"$tmp_hosts" \
    || fail "一時ファイルに書けない: $tmp_hosts"
printf '%s\n' "$expires_at" >"$tmp_expires" || fail "一時ファイルに書けない: $tmp_expires"
mv -f "$tmp_hosts" "$HOSTS_FILE" || fail "hosts.yml を置き換えられない: $HOSTS_FILE"
mv -f "$tmp_expires" "$EXPIRES_FILE" || fail "期限のファイルを置き換えられない: $EXPIRES_FILE"
exit 0
