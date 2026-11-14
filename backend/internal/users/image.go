package users

import (
	"bytes"
	"image"
	"slices"
	"strings"

	// Go 版が読む画像の形式は、PNG と JPEG と GIF だけである。image.DecodeConfig と image.Decode は、ここで読み込んだ形式だけを読む。
	_ "image/gif"
	_ "image/jpeg"
	_ "image/png"
)

// 画像の検査の上限と、許可する形式と拡張子である。どれも Java 版の UpdateUserInfoUseCase と ProfileImageKeys の値を写した。
const (
	// imageMaxBytes は、画像の大きさの上限である(ALLOWED_FILE_SIZE)。
	imageMaxBytes = 1024 * 1024
	// imageMaxDimension は、画像の縦と横の長さの上限である(MAX_IMAGE_DIMENSION)。
	imageMaxDimension = 4096
)

var (
	// imageContentTypes は、許可する部分の Content-Type である(ALLOWED_MIME_TYPES)。Java 版の List.contains と同じく、文字列が
	// 完全に一致するものだけを許可する。
	imageContentTypes = []string{"image/jpeg", "image/png", "image/gif"}
	// imageExtensions は、許可する拡張子である(ProfileImageKeys.ALLOWED_EXTENSIONS)。
	imageExtensions = []string{"jpg", "jpeg", "png", "gif"}
)

// ImageInput は、名前と画像と2段階認証の設定の変更の要求で送られたプロフィール画像である。
type ImageInput struct {
	// FileName は、部分のファイルの名前である。
	FileName string
	// ContentType は、部分の Content-Type の見出しの値である。
	ContentType string
	// Content は、画像のバイトの並びである。
	Content []byte
}

// checkImage は、Java 版の UpdateUserInfoUseCase の validateProfileImage と同じ順で画像を検査し、項目 profileImage の文言を返す。
// 誤りが無ければ nil を返す。中身が空の画像は、Java 版の ProfileImageCommand.isEmpty と同じく検査しない。
//
// 形式と拡張子と大きさの誤りは、すべて集める。そのあと、中身の検査で、次のどれか1つを足す。
//   - 大きさを読めなければ、中身の誤り
//   - 縦か横が上限を超えれば、縦と横の長さの誤り
//   - 中身を最後まで読めなければ、中身の誤り
func checkImage(in ImageInput) []string {
	if len(in.Content) == 0 {
		return nil
	}
	var messages []string
	if !slices.Contains(imageContentTypes, in.ContentType) {
		messages = append(messages, MessageImageTypeNotAllowed)
	}
	if !slices.Contains(imageExtensions, imageExtension(in.FileName)) {
		messages = append(messages, MessageImageExtensionNotAllowed)
	}
	if len(in.Content) > imageMaxBytes {
		messages = append(messages, MessageImageTooLarge)
	}
	if m := checkImageContent(in.Content); m != "" {
		messages = append(messages, m)
	}
	return messages
}

// checkImageContent は、Java 版の validateImageContent と同じく、先に見出しだけを読んで縦と横の長さを確かめ、上限の内のときだけ
// 中身を最後まで読む。大きな画像の中身を読む前に断るので、読むときに使うメモリが、上限の画像の分を超えない。
func checkImageContent(content []byte) string {
	cfg, _, err := image.DecodeConfig(bytes.NewReader(content))
	if err != nil {
		return MessageImageInvalid
	}
	if cfg.Width > imageMaxDimension || cfg.Height > imageMaxDimension {
		return MessageImageTooBig
	}
	if _, _, err := image.Decode(bytes.NewReader(content)); err != nil {
		return MessageImageInvalid
	}
	return ""
}

// imageExtension は、Java 版の UpdateUserInfoUseCase の getExtension と同じく、ファイルの名前の最後の . のあとの文字列を返す。
// . が無いときと、. が最後の字のときは、空の文字列を返す。. が最後の字のときは、. のあとの文字列が空になる。
//
// Java 版は toLowerCase ですべての字を小文字にする。Go 版は ASCII の字だけを小文字にする。Java 版の toLowerCase は、
// ASCII でない字を、許可する拡張子の字(j p e g n i f)にしない。そのため、許可するかどうかの答えは、どちらの版でも同じになる。
func imageExtension(fileName string) string {
	dot := strings.LastIndexByte(fileName, '.')
	if dot < 0 {
		return ""
	}
	return asciiLower(fileName[dot+1:])
}

// asciiLower は、ASCII の大文字だけを小文字にする。
func asciiLower(s string) string {
	b := []byte(s)
	for i, c := range b {
		if 'A' <= c && c <= 'Z' {
			b[i] = c + ('a' - 'A')
		}
	}
	return string(b)
}
