//go:build compat

// Command fakeoidc は、比べる検査の Google と GitHub のログインの代わりのサーバを、ポート 8080 で動かす。
package main

import (
	"log"
	"net"
	"net/http"
	"time"

	"github.com/DogisRiki/KeirekiPro/backend/compat/fakeoidc"
)

func main() {
	server := &http.Server{
		Addr:              net.JoinHostPort("", fakeoidc.Port),
		Handler:           fakeoidc.NewServer(),
		ReadHeaderTimeout: 10 * time.Second,
	}
	log.Printf("fakeoidc: ポート %s で受けます", fakeoidc.Port)
	log.Fatal(server.ListenAndServe())
}
