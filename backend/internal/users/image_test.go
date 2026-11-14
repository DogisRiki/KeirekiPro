package users

import (
	"bytes"
	"compress/zlib"
	"encoding/binary"
	"hash/crc32"
	"io/fs"
	"math"
	"os"
	"slices"
	"testing"
)

// このファイルは、image/png と image/jpeg と image/gif を読み込まない。読み込むと、テストの中で画像の形式が登録され、
// image.go がその形式を読み込み忘れても、テストが通ってしまうためである。PNG は pngBytes で組み立て、JPEG と GIF は
// testdata/images の見本のファイルを読む。

// pngBytes は、横 w 画素、縦 h 画素の、8ビットの灰色の PNG のバイトの並びを組み立てる。
func pngBytes(t *testing.T, w, h uint32) []byte {
	t.Helper()
	var pixels bytes.Buffer
	zw := zlib.NewWriter(&pixels)
	row := make([]byte, 1+uint64(w)) // 先頭の 0 は、行の変換の種類(変換しない)である
	for range h {
		if _, err := zw.Write(row); err != nil {
			t.Fatalf("PNG の画素を圧縮できない: %v", err)
		}
	}
	if err := zw.Close(); err != nil {
		t.Fatalf("PNG の画素を圧縮できない: %v", err)
	}

	var out bytes.Buffer
	out.WriteString("\x89PNG\r\n\x1a\n")
	chunk := func(kind string, data []byte) {
		n := len(data)
		if n < 0 || n > math.MaxUint32 {
			t.Fatalf("PNG の塊が大きすぎる: %d バイト", n)
			return
		}
		out.Write(binary.BigEndian.AppendUint32(nil, uint32(n)))
		body := append([]byte(kind), data...)
		out.Write(body)
		out.Write(binary.BigEndian.AppendUint32(nil, crc32.ChecksumIEEE(body)))
	}
	header := binary.BigEndian.AppendUint32(nil, w)
	header = binary.BigEndian.AppendUint32(header, h)
	header = append(header, 8, 0, 0, 0, 0) // 8ビット、灰色、圧縮と変換と飛び越しは既定
	chunk("IHDR", header)
	chunk("IDAT", pixels.Bytes())
	chunk("IEND", nil)
	return out.Bytes()
}

// sampleImage は、testdata/images の見本のファイルを読む。見本は、Java の ImageIO が書いた横 2 画素、縦 2 画素の画像である。
func sampleImage(t *testing.T, name string) []byte {
	t.Helper()
	b, err := fs.ReadFile(os.DirFS("testdata/images"), name)
	if err != nil {
		t.Fatalf("見本の %s を読めない: %v", name, err)
	}
	return b
}

// paddedPNG は、1画素の PNG のあとに 0 のバイトを足して、全体を n バイトにする。PNG の読み方は、最後の塊のあとのバイトを読まない。
func paddedPNG(t *testing.T, n int) []byte {
	t.Helper()
	b := pngBytes(t, 1, 1)
	if len(b) > n {
		t.Fatalf("PNG が %d バイトより大きい", n)
	}
	return append(b, make([]byte, n-len(b))...)
}

// truncatedPNG は、見出しの塊までは正しく、画素の塊が壊れた PNG を作る。大きさは読めるが、中身は最後まで読めない。
func truncatedPNG(t *testing.T) []byte {
	t.Helper()
	b := pngBytes(t, 8, 8)
	// 8 バイトの印と、25 バイトの IHDR の塊と、IDAT の塊の長さと種類の 8 バイトを残し、画素の圧縮した中身を消す。
	return b[:8+25+8]
}

func validPNG(t *testing.T) ImageInput {
	t.Helper()
	return ImageInput{FileName: "a.png", ContentType: "image/png", Content: pngBytes(t, 1, 1)}
}

func checkMessages(t *testing.T, name string, in ImageInput, want []string) {
	t.Helper()
	got := checkImage(in)
	if !slices.Equal(got, want) {
		t.Errorf("%s: 文言 = %q、期待 = %q", name, got, want)
	}
}

func TestCheckImage_Boundaries(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name    string
		content []byte
		want    []string
	}{
		{"1048576 バイト", paddedPNG(t, 1048576), nil},
		{"1048577 バイト", paddedPNG(t, 1048577), []string{MessageImageTooLarge}},
		{"横 4096 画素", pngBytes(t, 4096, 1), nil},
		{"横 4097 画素", pngBytes(t, 4097, 1), []string{MessageImageTooBig}},
		{"縦 4096 画素", pngBytes(t, 1, 4096), nil},
		{"縦 4097 画素", pngBytes(t, 1, 4097), []string{MessageImageTooBig}},
	}
	for _, c := range cases {
		checkMessages(t, c.name, ImageInput{FileName: "a.png", ContentType: "image/png", Content: c.content}, c.want)
	}
}

func TestCheckImage_Formats(t *testing.T) {
	t.Parallel()

	jpg := sampleImage(t, "small.jpg")
	gf := sampleImage(t, "small.gif")

	checkMessages(t, "PNG", validPNG(t), nil)
	checkMessages(t, "JPEG", ImageInput{FileName: "a.jpg", ContentType: "image/jpeg", Content: jpg}, nil)
	checkMessages(t, "JPEG の拡張子 jpeg", ImageInput{FileName: "a.jpeg", ContentType: "image/jpeg", Content: jpg}, nil)
	checkMessages(t, "GIF", ImageInput{FileName: "a.gif", ContentType: "image/gif", Content: gf}, nil)
	// 途中で切れた JPEG と GIF は、大きさは読めても、中身を最後まで読めない。
	checkMessages(t, "切れた JPEG", ImageInput{FileName: "a.jpg", ContentType: "image/jpeg", Content: jpg[:len(jpg)/2]}, []string{MessageImageInvalid})
	checkMessages(t, "切れた GIF", ImageInput{FileName: "a.gif", ContentType: "image/gif", Content: gf[:len(gf)-5]}, []string{MessageImageInvalid})
	// 形式と拡張子と中身の組み合わせは確かめない。Java 版も確かめない。
	checkMessages(t, "PNG の中身に gif の名前", ImageInput{FileName: "a.gif", ContentType: "image/gif", Content: pngBytes(t, 1, 1)}, nil)

	// Java 版が読める BMP を、Go 版は読まない。置き換えの spec の変えた動きの一覧のとおりである。
	bmp := append([]byte("BM"), make([]byte, 64)...)
	checkMessages(t, "BMP", ImageInput{FileName: "a.png", ContentType: "image/png", Content: bmp}, []string{MessageImageInvalid})

	// 中身が空の画像は、Java 版の isEmpty と同じく、検査しない。
	checkMessages(t, "空の中身", ImageInput{FileName: "a.txt", ContentType: "text/plain"}, nil)
}

func TestCheckImage_ContentTypeAndExtension(t *testing.T) {
	t.Parallel()

	content := pngBytes(t, 1, 1)
	types := []struct {
		contentType string
		ok          bool
	}{
		{"image/png", true},
		{"image/jpeg", true},
		{"image/gif", true},
		{"", false},
		{"IMAGE/PNG", false},
		{"image/png; charset=UTF-8", false},
		{"image/jpg", false},
		{"image/webp", false},
	}
	for _, c := range types {
		var want []string
		if !c.ok {
			want = []string{MessageImageTypeNotAllowed}
		}
		checkMessages(t, "Content-Type "+c.contentType, ImageInput{FileName: "a.png", ContentType: c.contentType, Content: content}, want)
	}

	names := []struct {
		fileName string
		ok       bool
	}{
		{"a.png", true},
		{"a.PNG", true},
		{"a.Jpeg", true},
		{"a.JPG", true},
		{"a.GIF", true},
		{"a.txt.png", true},
		{".png", true},
		{"画像.png", true},
		{"a.png.txt", false},
		{"a.", false},
		{"png", false},
		{"", false},
		{"a.webp", false},
		{"a. png", false},
	}
	for _, c := range names {
		var want []string
		if !c.ok {
			want = []string{MessageImageExtensionNotAllowed}
		}
		checkMessages(t, "ファイルの名前 "+c.fileName, ImageInput{FileName: c.fileName, ContentType: "image/png", Content: content}, want)
	}
}

func TestCheckImage_NonASCIIExtension(t *testing.T) {
	t.Parallel()

	content := pngBytes(t, 1, 1)
	// Java 版の toLowerCase は、どの字も ASCII の j p e g n i f にしない。ASCII でない字を含む拡張子は、どちらの版でも許可しない。
	for _, name := range []string{
		"a.ｐｎｇ",                            // 全角の字
		"a.ＧＩＦ",                            // 全角の大文字
		"a.G\u0130F",                       // トルコ語の点のある大文字の I。Java 版の toLowerCase は i と結合する点の2字にする
		"a.JPE\u0301G",                     // E のあとに結合するアクセント
		"a.\u212aPG",                       // ケルビンの記号。Java 版の toLowerCase は k にするが、k を含む拡張子は無い
		"a.p\u00f1g",                       // ASCII でない小文字
		"a.png\u200b",                      // 幅の無い空白
		"a.\U0001d429\U0001d427\U0001d420", // 数学用の太字
	} {
		checkMessages(t, "ファイルの名前 "+name, ImageInput{FileName: name, ContentType: "image/png", Content: content}, []string{MessageImageExtensionNotAllowed})
	}
}

func TestCheckImage_ErrorOrder(t *testing.T) {
	t.Parallel()

	// 形式と拡張子と大きさの誤りは、すべて集め、そのあとに中身の誤りを足す。
	big := append([]byte("not image"), make([]byte, 1048576)...)
	checkMessages(t, "4つが重なる", ImageInput{FileName: "a.bmp", ContentType: "image/bmp", Content: big}, []string{
		MessageImageTypeNotAllowed,
		MessageImageExtensionNotAllowed,
		MessageImageTooLarge,
		MessageImageInvalid,
	})

	// 縦と横の長さの誤りでは、中身を最後まで読まずに終える。
	checkMessages(t, "形式と長さ", ImageInput{FileName: "a.png", ContentType: "text/plain", Content: pngBytes(t, 4097, 1)}, []string{
		MessageImageTypeNotAllowed,
		MessageImageTooBig,
	})

	// 大きさは読めるが中身を最後まで読めない画像は、中身の誤りを1つだけ足す。
	checkMessages(t, "中身が壊れた PNG", ImageInput{FileName: "a.png", ContentType: "image/png", Content: truncatedPNG(t)}, []string{MessageImageInvalid})
	checkMessages(t, "拡張子と中身が壊れた PNG", ImageInput{FileName: "a.txt", ContentType: "image/png", Content: truncatedPNG(t)}, []string{
		MessageImageExtensionNotAllowed,
		MessageImageInvalid,
	})

	// 大きさを読めない画像では、縦と横の長さを確かめずに終える。
	checkMessages(t, "画像でない", ImageInput{FileName: "a.png", ContentType: "image/png", Content: []byte("hello")}, []string{MessageImageInvalid})
}

func TestImageExtension(t *testing.T) {
	t.Parallel()

	cases := map[string]string{
		"a.png":      "png",
		"a.PNG":      "png",
		"a.b.JpEg":   "jpeg",
		"a.":         "",
		"a":          "",
		"":           "",
		".gif":       "gif",
		"a.ＰＮＧ":      "ＰＮＧ",
		"a.G\u0130F": "g\u0130f",
	}
	for name, want := range cases {
		if got := imageExtension(name); got != want {
			t.Errorf("imageExtension(%q) = %q、期待 = %q", name, got, want)
		}
	}
}
