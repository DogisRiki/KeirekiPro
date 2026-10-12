#!/bin/bash
# =====================================================================
# refresh-token.sh(Claude の手元の gh に GitHub App のインストールトークンを入れるスクリプト)のテスト
#
# 実行: bash .claude/scripts/github-app/tests/test-refresh-token.sh
# ネットワークにはつながない。鍵はテストの中で openssl genrsa で作り、curl は、
# 渡された引数と標準入力(ヘッダー)を記録して偽の応答を返す偽物(PATH の先頭に置く)に差し替える。
# GH_CONFIG_DIR は一時ディレクトリに向け、本物の ~/.gh-bot には触れない。
# 前提: bash・perl(JSON::PP)・openssl。ホストの Git Bash から流す。
#
# hosts.yml の user の値を x-access-token にする根拠:
# - GitHub の文書は、インストールトークンで git を HTTP で使うときの利用者名を x-access-token とする
#   https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/authenticating-as-a-github-app-installation
# - gh の git の資格情報ヘルパーは、利用者名を hosts.yml の user から取る。user が x-access-token のときは、
#   git が求める利用者名と照らさずに鍵を返す(tokenUser = "x-access-token")
#   https://github.com/cli/cli/blob/trunk/pkg/cmd/auth/gitcredential/helper.go
# - gh は、トークンを hosts.yml の oauth_token から、利用者を user から読み、users の表や設定の版を求めない
#   https://github.com/cli/cli/blob/trunk/internal/config/config.go
# =====================================================================
set -u

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/refresh-token.sh"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT
# openssl に渡せる形(Windows では C:/...)
WORK=$(cd "$TMP_ROOT" && { pwd -W 2>/dev/null || pwd; })

# --- テスト用の鍵(GitHub が配る App の秘密鍵と同じ PKCS#1 の形)
openssl genrsa -traditional -out "$WORK/app.pem" 2048 2>/dev/null \
    || openssl genrsa -out "$WORK/app.pem" 2048 2>/dev/null \
    || { echo "テスト用の鍵を作れない"; exit 1; }
openssl rsa -in "$WORK/app.pem" -pubout -out "$WORK/app.pub" 2>/dev/null \
    || { echo "テスト用の公開鍵を作れない"; exit 1; }

# --- 偽物の curl
# 引数を1行に1つずつ $FAKE_CURL_ARGS に、-H @- で標準入力から渡されたヘッダーを $FAKE_CURL_HEADERS に残す。
# 応答は $FAKE_CURL_RESPONSE のファイルの中身を標準出力に出し、終了コードは $FAKE_CURL_EXIT(既定0)にする。
mkdir -p "$WORK/bin"
cat >"$WORK/bin/curl" <<'EOF'
#!/bin/bash
: >"$FAKE_CURL_ARGS"
prev=
for a in "$@"; do
    printf '%s\n' "$a" >>"$FAKE_CURL_ARGS"
    if [ "$prev" = -H ] && [ "$a" = @- ]; then
        cat >"$FAKE_CURL_HEADERS"
    fi
    prev=$a
done
if [ "${FAKE_CURL_EXIT:-0}" -ne 0 ]; then
    # 失敗しても標準出力に応答が出ていることがある(--fail-with-body)。終了コードで失敗を見分けることを確かめる
    cat "$FAKE_CURL_RESPONSE"
    echo "curl: (22) The requested URL returned error: 401" >&2
    exit "$FAKE_CURL_EXIT"
fi
cat "$FAKE_CURL_RESPONSE"
EOF
chmod +x "$WORK/bin/curl"
# PATH は : 区切りなので、C: を含まない形のパスで先頭に置く
export PATH="$TMP_ROOT/bin:$PATH"
export FAKE_CURL_ARGS="$WORK/curl-args.log"
export FAKE_CURL_HEADERS="$WORK/curl-headers.log"
export FAKE_CURL_RESPONSE="$WORK/curl-response.json"

CFG="$WORK/gh"
CLIENT_ID=Iv23liTESTCLIENT
INSTALLATION_ID=12345678
NEW_TOKEN=ghs_NewTokenFromFakeCurl0123456789
NEW_EXPIRES_AT=2099-01-02T03:04:05Z
NEW_EXPIRES_EPOCH=$(perl -MTime::Local=timegm -e 'print timegm(5, 4, 3, 2, 0, 2099)')

now() { date +%s; }

reset_state() {
    rm -rf "$CFG"
    mkdir -p "$CFG"
    rm -f "$FAKE_CURL_ARGS" "$FAKE_CURL_HEADERS"
    printf '{"token":"%s","expires_at":"%s","permissions":{"contents":"write"},"repository_selection":"selected"}\n' \
        "$NEW_TOKEN" "$NEW_EXPIRES_AT" >"$FAKE_CURL_RESPONSE"
    unset FAKE_CURL_EXIT
    export GH_CONFIG_DIR="$CFG"
}

# github-app.env を置く(Windows のメモ帳で作ったときの CRLF の行末にする)
put_env() {
    printf 'APP_CLIENT_ID=%s\r\nINSTALLATION_ID=%s\r\nPRIVATE_KEY_FILE=%s\r\n' \
        "$CLIENT_ID" "$INSTALLATION_ID" "$WORK/app.pem" >"$CFG/github-app.env"
}
put_old_hosts() {
    printf 'github.com:\n    oauth_token: ghs_OldToken\n    git_protocol: https\n    user: x-access-token\n' >"$CFG/hosts.yml"
}
put_expires() { printf '%s\n' "$1" >"$CFG/github-app-token.expires"; }

curl_called() { [ -f "$FAKE_CURL_ARGS" ]; }

# 一時ファイルを残していないこと(置き場にあるのは決まったファイルだけ)
no_leftovers() {
    local f
    for f in "$CFG"/* "$CFG"/.[!.]*; do
        [ -e "$f" ] || continue
        case "${f##*/}" in
            github-app.env | hosts.yml | github-app-token.expires) ;;
            *) die "一時ファイルが残っている: ${f##*/}" ;;
        esac
    done
}

# 失敗の理由を出して、そのテストを終える(テストは run_test のサブシェルで動く)
die() {
    printf '%s\n' "$*"
    exit 1
}

# base64url を復号して標準出力に出す
b64url_decode() {
    perl -MMIME::Base64 -e '$_ = shift; tr{-_}{+/}; $_ .= "=" x ((4 - length() % 4) % 4); binmode STDOUT; print decode_base64($_)' "$1"
}

# JSON の1つのキーの値を出す
json_get() { # <JSON> <キー>
    printf '%s' "$1" | perl -MJSON::PP -e 'local $/; my $d = decode_json(<STDIN>); print $d->{$ARGV[0]} // ""' "$2"
}

# 偽物の curl に渡った JWT を確かめる(ヘッダーと中身、テスト用の公開鍵での署名の検証)
check_jwt() {
    local auth jwt h p s t
    [ -f "$FAKE_CURL_HEADERS" ] || die "ヘッダーが標準入力(-H @-)で curl に渡っていない"
    auth=$(grep -i '^Authorization: Bearer ' "$FAKE_CURL_HEADERS" | tr -d '\r') \
        || die "Authorization のヘッダーが無い: $(cat "$FAKE_CURL_HEADERS")"
    jwt=${auth#*Bearer }
    grep -qF -- "$jwt" "$FAKE_CURL_ARGS" && die "JWT がコマンドの引数に出ている"
    IFS=. read -r h p s <<<"$jwt"
    [ -n "$h" ] && [ -n "$p" ] && [ -n "$s" ] || die "JWT が3つの部分に分かれていない: $jwt"
    [ "$(json_get "$(b64url_decode "$h")" alg)" = RS256 ] || die "alg が RS256 でない: $(b64url_decode "$h")"
    [ "$(json_get "$(b64url_decode "$h")" typ)" = JWT ] || die "typ が JWT でない"
    local payload iat exp iss
    payload=$(b64url_decode "$p")
    iss=$(json_get "$payload" iss)
    iat=$(json_get "$payload" iat)
    exp=$(json_get "$payload" exp)
    t=$(now)
    [ "$iss" = "$CLIENT_ID" ] || die "iss が APP_CLIENT_ID でない: $payload"
    # iat は60秒前、exp は540秒後(テストの実行の遅れを5秒まで許す)
    [ $((t - 60 - iat)) -ge 0 ] && [ $((t - 60 - iat)) -le 5 ] || die "iat が60秒前でない: iat=$iat now=$t"
    [ $((t + 540 - exp)) -ge 0 ] && [ $((t + 540 - exp)) -le 5 ] || die "exp が540秒後でない: exp=$exp now=$t"
    printf '%s.%s' "$h" "$p" >"$WORK/jwt-input"
    b64url_decode "$s" >"$WORK/jwt-sig"
    openssl dgst -sha256 -verify "$WORK/app.pub" -signature "$WORK/jwt-sig" "$WORK/jwt-input" >/dev/null 2>&1 \
        || die "JWT の署名をテスト用の公開鍵で検証できない"
}

# 偽物の curl への呼び方を確かめる
check_curl_call() {
    grep -qx -- "https://api.github.com/app/installations/$INSTALLATION_ID/access_tokens" "$FAKE_CURL_ARGS" \
        || die "発行の URL が違う: $(tr '\n' ' ' <"$FAKE_CURL_ARGS")"
    grep -A1 -x -- '-X' "$FAKE_CURL_ARGS" | grep -qx POST || die "POST で呼んでいない: $(tr '\n' ' ' <"$FAKE_CURL_ARGS")"
    grep -A1 -x -- '--max-time' "$FAKE_CURL_ARGS" | grep -qx 20 || die "--max-time 20 が無い: $(tr '\n' ' ' <"$FAKE_CURL_ARGS")"
}

# 新しいトークンが hosts.yml と期限のファイルに書かれていること
check_new_written() {
    local want
    want=$(printf 'github.com:\n    oauth_token: %s\n    git_protocol: https\n    user: x-access-token' "$NEW_TOKEN")
    [ "$(cat "$CFG/hosts.yml")" = "$want" ] || die "hosts.yml の中身が違う: $(cat "$CFG/hosts.yml")"
    [ "$(tr -d '\r\n' <"$CFG/github-app-token.expires")" = "$NEW_EXPIRES_EPOCH" ] \
        || die "期限のファイルが expires_at の UNIX 時刻でない: $(cat "$CFG/github-app-token.expires")"
}

pass=0
fail=0
run_test() { # <テスト名> <関数>
    local name="$1" fn="$2" out
    reset_state
    if out=$("$fn" 2>&1); then
        pass=$((pass + 1))
        printf 'ok: %s\n' "$name"
    else
        fail=$((fail + 1))
        printf 'FAIL: %s\n' "$name"
        printf '%s\n' "$out" | sed 's/^/    /'
    fi
}

# ---------------------------------------------------------------------

t_no_env() {
    put_old_hosts
    local before
    before=$(cat "$CFG/hosts.yml")
    bash "$SCRIPT" || die "終了コードが0でない: $?"
    curl_called && die "curl を呼んだ"
    [ "$(cat "$CFG/hosts.yml")" = "$before" ] || die "hosts.yml が変わった"
    [ -e "$CFG/github-app-token.expires" ] && die "期限のファイルを書いた"
    rm -f "$CFG/hosts.yml"
    bash "$SCRIPT" --force || die "--force でも終了コードが0でない: $?"
    curl_called && die "--force で curl を呼んだ"
    [ -e "$CFG/hosts.yml" ] && die "hosts.yml を書いた"
    true
}

t_no_config_dir() {
    unset GH_CONFIG_DIR
    bash "$SCRIPT" --force || die "GH_CONFIG_DIR が無いときの終了コードが0でない: $?"
    curl_called && die "GH_CONFIG_DIR が無いのに curl を呼んだ"
    export GH_CONFIG_DIR="$WORK/no-such-dir"
    bash "$SCRIPT" --force || die "GH_CONFIG_DIR のディレクトリが無いときの終了コードが0でない: $?"
    curl_called && die "GH_CONFIG_DIR のディレクトリが無いのに curl を呼んだ"
    [ -e "$WORK/no-such-dir" ] && die "GH_CONFIG_DIR のディレクトリを作った"
    true
}

t_not_near_expiry() {
    put_env
    put_old_hosts
    put_expires $(($(now) + 601))
    bash "$SCRIPT" || die "終了コードが0でない: $?"
    curl_called && die "期限まで600秒以上あるのに curl を呼んだ"
    grep -q 'ghs_OldToken' "$CFG/hosts.yml" || die "hosts.yml が変わった"
    true
}

t_near_expiry() {
    put_env
    put_old_hosts
    put_expires $(($(now) + 590))
    local err
    err=$(bash "$SCRIPT" 2>&1) || die "終了コードが0でない: $? $err"
    curl_called || die "期限が近いのに curl を呼んでいない"
    check_curl_call
    check_jwt
    check_new_written
    no_leftovers
}

t_no_expires_file() {
    put_env
    bash "$SCRIPT" || die "終了コードが0でない: $?"
    curl_called || die "期限のファイルが無いのに curl を呼んでいない"
    check_new_written
    no_leftovers
}

t_force() {
    put_env
    put_old_hosts
    put_expires $(($(now) + 3600))
    bash "$SCRIPT" --force || die "終了コードが0でない: $?"
    curl_called || die "--force なのに curl を呼んでいない"
    check_jwt
    check_new_written
    no_leftovers
}

t_curl_fails() {
    put_env
    put_old_hosts
    put_expires 100
    local before_hosts before_exp out rc=0
    before_hosts=$(cat "$CFG/hosts.yml")
    before_exp=$(cat "$CFG/github-app-token.expires")
    export FAKE_CURL_EXIT=22
    out=$(bash "$SCRIPT" 2>&1 >/dev/null) || rc=$?
    [ "$rc" -eq 1 ] || die "終了コードが1でない: $rc"
    [ -n "$out" ] || die "標準エラーに理由が出ていない"
    [ "$(cat "$CFG/hosts.yml")" = "$before_hosts" ] || die "hosts.yml を書き換えた"
    [ "$(cat "$CFG/github-app-token.expires")" = "$before_exp" ] || die "期限のファイルを書き換えた"
    no_leftovers
}

t_bad_response() {
    put_env
    put_old_hosts
    local before out rc=0 body
    before=$(cat "$CFG/hosts.yml")
    for body in '{"message":"Bad credentials"}' 'not json' \
        '{"token":"ghs_x\nuser: evil","expires_at":"2099-01-02T03:04:05Z"}' \
        '{"token":"ghs_OK","expires_at":"tomorrow"}'; do
        printf '%s\n' "$body" >"$FAKE_CURL_RESPONSE"
        rc=0
        out=$(bash "$SCRIPT" --force 2>&1 >/dev/null) || rc=$?
        [ "$rc" -eq 1 ] || die "応答が $body のときの終了コードが1でない: $rc"
        [ -n "$out" ] || die "応答が $body のときに標準エラーに理由が出ていない"
        # 理由はフックが会話に載せるので、応答のトークンを出さない
        case "$out" in *ghs_*) die "応答が $body のときに標準エラーにトークンを出した: $out" ;; esac
        [ "$(cat "$CFG/hosts.yml")" = "$before" ] || die "応答が $body のときに hosts.yml を書き換えた"
        [ -e "$CFG/github-app-token.expires" ] && die "応答が $body のときに期限のファイルを書いた"
    done
    no_leftovers
}

t_env_incomplete() {
    put_old_hosts
    local rc=0
    printf 'APP_CLIENT_ID=%s\nPRIVATE_KEY_FILE=%s\n' "$CLIENT_ID" "$WORK/app.pem" >"$CFG/github-app.env"
    bash "$SCRIPT" 2>/dev/null || rc=$?
    [ "$rc" -eq 1 ] || die "INSTALLATION_ID が無いときの終了コードが1でない: $rc"
    curl_called && die "INSTALLATION_ID が無いのに curl を呼んだ"
    rc=0
    printf 'APP_CLIENT_ID=%s\nINSTALLATION_ID=%s\nPRIVATE_KEY_FILE=%s\n' "$CLIENT_ID" "$INSTALLATION_ID" "$WORK/no-such.pem" >"$CFG/github-app.env"
    bash "$SCRIPT" 2>/dev/null || rc=$?
    [ "$rc" -eq 1 ] || die "秘密鍵のファイルが無いときの終了コードが1でない: $rc"
    curl_called && die "秘密鍵のファイルが無いのに curl を呼んだ"
    grep -q 'ghs_OldToken' "$CFG/hosts.yml" || die "hosts.yml が変わった"
    true
}

t_backslash_config_dir() {
    # 本物の GH_CONFIG_DIR は settings.local.json の %USERPROFILE%\.gh-bot から来るので、区切りが \ になる
    case "$CFG" in
        [A-Za-z]:/*) ;;
        *) echo "ドライブ文字の無い環境なので飛ばす"; return 0 ;;
    esac
    put_env
    export GH_CONFIG_DIR="${CFG//\//\\}"
    bash "$SCRIPT" --force || die "終了コードが0でない: $?"
    check_new_written
    no_leftovers
}

t_bad_args() {
    local rc=0
    put_env
    bash "$SCRIPT" --bogus 2>/dev/null || rc=$?
    [ "$rc" -eq 64 ] || die "知らない引数のときの終了コードが64でない: $rc"
    rc=0
    bash "$SCRIPT" --force extra 2>/dev/null || rc=$?
    [ "$rc" -eq 64 ] || die "引数が多すぎるときの終了コードが64でない: $rc"
    curl_called && die "呼び方の誤りなのに curl を呼んだ"
    true
}

echo "--- 何もしないとき"
run_test "github-app.env が無ければ、curl を呼ばず hosts.yml を書かずに終了コード0で終える" t_no_env
run_test "GH_CONFIG_DIR が無いか、そのディレクトリが無ければ、何もせずに終了コード0で終える" t_no_config_dir
run_test "期限まで600秒以上あれば、curl を呼ばずに終了コード0で終える" t_not_near_expiry

echo "--- 発行するとき"
run_test "期限が近ければ、署名した JWT で発行したトークンを hosts.yml と期限のファイルに書く" t_near_expiry
run_test "期限のファイルが無ければ発行する" t_no_expires_file
run_test "--force なら期限の前でも発行する" t_force
run_test "GH_CONFIG_DIR の区切りが \\ でも発行できる" t_backslash_config_dir

echo "--- 失敗したとき"
run_test "curl が失敗したら hosts.yml を書き換えずに終了コード1で終える" t_curl_fails
run_test "応答にトークンか期限が無いか、形が違えば hosts.yml を書き換えずに終了コード1で終える" t_bad_response
run_test "github-app.env の値が欠けているか秘密鍵が無ければ、curl を呼ばずに終了コード1で終える" t_env_incomplete
run_test "呼び方を誤れば終了コード64で終える" t_bad_args

echo
echo "結果: 成功 $pass / 失敗 $fail"
[ "$fail" -eq 0 ]
