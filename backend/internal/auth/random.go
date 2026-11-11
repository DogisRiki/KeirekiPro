package auth

import (
	"encoding/base64"
	"encoding/binary"
	"fmt"
	"io"
)

// randomTokenBytes は、ログインを続けるための値などに使う乱数のバイトの数である(Java 版の SecurityUtil と同じ)。
const randomTokenBytes = 32

// codeModulus は、確認のコードの値の数である。コードは 0 から 999999 の6桁になる。
const codeModulus = 1_000_000

// codeAcceptLimit は、4バイトの値のうち、確認のコードに使う値の上限(この値を含まない)である。
// 1000000 で割り切れる範囲だけを使い、それより大きい値を捨てて、0 から 999999 を一様にする。
const codeAcceptLimit = (1 << 32) / codeModulus * codeModulus

// readFunc は、乱数を返す関数を io.Reader として読むための型である。
type readFunc func([]byte) (int, error)

func (f readFunc) Read(p []byte) (int, error) {
	return f(p)
}

// randomToken は、32バイトの乱数を、Java 版の Base64.getUrlEncoder().withoutPadding() と同じく、
// = の無い base64url の文字列にする。read は、crypto/rand.Read と同じ形の乱数の関数である。
func randomToken(read func([]byte) (int, error)) (string, error) {
	b := make([]byte, randomTokenBytes)
	if _, err := io.ReadFull(readFunc(read), b); err != nil {
		return "", fmt.Errorf("乱数を読めない: %w", err)
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}

// randomCode は、0 から 999999 の一様な乱数を、Java 版の String.format("%06d") と同じく、
// 先頭を0で埋めた6桁の確認のコードにする。read は、crypto/rand.Read と同じ形の乱数の関数である。
func randomCode(read func([]byte) (int, error)) (string, error) {
	var b [4]byte
	for {
		if _, err := io.ReadFull(readFunc(read), b[:]); err != nil {
			return "", fmt.Errorf("乱数を読めない: %w", err)
		}
		v := binary.BigEndian.Uint32(b[:])
		if v < codeAcceptLimit {
			return fmt.Sprintf("%06d", v%codeModulus), nil
		}
	}
}
