//go:build compat

package harness

import (
	"bytes"
	"fmt"
	"os"
	"path"
	"path/filepath"
)

// multipartBoundary は、harness が multipart の本文を組み立てるときに使う、決まった区切りの文字列である。
// 同じ筋書きの段は、Java 版と Go 版に、同じバイトの並びの本文を送る。
const multipartBoundary = "KeirekiProCompatBoundary"

// multipartBody は、段 step の request.multipart から本文を組み立て、本文と、その本文の Content-Type を返す。
// 文字の部分の値の {名前} は、前の段で取り出した値に置き換える。文字の部分には Content-Type を付けない。
// file の部分は、fixtures/images の下のファイルを中身にし、filename を書かなければファイルの名前を送り、
// content_type を書かなければ Content-Type を付けない。pad_to を書いた部分は、ファイルの後ろに0のバイトを足して、
// 中身を pad_to の大きさにする。部分の名前とファイルの名前は、筋書きに書いたまま送る。
func (s *Session) multipartBody(step Step) ([]byte, string, error) {
	var b bytes.Buffer
	for i, part := range step.Request.Multipart {
		fmt.Fprintf(&b, "--%s\r\n", multipartBoundary)
		if part.Value != nil {
			v, err := s.expand(step, fmt.Sprintf("multipart の %d 番目の部分の値", i+1), *part.Value)
			if err != nil {
				return nil, "", err
			}
			fmt.Fprintf(&b, "Content-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n", part.Name, v)
			continue
		}
		data, err := readImageFixture(part.File)
		if err != nil {
			return nil, "", fmt.Errorf("harness: 段 %s の multipart の %d 番目の部分の file %q を読めません: %w", step.Name, i+1, part.File, err)
		}
		filename := part.Filename
		if filename == "" {
			filename = path.Base(part.File)
		}
		fmt.Fprintf(&b, "Content-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\n", part.Name, filename)
		if part.ContentType != "" {
			fmt.Fprintf(&b, "Content-Type: %s\r\n", part.ContentType)
		}
		b.WriteString("\r\n")
		b.Write(data)
		if pad := part.PadTo - len(data); pad > 0 {
			b.Write(make([]byte, pad))
		}
		b.WriteString("\r\n")
	}
	fmt.Fprintf(&b, "--%s--\r\n", multipartBoundary)
	return b.Bytes(), "multipart/form-data; boundary=" + multipartBoundary, nil
}

// readImageFixture は、fixtures/images の下のファイル name の中身を返す。fixtures/images の外を指す名前は誤りにする。
func readImageFixture(name string) ([]byte, error) {
	root, err := os.OpenRoot(filepath.Join(FixturesDir(), imagesFixtureDir))
	if err != nil {
		return nil, fmt.Errorf("画像のフォルダ fixtures/images を開けません: %w", err)
	}
	defer func() { _ = root.Close() }()
	return root.ReadFile(filepath.FromSlash(name))
}
