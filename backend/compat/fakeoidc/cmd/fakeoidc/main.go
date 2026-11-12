//go:build compat

// Command fakeoidc は、比べる検査の Google と GitHub のログインの代わりのサーバを、ポート 8080 で動かす。
// 環境変数で証明書と鍵のファイルの場所を渡されたときだけ、api.github.com としてポート 443 でも TLS を受ける。
package main

import (
	"log"
	"net"
	"net/http"
	"os"
	"time"

	"github.com/DogisRiki/KeirekiPro/backend/compat/fakeoidc"
)

func main() {
	handler := fakeoidc.NewServer()
	tlsServer, err := handler.TLSServer(os.Getenv(fakeoidc.CertFileEnv), os.Getenv(fakeoidc.KeyFileEnv))
	if err != nil {
		log.Fatal(err)
	}
	server := &http.Server{
		Addr:              net.JoinHostPort("", fakeoidc.Port),
		Handler:           handler,
		ReadHeaderTimeout: 10 * time.Second,
	}
	failed := make(chan error, 2)
	if tlsServer != nil {
		log.Printf("fakeoidc: ポート %s で api.github.com として TLS を受けます", fakeoidc.TLSPort)
		go func() { failed <- tlsServer.ListenAndServeTLS("", "") }()
	}
	log.Printf("fakeoidc: ポート %s で受けます", fakeoidc.Port)
	go func() { failed <- server.ListenAndServe() }()
	log.Fatal(<-failed)
}
