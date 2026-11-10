//go:build compat

// Command fakeaws は、比べる検査の AWS の代わりのサーバを、ポート 4566 で動かす。
package main

import (
	"log"
	"net"
	"net/http"
	"time"

	"github.com/DogisRiki/KeirekiPro/backend/compat/fakeaws"
)

func main() {
	server := &http.Server{
		Addr:              net.JoinHostPort("", fakeaws.Port),
		Handler:           fakeaws.NewServer(),
		ReadHeaderTimeout: 10 * time.Second,
	}
	log.Printf("fakeaws: ポート %s で受けます", fakeaws.Port)
	log.Fatal(server.ListenAndServe())
}
