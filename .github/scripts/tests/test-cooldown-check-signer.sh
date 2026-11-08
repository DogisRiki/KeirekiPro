#!/usr/bin/env bash
# =====================================================================
# cooldown-check-signer.sh の自動テスト(dependency-review CI から実行)
#
# curl と gh をスタブし、前の版と新しい版の署名した者の比べ方と、調べられないときの
# 扱いを検証する。npm の来歴の形は、2026-11-02 に registry.npmjs.org の
# /-/npm/v1/attestations/sigstore@3.0.0 と sigstore@3.1.0 から1回ずつ取った答えを
# もとにしてある。real_same の場合は、そのとき取った2つの来歴の証明書をそのまま使う。
# ほかの場合の証明書は、同じ拡張の OID を持たせて、テストの中で作る。
#
# maven の場合は、テストの中で作った使い捨ての鍵で .pom に署名し、鍵サーバの答えも
# その鍵で作る。real_pg の場合は、2026-11-02 に取った org.postgresql:postgresql の
# 2つの版の .pom と .pom.asc と公開鍵をそのまま使う。この2つの署名には、発行者の指紋が無く、
# 発行者の鍵 ID だけがある。
#
# 環境変数 KP_TEST_CASE に場合の名前を入れると、その場合だけを流す。
# 外部への問い合わせを行わないため、実行にネットワークを必要としない。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/cooldown-check-signer.sh"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'gpgconf --homedir "$WORK/gpg-maker" --kill gpg-agent >/dev/null 2>&1; rm -rf "$WORK"' EXIT
FAILED=0
CASE="${KP_TEST_CASE:-}"
NPM="https://registry.npm.invalid"
CENTRAL="https://central.maven.invalid/maven2"
PORTAL="https://portal.gradle.invalid/m2"
KEYS="https://keys.invalid"
STUB="$WORK/stub"

mkdir -p "$WORK/bin" "$STUB/att" "$STUB/doc" "$STUB/tgz" "$STUB/central" "$STUB/portal" "$STUB/keys"

# --- curl と gh のスタブ -------------------------------------------------------------
# curl: 取った URL と --max-time の値を $STUB_CALLS に1行で記録する。-L(-sSL のように
#   まとめた短い指定を含む)があれば、
#   "FOLLOW <URL>" の1行も記録する。
#   <CENTRAL>/<パス>: $STUB_DIR/central/<パス>
#   <PORTAL>/<パス>: $STUB_DIR/portal/<パス>。Gradle Plugin Portal は別の URL へ転送して返すので、
#     -L が無ければ HTTP 302 を返す
#   <KEYS>/pks/lookup?...search=0x<指紋か鍵 ID>: $STUB_DIR/keys/<指紋か鍵 ID>
#   <NPM>/-/npm/v1/attestations/<名前>@<版>: $STUB_DIR/att/<名前の / を _ にしたもの>@<版>
#   <NPM>/.../<ファイル>.tgz: $STUB_DIR/tgz/<ファイル>.tgz
#   <NPM>/<名前>: $STUB_DIR/doc/<URL のままの名前>
#   ファイルの名前に .fail を足したファイルがあれば HTTP 500、.fail-once なら1回だけ 500。
#   ファイルが無ければ 404。
cat >"$WORK/bin/curl" <<'STUB'
#!/usr/bin/env bash
url="" out="" maxt="" prev="" follow=""
for a in "$@"; do
    case "$prev" in
    -o) out="$a" ;;
    --max-time) maxt="$a" ;;
    esac
    case "$a" in
    http*) url="$a" ;;
    -L | -[!-]*L*) follow=1 ;;
    esac
    prev="$a"
done
echo "GET ${url} max-time=${maxt}" >>"${STUB_CALLS:?}"
[ -n "$follow" ] && echo "FOLLOW ${url}" >>"$STUB_CALLS"
case "$url" in
"${STUB_CENTRAL:?}"/*) f="${STUB_DIR:?}/central/${url#"${STUB_CENTRAL}"/}" ;;
"${STUB_PORTAL:?}"/*)
    if [ -z "$follow" ]; then : >"$out"; printf 302; exit 0; fi
    f="${STUB_DIR:?}/portal/${url#"${STUB_PORTAL}"/}"
    ;;
"${STUB_KEYS:?}"/pks/lookup\?*) f="${STUB_DIR:?}/keys/${url##*search=0x}" ;;
"${STUB_NPM:?}"/-/npm/v1/attestations/*) f="${STUB_DIR:?}/att/$(printf '%s' "${url#*/attestations/}" | tr '/' '_')" ;;
*.tgz) f="${STUB_DIR:?}/tgz/${url##*/}" ;;
"${STUB_NPM}"/*) f="${STUB_DIR:?}/doc/${url#"${STUB_NPM}"/}" ;;
*) exit 6 ;;
esac
if [ -e "${f}.fail-once" ]; then rm -f "${f}.fail-once"; printf '{}' >"$out"; printf 500; exit 0; fi
if [ -e "${f}.fail" ]; then printf '{}' >"$out"; printf 500; exit 0; fi
if [ -f "$f" ]; then cp "$f" "$out"; printf 200; exit 0; fi
printf '{"error":"not found"}' >"$out"
printf 404
STUB
chmod +x "$WORK/bin/curl"

# gh: 引数を $STUB_CALLS に "GH <引数>" の1行で記録し、--bundle のファイルを
#   $STUB_DIR/gh-bundle.json に写す。$STUB_DIR/gh.fail があれば終了コード 1。
cat >"$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "GH $*" >>"${STUB_CALLS:?}"
prev=""
for a in "$@"; do
    [ "$prev" = "--bundle" ] && cp "$a" "${STUB_DIR:?}/gh-bundle.json"
    prev="$a"
done
if [ -e "${STUB_DIR:?}/gh.fail" ]; then echo "verification failed" >&2; exit 1; fi
echo "Loaded digest sha512:... ✓ Verification succeeded!"
STUB
chmod +x "$WORK/bin/gh"

# --- 2026-11-02 に取った sigstore@3.0.0 と 3.1.0 の SLSA の来歴の証明書 -------------------
# 3つの欄は、どちらも OIDC の発行元 https://token.actions.githubusercontent.com、
# 元のリポジトリの ID 495574555、組み立ての設定
# https://github.com/sigstore/sigstore-js/.github/workflows/release.yml@refs/heads/main である。
cat >"$WORK/real-3.0.0.b64" <<'CERT'
MIIGtTCCBjugAwIBAgIUFZbCpi3CDAWvgrLHxtg1Y7uuzmUwCgYIKoZIzj0EAwMwNzEVMBMGA1UE
ChMMc2lnc3RvcmUuZGV2MR4wHAYDVQQDExVzaWdzdG9yZS1pbnRlcm1lZGlhdGUwHhcNMjQxMDE0
MTYxMzQ1WhcNMjQxMDE0MTYyMzQ1WjAAMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEf1geHKJm
qtJp8PDuLWzA/2kUwTWxIQZuDpBv+oyuT7r/Ja7Ro8kGEQrJ/DBFSpT/npc35Pk3LmmRylyYoedR
t6OCBVowggVWMA4GA1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggrBgEFBQcDAzAdBgNVHQ4EFgQU
mohazNhKN4gAImBmQV8TTMyBpeswHwYDVR0jBBgwFoAU39Ppz1YkEZb5qNjpKFWixi4YZD8wYwYD
VR0RAQH/BFkwV4ZVaHR0cHM6Ly9naXRodWIuY29tL3NpZ3N0b3JlL3NpZ3N0b3JlLWpzLy5naXRo
dWIvd29ya2Zsb3dzL3JlbGVhc2UueW1sQHJlZnMvaGVhZHMvbWFpbjA5BgorBgEEAYO/MAEBBCto
dHRwczovL3Rva2VuLmFjdGlvbnMuZ2l0aHVidXNlcmNvbnRlbnQuY29tMBIGCisGAQQBg78wAQIE
BHB1c2gwNgYKKwYBBAGDvzABAwQoM2E1N2E3NDFiZmI5ZjdjM2JjYTY5YjYzZTE3MGZjMjhlOTQz
MmU2OTAVBgorBgEEAYO/MAEEBAdSZWxlYXNlMCIGCisGAQQBg78wAQUEFHNpZ3N0b3JlL3NpZ3N0
b3JlLWpzMB0GCisGAQQBg78wAQYED3JlZnMvaGVhZHMvbWFpbjA7BgorBgEEAYO/MAEIBC0MK2h0
dHBzOi8vdG9rZW4uYWN0aW9ucy5naXRodWJ1c2VyY29udGVudC5jb20wZQYKKwYBBAGDvzABCQRX
DFVodHRwczovL2dpdGh1Yi5jb20vc2lnc3RvcmUvc2lnc3RvcmUtanMvLmdpdGh1Yi93b3JrZmxv
d3MvcmVsZWFzZS55bWxAcmVmcy9oZWFkcy9tYWluMDgGCisGAQQBg78wAQoEKgwoM2E1N2E3NDFi
ZmI5ZjdjM2JjYTY5YjYzZTE3MGZjMjhlOTQzMmU2OTAdBgorBgEEAYO/MAELBA8MDWdpdGh1Yi1o
b3N0ZWQwNwYKKwYBBAGDvzABDAQpDCdodHRwczovL2dpdGh1Yi5jb20vc2lnc3RvcmUvc2lnc3Rv
cmUtanMwOAYKKwYBBAGDvzABDQQqDCgzYTU3YTc0MWJmYjlmN2MzYmNhNjliNjNlMTcwZmMyOGU5
NDMyZTY5MB8GCisGAQQBg78wAQ4EEQwPcmVmcy9oZWFkcy9tYWluMBkGCisGAQQBg78wAQ8ECwwJ
NDk1NTc0NTU1MCsGCisGAQQBg78wARAEHQwbaHR0cHM6Ly9naXRodWIuY29tL3NpZ3N0b3JlMBgG
CisGAQQBg78wAREECgwINzEwOTYzNTMwZQYKKwYBBAGDvzABEgRXDFVodHRwczovL2dpdGh1Yi5j
b20vc2lnc3RvcmUvc2lnc3RvcmUtanMvLmdpdGh1Yi93b3JrZmxvd3MvcmVsZWFzZS55bWxAcmVm
cy9oZWFkcy9tYWluMDgGCisGAQQBg78wARMEKgwoM2E1N2E3NDFiZmI5ZjdjM2JjYTY5YjYzZTE3
MGZjMjhlOTQzMmU2OTAUBgorBgEEAYO/MAEUBAYMBHB1c2gwWwYKKwYBBAGDvzABFQRNDEtodHRw
czovL2dpdGh1Yi5jb20vc2lnc3RvcmUvc2lnc3RvcmUtanMvYWN0aW9ucy9ydW5zLzExMzMxMjkw
Mzg3L2F0dGVtcHRzLzEwFgYKKwYBBAGDvzABFgQIDAZwdWJsaWMwgYkGCisGAQQB1nkCBAIEewR5
AHcAdQDdPTBqxscRMmMZHhyZZzcCokpeuN48rf+HinKALynujgAAAZKLzphoAAAEAwBGMEQCIHQ9
LL9LECgBdY6bClnXOGR7hznz7bzwEz0gPvFmanWuAiBeeN3h0wium7ANLgDTBsFqY/df2Op54BC9
EAtias1ZJjAKBggqhkjOPQQDAwNoADBlAjEA2bLa8wNOQQ43ANDZOFJ85DDyn4DaFWQFjoWlQP3R
FIYQ9WDD4a5km9mVxQ9og82+AjApsAV76yLFvmDXHiOHNptbeDageiM1/nWekZZJj1Cix43RclqC
Nu0Q4+fNKeqlrnU=
CERT
cat >"$WORK/real-3.1.0.b64" <<'CERT'
MIIGtTCCBjugAwIBAgIUN5/v7FqchUyUo5Nb+G9zfECOsAcwCgYIKoZIzj0EAwMwNzEVMBMGA1UE
ChMMc2lnc3RvcmUuZGV2MR4wHAYDVQQDExVzaWdzdG9yZS1pbnRlcm1lZGlhdGUwHhcNMjUwMjA0
MjAzNTQ3WhcNMjUwMjA0MjA0NTQ3WjAAMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEfBAonJlS
eH6t8S7LaYyGyJLIAeCdf2e1IjbOHBLoZTytrGL7dVCBdzLEWZa22cjYbihgfE57lIn9zW90Gy3m
7KOCBVowggVWMA4GA1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggrBgEFBQcDAzAdBgNVHQ4EFgQU
mFmCQoyAACh9xjpWTS5e3Rne2a0wHwYDVR0jBBgwFoAU39Ppz1YkEZb5qNjpKFWixi4YZD8wYwYD
VR0RAQH/BFkwV4ZVaHR0cHM6Ly9naXRodWIuY29tL3NpZ3N0b3JlL3NpZ3N0b3JlLWpzLy5naXRo
dWIvd29ya2Zsb3dzL3JlbGVhc2UueW1sQHJlZnMvaGVhZHMvbWFpbjA5BgorBgEEAYO/MAEBBCto
dHRwczovL3Rva2VuLmFjdGlvbnMuZ2l0aHVidXNlcmNvbnRlbnQuY29tMBIGCisGAQQBg78wAQIE
BHB1c2gwNgYKKwYBBAGDvzABAwQoMDZjZDI2N2NiZGMyZWVhYTA0Mjk0OTk1NjIyZGI5ZjZhZDJm
YTdjZjAVBgorBgEEAYO/MAEEBAdSZWxlYXNlMCIGCisGAQQBg78wAQUEFHNpZ3N0b3JlL3NpZ3N0
b3JlLWpzMB0GCisGAQQBg78wAQYED3JlZnMvaGVhZHMvbWFpbjA7BgorBgEEAYO/MAEIBC0MK2h0
dHBzOi8vdG9rZW4uYWN0aW9ucy5naXRodWJ1c2VyY29udGVudC5jb20wZQYKKwYBBAGDvzABCQRX
DFVodHRwczovL2dpdGh1Yi5jb20vc2lnc3RvcmUvc2lnc3RvcmUtanMvLmdpdGh1Yi93b3JrZmxv
d3MvcmVsZWFzZS55bWxAcmVmcy9oZWFkcy9tYWluMDgGCisGAQQBg78wAQoEKgwoMDZjZDI2N2Ni
ZGMyZWVhYTA0Mjk0OTk1NjIyZGI5ZjZhZDJmYTdjZjAdBgorBgEEAYO/MAELBA8MDWdpdGh1Yi1o
b3N0ZWQwNwYKKwYBBAGDvzABDAQpDCdodHRwczovL2dpdGh1Yi5jb20vc2lnc3RvcmUvc2lnc3Rv
cmUtanMwOAYKKwYBBAGDvzABDQQqDCgwNmNkMjY3Y2JkYzJlZWFhMDQyOTQ5OTU2MjJkYjlmNmFk
MmZhN2NmMB8GCisGAQQBg78wAQ4EEQwPcmVmcy9oZWFkcy9tYWluMBkGCisGAQQBg78wAQ8ECwwJ
NDk1NTc0NTU1MCsGCisGAQQBg78wARAEHQwbaHR0cHM6Ly9naXRodWIuY29tL3NpZ3N0b3JlMBgG
CisGAQQBg78wAREECgwINzEwOTYzNTMwZQYKKwYBBAGDvzABEgRXDFVodHRwczovL2dpdGh1Yi5j
b20vc2lnc3RvcmUvc2lnc3RvcmUtanMvLmdpdGh1Yi93b3JrZmxvd3MvcmVsZWFzZS55bWxAcmVm
cy9oZWFkcy9tYWluMDgGCisGAQQBg78wARMEKgwoMDZjZDI2N2NiZGMyZWVhYTA0Mjk0OTk1NjIy
ZGI5ZjZhZDJmYTdjZjAUBgorBgEEAYO/MAEUBAYMBHB1c2gwWwYKKwYBBAGDvzABFQRNDEtodHRw
czovL2dpdGh1Yi5jb20vc2lnc3RvcmUvc2lnc3RvcmUtanMvYWN0aW9ucy9ydW5zLzEzMTQ0MzU3
Njg0L2F0dGVtcHRzLzEwFgYKKwYBBAGDvzABFgQIDAZwdWJsaWMwgYkGCisGAQQB1nkCBAIEewR5
AHcAdQDdPTBqxscRMmMZHhyZZzcCokpeuN48rf+HinKALynujgAAAZTSrRlwAAAEAwBGMEQCIG6z
SGVykpyfLV+DYSfTYdd83d0jGeJADXoKc0SuZ3CsAiBoa8ERFDEIsg799ZgYT6frfjA7RUnGBsL1
vBPYrLoK3TAKBggqhkjOPQQDAwNoADBlAjEA5zy+m61vFvP4s8kJTTZlLAEqd5TOeD9jb2b4WIcZ
usvIuBBlkmm26XAKD434joK0AjAub9Ly1MgsVb9ytqYuaM4FopYnNs5v7kf4jOOE+CNitiXwyv/x
ALYCYPkEASI621Q=
CERT


# --- 2026-11-02 に取った org.postgresql:postgresql 42.7.13 と 42.7.14 の .pom と .pom.asc と公開鍵 ---
# Maven Central と keyserver.ubuntu.com から1回ずつ取った、そのままのファイルである。
# 2つの署名には発行者の指紋が無く、発行者の鍵 ID 305F296EAC47556B だけがある。
# 公開鍵は、その鍵 ID で keyserver.ubuntu.com の search=0x305F296EAC47556B から取った。
mkdir -p "$WORK/real-pg"
cat >"$WORK/real-pg/postgresql-42.7.13.pom" <<'REAL'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0" xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <modelVersion>4.0.0</modelVersion>
  <groupId>org.postgresql</groupId>
  <artifactId>postgresql</artifactId>
  <version>42.7.13</version>
  <name>PostgreSQL JDBC Driver</name>
  <description>PostgreSQL JDBC Driver Postgresql</description>
  <url>https://jdbc.postgresql.org</url>
  <inceptionYear>1997</inceptionYear>
  <organization>
    <name>PostgreSQL Global Development Group</name>
    <url>https://jdbc.postgresql.org/</url>
  </organization>
  <licenses>
    <license>
      <name>BSD-2-Clause</name>
      <url>https://jdbc.postgresql.org/about/license.html</url>
      <distribution>repo</distribution>
      <comments>BSD-2-Clause, copyright PostgreSQL Global Development Group</comments>
    </license>
  </licenses>
  <developers>
    <developer>
      <id>davecramer</id>
      <name>Dave Cramer</name>
    </developer>
    <developer>
      <id>jurka</id>
      <name>Kris Jurka</name>
    </developer>
    <developer>
      <id>oliver</id>
      <name>Oliver Jowett</name>
    </developer>
    <developer>
      <id>ringerc</id>
      <name>Craig Ringer</name>
    </developer>
    <developer>
      <id>vlsi</id>
      <name>Vladimir Sitnikov</name>
    </developer>
    <developer>
      <id>bokken</id>
      <name>Brett Okken</name>
    </developer>
    <developer>
      <id>sehrope</id>
      <name>Sehrope Sarkuni</name>
    </developer>
  </developers>
  <mailingLists>
    <mailingList>
      <name>PostgreSQL JDBC development list</name>
      <subscribe>https://lists.postgresql.org/</subscribe>
      <unsubscribe>https://lists.postgresql.org/unsubscribe/</unsubscribe>
      <post>pgsql-jdbc@postgresql.org</post>
      <archive>https://www.postgresql.org/list/pgsql-jdbc/</archive>
    </mailingList>
  </mailingLists>
  <scm>
    <connection>scm:git:https://github.com/pgjdbc/pgjdbc.git</connection>
    <developerConnection>scm:git:https://github.com/pgjdbc/pgjdbc.git</developerConnection>
    <url>https://github.com/pgjdbc/pgjdbc</url>
  </scm>
  <issueManagement>
    <system>GitHub issues</system>
    <url>https://github.com/pgjdbc/pgjdbc/issues</url>
  </issueManagement>
  <dependencies>
    <dependency>
      <groupId>org.checkerframework</groupId>
      <artifactId>checker-qual</artifactId>
      <version>3.55.1</version>
      <scope>runtime</scope>
    </dependency>
    <dependency>
      <groupId>com.github.waffle</groupId>
      <artifactId>waffle-jna</artifactId>
      <version>1.9.1</version>
      <scope>runtime</scope>
      <optional>true</optional>
    </dependency>
  </dependencies>
</project>
REAL
cat >"$WORK/real-pg/postgresql-42.7.13.pom.asc" <<'REAL'
-----BEGIN PGP SIGNATURE-----

wsFcBAABCgAGBYJqS/0qAAoJEDBfKW6sR1Vrcq4P+QG4AtX93f/xYLQ9imZgKqgO
b+UxHMN5UR3J7J2DrjoCLeGMUILVUdocLQkUTW1CMwx7oGatyjRf6AbtKOHee9/C
DyC+eQboblWYW9h1+ICFZFLQZx+SfiQfXEEsB6SU2/rgvEFWtzz2srORKF5D8X0/
/fPXYz+ExU5kQHCEYwX6GJHTwBNu0lMPEzNiXFH5W/7nB2qh7xDtMn9p8JaswzSp
SHQ/nKGRaQvhOxIbwMy3BYbLSXtcf/712ZBBywesUS13WEktz5JuY+xbi3XBuAnu
3O0gGqt9YRFTdfx6fFzv06Tll+mG8yNZvihtiRFnmnuLIPAXRUDTXXK/umAmkWgR
SvhGtTvw5X4grxxVRJHr9JbJCYLL30mxjbyMmu3h8dQJqtCv3zwg7+V5IvFD7RgT
m0StAwoWAGz/yayCgCfep6IVX5GwT4rp64ZzDZ0gaizUAZAVUDXOm4Nj5MsSu4Q6
z9mWHgg7Xv1wGlh+QiAhfBw1kOHbWwT2+kGFja86w3apOTXpGGSqw+9ZE9l+yl4C
6RhP0YsVkGk4GG2KU7n0WFpdVTMEZcMd8aeprjzm7HZ22axm1PYuEdup8UW8EeIX
GvLmkbp75kqCifdZW5HRUmElRgzzgSM3BntFbXREP733W+VpPnQUzS4oRazzT5RY
Bf3JFc+9o3i3bpOmOBdY
=W6d3
-----END PGP SIGNATURE-----
REAL
cat >"$WORK/real-pg/postgresql-42.7.14.pom" <<'REAL'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0" xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <modelVersion>4.0.0</modelVersion>
  <groupId>org.postgresql</groupId>
  <artifactId>postgresql</artifactId>
  <version>42.7.14</version>
  <name>PostgreSQL JDBC Driver</name>
  <description>PostgreSQL JDBC Driver Postgresql</description>
  <url>https://jdbc.postgresql.org</url>
  <inceptionYear>1997</inceptionYear>
  <organization>
    <name>PostgreSQL Global Development Group</name>
    <url>https://jdbc.postgresql.org/</url>
  </organization>
  <licenses>
    <license>
      <name>BSD-2-Clause</name>
      <url>https://jdbc.postgresql.org/about/license.html</url>
      <distribution>repo</distribution>
      <comments>BSD-2-Clause, copyright PostgreSQL Global Development Group</comments>
    </license>
  </licenses>
  <developers>
    <developer>
      <id>davecramer</id>
      <name>Dave Cramer</name>
    </developer>
    <developer>
      <id>jurka</id>
      <name>Kris Jurka</name>
    </developer>
    <developer>
      <id>oliver</id>
      <name>Oliver Jowett</name>
    </developer>
    <developer>
      <id>ringerc</id>
      <name>Craig Ringer</name>
    </developer>
    <developer>
      <id>vlsi</id>
      <name>Vladimir Sitnikov</name>
    </developer>
    <developer>
      <id>bokken</id>
      <name>Brett Okken</name>
    </developer>
    <developer>
      <id>sehrope</id>
      <name>Sehrope Sarkuni</name>
    </developer>
  </developers>
  <mailingLists>
    <mailingList>
      <name>PostgreSQL JDBC development list</name>
      <subscribe>https://lists.postgresql.org/</subscribe>
      <unsubscribe>https://lists.postgresql.org/unsubscribe/</unsubscribe>
      <post>pgsql-jdbc@postgresql.org</post>
      <archive>https://www.postgresql.org/list/pgsql-jdbc/</archive>
    </mailingList>
  </mailingLists>
  <scm>
    <connection>scm:git:https://github.com/pgjdbc/pgjdbc.git</connection>
    <developerConnection>scm:git:https://github.com/pgjdbc/pgjdbc.git</developerConnection>
    <url>https://github.com/pgjdbc/pgjdbc</url>
  </scm>
  <issueManagement>
    <system>GitHub issues</system>
    <url>https://github.com/pgjdbc/pgjdbc/issues</url>
  </issueManagement>
  <dependencies>
    <dependency>
      <groupId>org.checkerframework</groupId>
      <artifactId>checker-qual</artifactId>
      <version>3.55.1</version>
      <scope>runtime</scope>
    </dependency>
    <dependency>
      <groupId>com.github.waffle</groupId>
      <artifactId>waffle-jna</artifactId>
      <version>1.9.1</version>
      <scope>runtime</scope>
      <optional>true</optional>
    </dependency>
  </dependencies>
</project>
REAL
cat >"$WORK/real-pg/postgresql-42.7.14.pom.asc" <<'REAL'
-----BEGIN PGP SIGNATURE-----

wsFcBAABCgAGBYJqxrwnAAoJEDBfKW6sR1VrFsIQALeLfxIn7Rk1tWGD30a+69fL
xpAM5o34riI2joVz5AxjJXchouGdyO3r/EhDNQEYXP/cXvDp5Ub4XEkP8Lut594l
bHy7fGLQfrlgTtRGBAXGvKOSufVZdje3aplhnU9SasOclvyO0B2L0vY8NHPyU7ob
OkmDhoCo5yLTICbfoakimTRrMoOAo+X++uQbyPlUmhIY516YZXGehZuIk+py6JZc
Ks2logOddbV2RuH4+V0E+yhvAbF9l1BtNtN5MHq5TnRVsAMP20oRybP9ObizvWOp
oxlrJDjtM74kYWzC0/gDfQAGlSi8HuDGe9rJrL5gnE5faTLVYc80A1UQTBqUDlwW
HBlzLTyQevWxQLFRuP/RR2qY7qRePtPGJJ33h6IkkEVLZQaXAWcEOry1XxQ+q22R
pUbMBvcPzfZ5SGADm58O9hQ73f6GgJ8K+nn3F2seGM5iiECd5626p0kX+qgCge42
zlLtSGt/kcvJpvdlZUSHvgvJkYb4Z/pi3KAP7oAjC+e+guX7sVUH7ChS/zskcoOg
zu0BrR3tJy06Lzbbws33LBqNGfg0mNtcNnAhUuLqK8uqK5RxcWFSmh40924V/dl9
EeM8TVONGUR/VNAWk0BkgPKMwonuiqTlQqSCodHwukNUi6RDKpbzjIsglaJWQ8Ku
FO8hNOT6rPJtTB1Q00Xu
=M0f0
-----END PGP SIGNATURE-----
REAL
cat >"$WORK/real-pg/key-305F296EAC47556B.asc" <<'REAL'
-----BEGIN PGP PUBLIC KEY BLOCK-----
Comment: Hostname: 
Version: Hockeypuck 2.2

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
+IY=
=KftP
-----END PGP PUBLIC KEY BLOCK-----
REAL

# --- 材料を作る -----------------------------------------------------------------------
openssl ecparam -name prime256v1 -genkey -noout -out "$WORK/key.pem" 2>/dev/null || exit 1

ISS="https://token.actions.githubusercontent.com"
WF="https://github.com/acme/widget/.github/workflows/release.yml"
REPO_URI="https://github.com/acme/widget"

# 使い方: mkcert <OIDC の発行元> <元のリポジトリの ID> <組み立ての設定の URI> <元のリポジトリの URI>
# 来歴の証明書と同じ OID の拡張を持つ証明書を作り、DER の base64 を1行で出す
mkcert() {
    openssl req -x509 -new -key "$WORK/key.pem" -subj "/CN=test" -days 1 -outform DER \
        -addext "1.3.6.1.4.1.57264.1.8=ASN1:UTF8String:$1" \
        -addext "1.3.6.1.4.1.57264.1.15=ASN1:UTF8String:$2" \
        -addext "1.3.6.1.4.1.57264.1.18=ASN1:UTF8String:$3" \
        -addext "1.3.6.1.4.1.57264.1.12=ASN1:UTF8String:$4" \
        -out "$WORK/c.der" 2>/dev/null || return 1
    base64 -w0 "$WORK/c.der"
}

# 使い方: att <名前> <版> <証明書の base64(空なら SLSA の来歴を付けない)> [v03]
# publish attestation はいつも付ける。v03 なら証明書を verificationMaterial.certificate に置く
att() {
    local key
    key=$(printf '%s@%s' "$1" "$2" | tr '/' '_')
    jq -n --arg cert "$3" --arg fmt "${4:-v02}" '{attestations: ([{
        predicateType: "https://github.com/npm/attestation/tree/main/specs/publish/v0.1",
        bundle: {mediaType: "application/vnd.dev.sigstore.bundle+json;version=0.2",
            verificationMaterial: {publicKey: {hint: "SHA256:jl3bwswu80PjjokCgh0o2w5c2U4LhQAE57gj9cz1kzA"},
                tlogEntries: []},
            dsseEnvelope: {payload: "e30=", payloadType: "application/vnd.in-toto+json", signatures: []}}}]
      + (if $cert == "" then [] else [{
        predicateType: "https://slsa.dev/provenance/v1",
        bundle: ({dsseEnvelope: {payload: "e30=", payloadType: "application/vnd.in-toto+json", signatures: []}}
          + if $fmt == "v03" then {mediaType: "application/vnd.dev.sigstore.bundle.v0.3+json",
                verificationMaterial: {certificate: {rawBytes: $cert}, tlogEntries: []}}
            else {mediaType: "application/vnd.dev.sigstore.bundle+json;version=0.2",
                verificationMaterial: {x509CertificateChain: {certificates: [{rawBytes: $cert}]},
                    tlogEntries: [], timestampVerificationData: {}}} end)}] end))}' \
        >"$STUB/att/$key"
}

# 使い方: pkg <名前> <版>。tgz と、dist.tarball と dist.integrity と registry の署名を持つ部品の文書を作る
pkg() {
    local base="${1##*/}" doc
    doc="$STUB/doc/${1//\//%2f}"
    printf 'contents of %s@%s\n' "$1" "$2" | gzip -c >"$STUB/tgz/${base}-$2.tgz"
    [ -f "$doc" ] || echo '{"versions":{}}' >"$doc"
    jq --arg v "$2" --arg t "${NPM}/$1/-/${base}-$2.tgz" \
        --arg i "sha512-$(openssl dgst -sha512 -binary "$STUB/tgz/${base}-$2.tgz" | base64 -w0)" \
        '.versions[$v] = {dist: {tarball: $t, integrity: $i,
            signatures: [{keyid: "SHA256:jl3bwswu80PjjokCgh0o2w5c2U4LhQAE57gj9cz1kzA", sig: "MEUCIQ=="}]}}' \
        "$doc" >"$doc.new" && mv "$doc.new" "$doc"
}

# --- maven の材料 -----------------------------------------------------------------------
# 使い捨ての鍵を作る家。Acme の主鍵には署名に使う副鍵を2つ付け、Other は別の公開元の鍵にする
MAKER="$WORK/gpg-maker"
mkdir -m 700 "$MAKER"
gpgm() { gpg --batch --homedir "$MAKER" --pinentry-mode loopback --passphrase '' "$@"; }
gpgm --quick-gen-key "Acme <acme@example.invalid>" ed25519 sign never 2>/dev/null || exit 1
gpgm --quick-gen-key "Other <other@example.invalid>" ed25519 sign never 2>/dev/null || exit 1
fpr_of() { gpgm --list-keys --with-colons "$1" 2>/dev/null | awk -F: '/^fpr/ { print $10; exit }'; }
FA=$(fpr_of acme@example.invalid)
FB=$(fpr_of other@example.invalid)
gpgm --quick-add-key "$FA" ed25519 sign never 2>/dev/null || exit 1
gpgm --quick-add-key "$FA" ed25519 sign never 2>/dev/null || exit 1
mapfile -t SUBS < <(gpgm --list-keys --with-colons "$FA" 2>/dev/null |
    awk -F: '/^sub/ { s = 1; next } s && /^fpr/ { print $10; s = 0 }')
SA1="${SUBS[0]:-}"
SA2="${SUBS[1]:-}"
[ -n "$FA" ] && [ -n "$FB" ] && [ -n "$SA1" ] && [ -n "$SA2" ] || exit 1

# 使い方: mvn_put <central|portal> <group:artifact> <版> [署名に使う鍵の指紋]
# .pom を置き、鍵の指紋があれば、その鍵(主鍵か副鍵)で .pom.asc を作って置く
mvn_put() {
    local g="${2%%:*}" a="${2#*:}" dir
    dir="$STUB/$1/${g//.//}/$a/$3"
    mkdir -p "$dir"
    printf '<project><groupId>%s</groupId><artifactId>%s</artifactId><version>%s</version></project>\n' \
        "$g" "$a" "$3" >"$dir/$a-$3.pom"
    if [ -n "${4:-}" ]; then
        gpgm -u "$4!" --armor --detach-sign -o "$dir/$a-$3.pom.asc" "$dir/$a-$3.pom" 2>/dev/null || exit 1
    fi
}

# 使い方: publish_key <主鍵の指紋> <search に使われる指紋か鍵 ID>...
# 鍵サーバの答えとして、その主鍵の公開鍵を、search の値ごとに置く
publish_key() {
    local primary="$1" s
    shift
    for s in "$@"; do gpgm --armor --export "$primary" >"$STUB/keys/$s" 2>/dev/null; done
}

reset() {
    rm -rf "${STUB:?}"/att/* "$STUB"/doc/* "$STUB"/tgz/* "$STUB/gh.fail" "$STUB/gh-bundle.json" \
        "$STUB"/central/* "$STUB"/portal/* "$STUB"/keys/*
    : >"$WORK/calls.log"
}

# 使い方: run <ecosystem> <名前> <前の版> <新しい版>。出力を $WORK/out.txt に、終了コードを $RC に入れる
run() {
    PATH="$WORK/bin:$PATH" STUB_DIR="$STUB" STUB_NPM="$NPM" STUB_CALLS="$WORK/calls.log" \
        STUB_CENTRAL="$CENTRAL" STUB_PORTAL="$PORTAL" STUB_KEYS="$KEYS" \
        NPM_REGISTRY_BASE="$NPM" MAVEN_CENTRAL_BASE="$CENTRAL" PLUGIN_PORTAL_BASE="$PORTAL" KEYSERVER_BASE="$KEYS" \
        bash "$SCRIPT" "$@" >"$WORK/out.txt" 2>"$WORK/err.log"
    RC=$?
}

pass() { echo "PASS: $1"; }
fail() {
    echo "FAIL: $1 ($2)"
    FAILED=1
}

# 使い方: expect_result <説明> <結果>。1行目が result=<結果>、2行目が空でない detail= で、終了コードが 0
expect_result() {
    local first second
    first=$(sed -n 1p "$WORK/out.txt")
    second=$(sed -n 2p "$WORK/out.txt")
    if [ "$RC" -eq 0 ] && [ "$first" = "result=$2" ] && [ "${second#detail=}" != "$second" ] &&
        [ -n "${second#detail=}" ]; then
        pass "$1"
    else
        fail "$1" "終了コード ${RC} / 出力: $(head -c 500 "$WORK/out.txt") / 標準エラー: $(head -c 300 "$WORK/err.log")"
    fi
}

# 使い方: expect_calls <説明> <grep の式> <回数>。スタブの記録に当たる行の数を比べる
expect_calls() {
    local n
    n=$(grep -c -- "$2" "$WORK/calls.log")
    if [ "$n" -eq "$3" ]; then pass "$1"; else fail "$1" "「$2」が ${n} 回(期待は $3 回)"; fi
}

expect_rc() {
    if [ "$RC" -eq "$2" ]; then pass "$1"; else fail "$1" "expected exit $2, got $RC"; fi
}

RAN=0
want() {
    if [ -z "$CASE" ] || [ "$CASE" = "$1" ]; then
        RAN=$((RAN + 1))
        return 0
    fi
    return 1
}

# --- 場合 ------------------------------------------------------------------------

if want real_same; then
    reset
    att sigstore 3.0.0 "$(tr -d '\n' <"$WORK/real-3.0.0.b64")"
    att sigstore 3.1.0 "$(tr -d '\n' <"$WORK/real-3.1.0.b64")"
    pkg sigstore 3.1.0
    run npm sigstore 3.0.0 3.1.0
    expect_result "3つの欄が同じなら same になる" same
    expect_calls "3つの欄が同じなら same になる(新しい版の来歴を、前の版の元のリポジトリで sha512 として検証する)" \
        "^GH attestation verify .*/pkg.tgz --bundle .* --digest-alg sha512 --repo sigstore/sigstore-js$" 1
    if jq -e --slurpfile a "$STUB/att/sigstore@3.1.0" \
        '. == ($a[0].attestations[] | select(.predicateType == "https://slsa.dev/provenance/v1") | .bundle)' \
        "$STUB/gh-bundle.json" >/dev/null 2>&1; then
        pass "3つの欄が同じなら same になる(検証に渡す bundle は新しい版の SLSA の来歴)"
    else
        fail "3つの欄が同じなら same になる(検証に渡す bundle は新しい版の SLSA の来歴)" "$(head -c 300 "$STUB/gh-bundle.json")"
    fi
    expect_calls "3つの欄が同じなら same になる(来歴と文書の打ち切りは60秒)" \
        "^GET ${NPM}/-/npm/v1/attestations/sigstore@3\.[01]\.0 max-time=60$" 2
    expect_calls "3つの欄が同じなら same になる(tgz の打ち切りは300秒)" \
        "^GET ${NPM}/sigstore/-/sigstore-3\.1\.0\.tgz max-time=300$" 1
fi

if want different_repo_id; then
    reset
    att widget 1.0.0 "$(mkcert "$ISS" 1001 "$WF@refs/tags/v1.0.0" "$REPO_URI")"
    att widget 1.1.0 "$(mkcert "$ISS" 1002 "$WF@refs/tags/v1.0.0" "$REPO_URI")"
    pkg widget 1.1.0
    run npm widget 1.0.0 1.1.0
    expect_result "元のリポジトリの ID が違えば different になる" different
    expect_calls "元のリポジトリの ID が違えば different になる(検証も tgz の取得もしない)" '^GH \|\.tgz ' 0
    reset
    att widget 1.0.0 "$(mkcert "$ISS" 1001 "$WF@refs/tags/v1.0.0" "$REPO_URI")"
    att widget 1.1.0 "$(mkcert "$ISS" 1001 "https://github.com/acme/widget/.github/workflows/other.yml@refs/tags/v1.0.0" "$REPO_URI")"
    pkg widget 1.1.0
    run npm widget 1.0.0 1.1.0
    expect_result "組み立ての設定の URI の @ より前が違えば different になる" different
    reset
    att widget 1.0.0 "$(mkcert "$ISS" 1001 "$WF@refs/tags/v1.0.0" "$REPO_URI")"
    att widget 1.1.0 "$(mkcert "https://gitlab.com" 1001 "$WF@refs/tags/v1.0.0" "$REPO_URI")"
    pkg widget 1.1.0
    run npm widget 1.0.0 1.1.0
    expect_result "OIDC の発行元が違えば different になる" different
fi

if want ref_only; then
    reset
    # スコープ付きの名前と、証明書を verificationMaterial.certificate に置く bundle の版 0.3
    att @acme/widget 1.0.0 "$(mkcert "$ISS" 1001 "$WF@refs/tags/v1.0.0" "$REPO_URI")" v03
    att @acme/widget 1.1.0 "$(mkcert "$ISS" 1001 "$WF@refs/tags/v1.1.0" "$REPO_URI")" v03
    pkg @acme/widget 1.1.0
    run npm @acme/widget 1.0.0 1.1.0
    expect_result "組み立ての設定の URI の @ より後ろだけが違えば same になる" same
    expect_calls "組み立ての設定の URI の @ より後ろだけが違えば same になる(スコープ付きの名前の文書は %2f で読む)" \
        "^GET ${NPM}/@acme%2fwidget max-time=60$" 1
    expect_calls "組み立ての設定の URI の @ より後ろだけが違えば same になる(--repo は前の版の元のリポジトリ)" \
        " --repo acme/widget$" 1
fi

if want no_new_signature; then
    reset
    att widget 1.0.0 "$(mkcert "$ISS" 1001 "$WF@refs/tags/v1.0.0" "$REPO_URI")"
    pkg widget 1.1.0
    run npm widget 1.0.0 1.1.0
    expect_result "前の版に来歴があり新しい版に無ければ no-new-signature になる" no-new-signature
    expect_calls "前の版に来歴があり新しい版に無ければ no-new-signature になる(404 は再試行しない)" \
        "attestations/widget@1\.1\.0 " 1
fi

if want registry_only; then
    reset
    # 新しい版には、registry の署名(部品の文書の dist.signatures)と publish attestation だけがある
    att widget 1.0.0 "$(mkcert "$ISS" 1001 "$WF@refs/tags/v1.0.0" "$REPO_URI")"
    att widget 1.1.0 ""
    pkg widget 1.1.0
    run npm widget 1.0.0 1.1.0
    expect_result "registry の署名と publish attestation だけがある版は、署名が無いものとして扱う(新しい版)" no-new-signature
    reset
    att widget 1.0.0 ""
    att widget 1.1.0 "$(mkcert "$ISS" 1001 "$WF@refs/tags/v1.1.0" "$REPO_URI")"
    pkg widget 1.0.0
    pkg widget 1.1.0
    run npm widget 1.0.0 1.1.0
    expect_result "registry の署名と publish attestation だけがある版は、署名が無いものとして扱う(前の版)" no-prior-signature
fi

if want no_prior_signature; then
    reset
    att widget 1.1.0 "$(mkcert "$ISS" 1001 "$WF@refs/tags/v1.1.0" "$REPO_URI")"
    pkg widget 1.1.0
    run npm widget 1.0.0 1.1.0
    expect_result "前の版に来歴が無ければ no-prior-signature になる" no-prior-signature
fi

if want gh_fail; then
    reset
    att widget 1.0.0 "$(mkcert "$ISS" 1001 "$WF@refs/tags/v1.0.0" "$REPO_URI")"
    att widget 1.1.0 "$(mkcert "$ISS" 1001 "$WF@refs/tags/v1.1.0" "$REPO_URI")"
    pkg widget 1.1.0
    : >"$STUB/gh.fail"
    run npm widget 1.0.0 1.1.0
    expect_result "gh attestation verify が失敗したら unknown になる" unknown
    expect_calls "gh attestation verify が失敗したら unknown になる(再試行は1回)" '^GH attestation verify ' 2
fi

if want att_fail; then
    reset
    att widget 1.0.0 "$(mkcert "$ISS" 1001 "$WF@refs/tags/v1.0.0" "$REPO_URI")"
    att widget 1.1.0 "$(mkcert "$ISS" 1001 "$WF@refs/tags/v1.1.0" "$REPO_URI")"
    pkg widget 1.1.0
    : >"$STUB/att/widget@1.1.0.fail"
    run npm widget 1.0.0 1.1.0
    expect_result "来歴の取得が失敗したら unknown になる(新しい版)" unknown
    expect_calls "来歴の取得が失敗したら unknown になる(再試行は1回)" "attestations/widget@1\.1\.0 " 2
    rm -f "$STUB/att/widget@1.1.0.fail"
    : >"$STUB/att/widget@1.0.0.fail"
    run npm widget 1.0.0 1.1.0
    expect_result "来歴の取得が失敗したら unknown になる(前の版)" unknown
    rm -f "$STUB/att/widget@1.0.0.fail"
    : >"$STUB/tgz/widget-1.1.0.tgz.fail"
    run npm widget 1.0.0 1.1.0
    expect_result "来歴の取得が失敗したら unknown になる(tgz)" unknown
fi

if want retry; then
    reset
    att widget 1.0.0 "$(mkcert "$ISS" 1001 "$WF@refs/tags/v1.0.0" "$REPO_URI")"
    att widget 1.1.0 "$(mkcert "$ISS" 1001 "$WF@refs/tags/v1.1.0" "$REPO_URI")"
    pkg widget 1.1.0
    : >"$STUB/att/widget@1.1.0.fail-once"
    : >"$STUB/doc/widget.fail-once"
    run npm widget 1.0.0 1.1.0
    expect_result "1回目の取得が失敗しても、再試行で取れれば判定する" same
fi

if want integrity_mismatch; then
    reset
    att widget 1.0.0 "$(mkcert "$ISS" 1001 "$WF@refs/tags/v1.0.0" "$REPO_URI")"
    att widget 1.1.0 "$(mkcert "$ISS" 1001 "$WF@refs/tags/v1.1.0" "$REPO_URI")"
    pkg widget 1.1.0
    printf 'tampered\n' | gzip -c >"$STUB/tgz/widget-1.1.0.tgz"
    run npm widget 1.0.0 1.1.0
    expect_result "tgz が dist.integrity と合わなければ unknown になる" unknown
    expect_calls "tgz が dist.integrity と合わなければ unknown になる(検証に進まない)" '^GH ' 0
fi

if want bad_cert; then
    reset
    att widget 1.0.0 "$(mkcert "$ISS" 1001 "$WF@refs/tags/v1.0.0" "$REPO_URI")"
    att widget 1.1.0 "bm90IGEgY2VydGlmaWNhdGU="
    pkg widget 1.1.0
    run npm widget 1.0.0 1.1.0
    expect_result "来歴の証明書を読めなければ unknown になる" unknown
fi

if want bad_prev_cert; then
    reset
    att widget 1.0.0 "bm90IGEgY2VydGlmaWNhdGU="
    att widget 1.1.0 "$(mkcert "$ISS" 1001 "$WF@refs/tags/v1.1.0" "$REPO_URI")"
    pkg widget 1.1.0
    run npm widget 1.0.0 1.1.0
    expect_result "前の版の来歴の証明書を読めなければ unknown になる" unknown
    expect_calls "前の版の来歴の証明書を読めなければ unknown になる(検証も tgz の取得もしない)" '^GH \|\.tgz ' 0
fi

if want doc_fail; then
    reset
    att widget 1.0.0 "$(mkcert "$ISS" 1001 "$WF@refs/tags/v1.0.0" "$REPO_URI")"
    att widget 1.1.0 "$(mkcert "$ISS" 1001 "$WF@refs/tags/v1.1.0" "$REPO_URI")"
    pkg widget 1.1.0
    : >"$STUB/doc/widget.fail"
    run npm widget 1.0.0 1.1.0
    expect_result "部品の文書を読めなければ unknown になる" unknown
    expect_calls "部品の文書を読めなければ unknown になる(再試行は1回)" "^GET ${NPM}/widget max-time=60$" 2
fi

if want no_tarball; then
    reset
    att widget 1.0.0 "$(mkcert "$ISS" 1001 "$WF@refs/tags/v1.0.0" "$REPO_URI")"
    att widget 1.1.0 "$(mkcert "$ISS" 1001 "$WF@refs/tags/v1.1.0" "$REPO_URI")"
    pkg widget 1.1.0
    jq 'del(.versions["1.1.0"].dist.tarball)' "$STUB/doc/widget" >"$STUB/doc/widget.new" && mv "$STUB/doc/widget.new" "$STUB/doc/widget"
    run npm widget 1.0.0 1.1.0
    expect_result "部品の文書に tgz の URL が無ければ unknown になる" unknown
    pkg widget 1.1.0
    jq '.versions["1.1.0"].dist.integrity = "sha1-AAAA"' "$STUB/doc/widget" >"$STUB/doc/widget.new" && mv "$STUB/doc/widget.new" "$STUB/doc/widget"
    run npm widget 1.0.0 1.1.0
    expect_result "部品の文書に sha512 の dist.integrity が無ければ unknown になる" unknown
    expect_calls "部品の文書に tgz の URL か sha512 の dist.integrity が無ければ unknown になる(検証に進まない)" '^GH ' 0
fi

# --- maven の場合 ---------------------------------------------------------------------

if want maven_same; then
    reset
    mvn_put central com.acme:widget 1.0.0 "$FA"
    mvn_put central com.acme:widget 1.1.0 "$FA"
    publish_key "$FA" "$FA"
    run maven com.acme:widget 1.0.0 1.1.0
    expect_result "主鍵の指紋が同じなら same になる" same
    expect_calls "主鍵の指紋が同じなら same になる(公開鍵を発行者の指紋で鍵サーバから取る)" \
        "^GET ${KEYS}/pks/lookup?op=get&options=mr&search=0x${FA} max-time=60$" 2
    expect_calls "主鍵の指紋が同じなら same になる(.pom と .pom.asc の打ち切りは60秒)" \
        "^GET ${CENTRAL}/com/acme/widget/1\.[01]\.0/widget-1\.[01]\.0\.pom\(\.asc\)\? max-time=60$" 4
fi

if want maven_different; then
    reset
    mvn_put central com.acme:widget 1.0.0 "$FA"
    mvn_put central com.acme:widget 1.1.0 "$FB"
    publish_key "$FA" "$FA"
    publish_key "$FB" "$FB"
    run maven com.acme:widget 1.0.0 1.1.0
    expect_result "主鍵の指紋が違えば different になる" different
fi

if want maven_subkey; then
    reset
    mvn_put central com.acme:widget 1.0.0 "$SA1"
    mvn_put central com.acme:widget 1.1.0 "$SA2"
    publish_key "$FA" "$SA1" "$SA2"
    run maven com.acme:widget 1.0.0 1.1.0
    expect_result "副鍵が替わっても主鍵が同じなら same になる" same
    expect_calls "副鍵が替わっても主鍵が同じなら same になる(公開鍵を署名した副鍵の指紋で取る)" \
        "search=0x\(${SA1}\|${SA2}\) " 2
fi

if want real_pg; then
    reset
    for v in 42.7.13 42.7.14; do
        mkdir -p "$STUB/central/org/postgresql/postgresql/$v"
        cp "$WORK/real-pg/postgresql-$v.pom" "$WORK/real-pg/postgresql-$v.pom.asc" \
            "$STUB/central/org/postgresql/postgresql/$v/"
    done
    cp "$WORK/real-pg/key-305F296EAC47556B.asc" "$STUB/keys/305F296EAC47556B"
    run maven org.postgresql:postgresql 42.7.13 42.7.14
    expect_result "発行者の指紋が無い署名は鍵 ID で鍵を取る(実物の postgresql の2つの版は same になる)" same
    expect_calls "発行者の指紋が無い署名は鍵 ID で鍵を取る(search は鍵 ID の 0x305F296EAC47556B)" \
        "^GET ${KEYS}/pks/lookup?op=get&options=mr&search=0x305F296EAC47556B max-time=60$" 2
fi

if want maven_no_prior; then
    reset
    mvn_put central com.acme:widget 1.0.0
    mvn_put central com.acme:widget 1.1.0 "$FA"
    publish_key "$FA" "$FA"
    run maven com.acme:widget 1.0.0 1.1.0
    expect_result "前の版の .pom.asc が 404 なら no-prior-signature になる" no-prior-signature
fi

if want maven_no_new; then
    reset
    mvn_put central com.acme:widget 1.0.0 "$FA"
    mvn_put central com.acme:widget 1.1.0
    publish_key "$FA" "$FA"
    run maven com.acme:widget 1.0.0 1.1.0
    expect_result "前の版に .pom.asc があり新しい版の .pom.asc が 404 なら no-new-signature になる" no-new-signature
    expect_calls "前の版に .pom.asc があり新しい版の .pom.asc が 404 なら no-new-signature になる(404 は再試行しない)" \
        "widget-1\.1\.0\.pom\.asc max-time" 1
fi

if want maven_portal; then
    reset
    mvn_put portal com.acme.gradle:plugin 1.0.0 "$FA"
    mvn_put portal com.acme.gradle:plugin 1.1.0 "$FA"
    publish_key "$FA" "$FA"
    run maven com.acme.gradle:plugin 1.0.0 1.1.0
    expect_result "Maven Central が 404 を返す部品は Gradle Plugin Portal の署名を読む" same
    expect_calls "Maven Central が 404 を返す部品は Gradle Plugin Portal の署名を読む(Maven Central を先に問う)" \
        "^GET ${CENTRAL}/com/acme/gradle/plugin/1\.[01]\.0/plugin-1\.[01]\.0\.pom max-time=60$" 2
    expect_calls "Maven Central が 404 を返す部品は Gradle Plugin Portal の署名を読む(転送を追う)" \
        "^FOLLOW ${PORTAL}/com/acme/gradle/plugin/1\.[01]\.0/plugin-1\.[01]\.0\.pom\.asc$" 2
fi

if want maven_key_missing; then
    reset
    mvn_put central com.acme:widget 1.0.0 "$FA"
    mvn_put central com.acme:widget 1.1.0 "$FA"
    run maven com.acme:widget 1.0.0 1.1.0
    expect_result "鍵を取れなければ unknown になる(鍵サーバに鍵が無い)" unknown
    publish_key "$FA" "$FA"
    : >"$STUB/keys/${FA}.fail"
    : >"$WORK/calls.log"
    run maven com.acme:widget 1.0.0 1.1.0
    expect_result "鍵を取れなければ unknown になる(鍵サーバが失敗する)" unknown
    expect_calls "鍵を取れなければ unknown になる(再試行は1回)" "search=0x${FA} " 2
fi

if want maven_badsig; then
    reset
    mvn_put central com.acme:widget 1.0.0 "$FA"
    mvn_put central com.acme:widget 1.1.0 "$FA"
    publish_key "$FA" "$FA"
    printf '<project>tampered</project>\n' >"$STUB/central/com/acme/widget/1.1.0/widget-1.1.0.pom"
    run maven com.acme:widget 1.0.0 1.1.0
    expect_result "VALIDSIG が出なければ unknown になる(署名が .pom と合わない)" unknown
    reset
    mvn_put central com.acme:widget 1.0.0 "$FA"
    mvn_put central com.acme:widget 1.1.0 "$FA"
    publish_key "$FA" "$FB"
    publish_key "$FB" "$FA"
    run maven com.acme:widget 1.0.0 1.1.0
    expect_result "VALIDSIG が出なければ unknown になる(鍵サーバが別の鍵を返す)" unknown
fi

if want maven_no_issuer; then
    reset
    mvn_put central com.acme:widget 1.0.0 "$FA"
    mvn_put central com.acme:widget 1.1.0
    printf 'not a signature\n' >"$STUB/central/com/acme/widget/1.1.0/widget-1.1.0.pom.asc"
    publish_key "$FA" "$FA"
    run maven com.acme:widget 1.0.0 1.1.0
    expect_result "署名から発行者の指紋も鍵 ID も読めなければ unknown になる" unknown
    expect_calls "署名から発行者の指紋も鍵 ID も読めなければ unknown になる(鍵サーバに問わない)" "search=0x${FA} " 1
fi

if want maven_fetch_fail; then
    reset
    mvn_put central com.acme:widget 1.0.0 "$FA"
    mvn_put central com.acme:widget 1.1.0 "$FA"
    publish_key "$FA" "$FA"
    : >"$STUB/central/com/acme/widget/1.1.0/widget-1.1.0.pom.asc.fail"
    run maven com.acme:widget 1.0.0 1.1.0
    expect_result "取得に失敗したら unknown になる(.pom.asc)" unknown
    expect_calls "取得に失敗したら unknown になる(再試行は1回)" "widget-1\.1\.0\.pom\.asc max-time" 2
    reset
    mvn_put central com.acme:widget 1.0.0 "$FA"
    publish_key "$FA" "$FA"
    run maven com.acme:widget 1.0.0 1.1.0
    expect_result "取得に失敗したら unknown になる(どの配布元にも .pom が無い)" unknown
    reset
    mvn_put central com.acme:widget 1.0.0 "$FA"
    mvn_put central com.acme:widget 1.1.0 "$FA"
    publish_key "$FA" "$FA"
    : >"$STUB/central/com/acme/widget/1.1.0/widget-1.1.0.pom.fail-once"
    run maven com.acme:widget 1.0.0 1.1.0
    expect_result "1回目の取得が失敗しても、再試行で取れれば判定する(maven)" same
fi

if want gomod_no_signature; then
    reset
    run gomod github.com/Example/Tool 1.1.0 1.2.0
    expect_result "gomod の部品は、署名の仕組みが無いので no-prior-signature になる" no-prior-signature
    if [ -s "$WORK/calls.log" ]; then
        fail "gomod の部品は、外部に問い合わせない" "$(head -c 300 "$WORK/calls.log")"
    else
        pass "gomod の部品は、外部に問い合わせない"
    fi
fi

if want bad_args; then
    reset
    run npm widget 1.0.0
    expect_rc "引数が4つでなければ終了コード 2 になる" 2
    run pypi widget 1.0.0 1.1.0
    expect_rc "知らない ecosystem なら終了コード 2 になる" 2
    run maven widget 1.0.0 1.1.0
    expect_rc "maven の名前が groupId:artifactId の形でなければ終了コード 2 になる" 2
fi

if [ "$RAN" -eq 0 ]; then
    echo "FAIL: KP_TEST_CASE=${CASE} に当たる場合がありません"
    FAILED=1
fi

exit "$FAILED"
