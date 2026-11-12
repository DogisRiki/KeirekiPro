package auth

import (
	"bytes"
	"errors"
	"strings"
	"testing"
)

// fixedRandom は、決めたバイトの並びを先頭から順に返す乱数の関数を作る。
func fixedRandom(b []byte) func([]byte) (int, error) {
	r := bytes.NewReader(b)
	return r.Read
}

// TestRandomToken_32BytesBase64URL は、32バイトの乱数を、Java 版の
// Base64.getUrlEncoder().withoutPadding() と同じ、= の無い base64url の43文字にすることを確かめる。
func TestRandomToken_32BytesBase64URL(t *testing.T) {
	got, err := randomToken(fixedRandom(bytes.Repeat([]byte{0xff}, 32)))
	if err != nil {
		t.Fatalf("randomToken: %v", err)
	}
	// 0xff の32バイトは、6ビットずつ区切ると 63 が42個と、残りの4ビットの 111100(60)になる
	want := strings.Repeat("_", 42) + "8"
	if got != want {
		t.Errorf("randomToken = %q, want %q", got, want)
	}
}

// TestRandomToken_ReadsExactly32Bytes は、乱数を32バイトだけ読むことを確かめる。
func TestRandomToken_ReadsExactly32Bytes(t *testing.T) {
	src := append(bytes.Repeat([]byte{0x00}, 32), 0xff)
	r := bytes.NewReader(src)
	got, err := randomToken(r.Read)
	if err != nil {
		t.Fatalf("randomToken: %v", err)
	}
	if want := strings.Repeat("A", 43); got != want {
		t.Errorf("randomToken = %q, want %q", got, want)
	}
	if r.Len() != 1 {
		t.Errorf("読み残しのバイトの数 = %d, want 1", r.Len())
	}
}

// TestRandomToken_ReadError は、乱数を読めないときに誤りを返すことを確かめる。
func TestRandomToken_ReadError(t *testing.T) {
	if _, err := randomToken(fixedRandom(make([]byte, 31))); err == nil {
		t.Fatal("乱数が31バイトしか無いのに、randomToken が誤りを返さない")
	}
}

// TestRandomCode_SixDigitsZeroPadded は、確認のコードを、Java 版の String.format("%06d") と同じく
// 先頭を0で埋めた6桁にすることを確かめる。
func TestRandomCode_SixDigitsZeroPadded(t *testing.T) {
	got, err := randomCode(fixedRandom([]byte{0x00, 0x00, 0x00, 0x05}))
	if err != nil {
		t.Fatalf("randomCode: %v", err)
	}
	if got != "000005" {
		t.Errorf("randomCode = %q, want %q", got, "000005")
	}
}

// TestRandomCode_RejectsBiasedValues は、0 から 999999 に一様にするため、
// 1000000 で割り切れる範囲を超えた値を捨てて、次の値を読むことを確かめる。
func TestRandomCode_RejectsBiasedValues(t *testing.T) {
	src := []byte{
		0xff, 0xff, 0xff, 0xff, // 4294967295 は捨てる
		0xff, 0xf1, 0x3d, 0x80, // 4294000000 は捨てる(受け入れる最大の値 4293999999 の1つ上)
		0xff, 0xf1, 0x3d, 0x7f, // 4293999999 は受け入れる。1000000 で割った余りは 999999
	}
	got, err := randomCode(fixedRandom(src))
	if err != nil {
		t.Fatalf("randomCode: %v", err)
	}
	if got != "999999" {
		t.Errorf("randomCode = %q, want %q", got, "999999")
	}
}

// TestRandomCode_ReadError は、乱数を読めないときに誤りを返すことを確かめる。
func TestRandomCode_ReadError(t *testing.T) {
	failing := func([]byte) (int, error) { return 0, errors.New("読めない") }
	if _, err := randomCode(failing); err == nil {
		t.Fatal("乱数を読めないのに、randomCode が誤りを返さない")
	}
}
