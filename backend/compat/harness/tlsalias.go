//go:build compat

package harness

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"math/big"
	"os"
	"path/filepath"
	"time"

	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/wait"

	"github.com/DogisRiki/KeirekiPro/backend/compat/fakeoidc"
)

// GitHubAPIHost は、Java 版と Go 版が GitHub のメールアドレスを読むときにつなぐホストである。
// 検査のネットワークでは、fakeoidc がこの別名で TLS を受ける。
const GitHubAPIHost = "api.github.com"

// コンテナの中の、TLS のためのファイルの置き場である。どのコンテナでも同じ置き場に写す。
const (
	tlsDir = "/compat-tls"
	// CACertPath は、検査のたびに作る認証局の証明書の置き場である。Go 版は SSL_CERT_FILE でこれを信頼する。
	CACertPath = tlsDir + "/ca.pem"
	// TrustStorePath は、認証局の証明書を入れた PKCS12 の信頼の束の置き場である。Java 版は JAVA_TOOL_OPTIONS でこれを信頼する。
	TrustStorePath = tlsDir + "/truststore.p12"
	// TLSCertPath と TLSKeyPath は、fakeoidc が api.github.com として TLS を受ける証明書と鍵の置き場である。
	TLSCertPath = tlsDir + "/api-github-com.pem"
	TLSKeyPath  = tlsDir + "/api-github-com-key.pem"
)

// containerFileMode は、コンテナに写すファイルの権限である。backend と fakeoidc は root でない利用者で動くので、
// 誰でも読める権限にする。手元のファイルは 0600 で作業用のフォルダに置く。
const containerFileMode = 0o644

// keytoolBuildPath は、keytool のコンテナの中で信頼の束を作る場所である。
// Java 版のイメージの利用者が書ける /tmp に作り、止まったコンテナから写し出す。
const keytoolBuildPath = "/tmp/truststore.p12"

// TLSAlias は、検査のたびに作る、自己署名の認証局と、その認証局が署名した api.github.com の証明書と鍵である。
// フィールドはすべて手元のファイルのパスで、ファイルは作業用のフォルダに置く。本番と開発の設定には置かない。
type TLSAlias struct {
	CACertFile string
	CertFile   string
	KeyFile    string
	// TrustStoreFile は、BuildTrustStore で作った PKCS12 の信頼の束である。作る前は空である。
	TrustStoreFile string
	// TrustStorePassword は、信頼の束を開くパスワードである。検査のたびに作る。
	TrustStorePassword string

	dir string
}

// NewTLSAlias は、自己署名の認証局と、その認証局が署名した api.github.com の証明書と鍵を作り、dir に PEM で書く。
func NewTLSAlias(dir string) (*TLSAlias, error) {
	caKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, fmt.Errorf("harness: 認証局の鍵を作れません: %w", err)
	}
	caSerial, err := serialNumber()
	if err != nil {
		return nil, err
	}
	leafSerial, err := serialNumber()
	if err != nil {
		return nil, err
	}
	now := time.Now()
	caTemplate := &x509.Certificate{
		SerialNumber:          caSerial,
		Subject:               pkix.Name{CommonName: "KeirekiPro compat CA"},
		NotBefore:             now.Add(-time.Hour),
		NotAfter:              now.Add(24 * time.Hour),
		IsCA:                  true,
		BasicConstraintsValid: true,
		KeyUsage:              x509.KeyUsageCertSign | x509.KeyUsageCRLSign,
	}
	caDER, err := x509.CreateCertificate(rand.Reader, caTemplate, caTemplate, &caKey.PublicKey, caKey)
	if err != nil {
		return nil, fmt.Errorf("harness: 認証局の証明書を作れません: %w", err)
	}
	ca, err := x509.ParseCertificate(caDER)
	if err != nil {
		return nil, fmt.Errorf("harness: 認証局の証明書を読めません: %w", err)
	}
	leafKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, fmt.Errorf("harness: %s の鍵を作れません: %w", GitHubAPIHost, err)
	}
	leafTemplate := &x509.Certificate{
		SerialNumber: leafSerial,
		Subject:      pkix.Name{CommonName: GitHubAPIHost},
		DNSNames:     []string{GitHubAPIHost},
		NotBefore:    now.Add(-time.Hour),
		NotAfter:     now.Add(24 * time.Hour),
		KeyUsage:     x509.KeyUsageDigitalSignature,
		ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
	}
	leafDER, err := x509.CreateCertificate(rand.Reader, leafTemplate, ca, &leafKey.PublicKey, caKey)
	if err != nil {
		return nil, fmt.Errorf("harness: %s の証明書を作れません: %w", GitHubAPIHost, err)
	}
	keyDER, err := x509.MarshalPKCS8PrivateKey(leafKey)
	if err != nil {
		return nil, fmt.Errorf("harness: %s の鍵を書き出せません: %w", GitHubAPIHost, err)
	}
	a := &TLSAlias{
		CACertFile:         filepath.Join(dir, "ca.pem"),
		CertFile:           filepath.Join(dir, "api-github-com.pem"),
		KeyFile:            filepath.Join(dir, "api-github-com-key.pem"),
		TrustStorePassword: rand.Text(),
		dir:                dir,
	}
	for file, block := range map[string]*pem.Block{
		a.CACertFile: {Type: "CERTIFICATE", Bytes: caDER},
		a.CertFile:   {Type: "CERTIFICATE", Bytes: leafDER},
		a.KeyFile:    {Type: "PRIVATE KEY", Bytes: keyDER},
	} {
		if err := os.WriteFile(file, pem.EncodeToMemory(block), 0o600); err != nil {
			return nil, fmt.Errorf("harness: %s を書けません: %w", file, err)
		}
	}
	return a, nil
}

// serialNumber は、証明書の通し番号を、暗号に使える乱数から作る。RFC 5280 の上限の20バイトに収まる128ビットにする。
func serialNumber() (*big.Int, error) {
	n, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
	if err != nil {
		return nil, fmt.Errorf("harness: 証明書の通し番号を作れません: %w", err)
	}
	return n, nil
}

// BuildTrustStore は、Java 版のイメージ image の keytool で、認証局の証明書だけを信頼する PKCS12 の信頼の束を作り、
// 作業用のフォルダに TrustStoreFile として置く。作ったあとにもう一度呼ばれたら、keytool を動かさずに戻る。
// keytool を動かすコンテナは env に入れるので、env を片付けるときに消える。
func (a *TLSAlias) BuildTrustStore(ctx context.Context, env *Env, image string) error {
	if a.TrustStoreFile != "" {
		return nil
	}
	c, err := env.Start(ctx, ContainerSpec{
		Name:       "keytool",
		Image:      image,
		Entrypoint: []string{"keytool"},
		Cmd: []string{
			"-importcert", "-noprompt", "-alias", "keirekipro-compat-ca", "-file", CACertPath,
			"-keystore", keytoolBuildPath, "-storetype", "PKCS12", "-storepass", a.TrustStorePassword,
		},
		Files:      []testcontainers.ContainerFile{{HostFilePath: a.CACertFile, ContainerFilePath: CACertPath, FileMode: containerFileMode}},
		WaitingFor: wait.ForExit(),
	})
	if err != nil {
		return fmt.Errorf("harness: keytool のコンテナを動かせません: %w", err)
	}
	state, err := c.State(ctx)
	if err != nil {
		return fmt.Errorf("harness: keytool のコンテナの状態を読めません: %w", err)
	}
	if state.ExitCode != 0 {
		return fmt.Errorf("harness: keytool が終了コード %d で失敗しました: %s", state.ExitCode, tailLogs(ctx, c))
	}
	in, err := c.CopyFileFromContainer(ctx, keytoolBuildPath)
	if err != nil {
		return fmt.Errorf("harness: keytool が作った信頼の束を写し出せません: %w", err)
	}
	defer func() { _ = in.Close() }()
	file := filepath.Join(a.dir, "truststore.p12")
	data, err := io.ReadAll(in)
	if err != nil {
		return fmt.Errorf("harness: keytool が作った信頼の束を読めません: %w", err)
	}
	if err := os.WriteFile(file, data, 0o600); err != nil {
		return fmt.Errorf("harness: 信頼の束 %s を書けません: %w", file, err)
	}
	a.TrustStoreFile = file
	return nil
}

// tailLogs は、コンテナのログの終わりの 4096 バイトを返す。読めなければ、読めない理由を返す。
func tailLogs(ctx context.Context, c *Container) string {
	logs, err := c.Logs(ctx)
	if err != nil {
		return "ログを読めません: " + err.Error()
	}
	defer func() { _ = logs.Close() }()
	text, err := io.ReadAll(logs)
	if err != nil {
		return "ログを読めません: " + err.Error()
	}
	if len(text) > 4096 {
		text = text[len(text)-4096:]
	}
	return string(text)
}

// fakeOIDCSpec は、fakeoidc のコンテナの起動の形を返す。a が nil でなければ、a の証明書と鍵を写し、
// ネットワークの別名 api.github.com を付けて、ポート fakeoidc.TLSPort で TLS を受けさせる。
func fakeOIDCSpec(image string, a *TLSAlias) ContainerSpec {
	spec := ContainerSpec{
		Name:         "fakeoidc",
		Image:        image,
		ExposedPorts: []string{fakeoidc.Port + "/tcp"},
		WaitingFor:   wait.ForHTTP("/_compat/healthz").WithPort(fakeoidc.Port + "/tcp"),
	}
	if a == nil {
		return spec
	}
	spec.Aliases = []string{GitHubAPIHost}
	spec.Env = map[string]string{fakeoidc.CertFileEnv: TLSCertPath, fakeoidc.KeyFileEnv: TLSKeyPath}
	spec.Files = []testcontainers.ContainerFile{
		{HostFilePath: a.CertFile, ContainerFilePath: TLSCertPath, FileMode: containerFileMode},
		{HostFilePath: a.KeyFile, ContainerFilePath: TLSKeyPath, FileMode: containerFileMode},
	}
	return spec
}

// backendSpec は、つなぐ先 b の be を、backend-<version> の名前で起動する形を返す。
// b が TLS の別名を持てば、認証局の証明書を写し、be が Java 版の起動の仕方なら、信頼の束も写す。
// Java 版の信頼の束は、BuildTrustStore で作ってから渡す。作る前なら誤りを返す。
func backendSpec(version string, be Backend, b Backing) (ContainerSpec, error) {
	spec := ContainerSpec{
		Name:         "backend-" + version,
		Image:        be.Image,
		Env:          be.Env(b),
		ExposedPorts: []string{backendPort},
		WaitingFor:   wait.ForHTTP(be.HealthPath).WithPort(backendPort),
	}
	if b.tls == nil {
		return spec, nil
	}
	spec.Files = []testcontainers.ContainerFile{{HostFilePath: b.tls.CACertFile, ContainerFilePath: CACertPath, FileMode: containerFileMode}}
	if be.JavaTrustStore {
		if b.tls.TrustStoreFile == "" {
			return ContainerSpec{}, errors.New("harness: Java 版の信頼の束をまだ作っていません")
		}
		spec.Files = append(spec.Files, testcontainers.ContainerFile{
			HostFilePath: b.tls.TrustStoreFile, ContainerFilePath: TrustStorePath, FileMode: containerFileMode,
		})
	}
	return spec, nil
}
