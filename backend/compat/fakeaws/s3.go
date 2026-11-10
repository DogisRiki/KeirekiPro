//go:build compat

package fakeaws

import (
	"bufio"
	"bytes"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"encoding/hex"
	"encoding/xml"
	"errors"
	"fmt"
	"hash/crc32"
	"io"
	"log"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
)

// maxObjectSize は、受けるオブジェクトの大きさの上限である。利用者が上げる画像と作る PDF より十分に大きくする。
const maxObjectSize = 32 << 20

const metaPrefix = "X-Amz-Meta-"

// putObject は、S3 の PutObject を受ける。
func (s *Server) putObject(w http.ResponseWriter, r *http.Request) {
	body, err := readObjectBody(w, r)
	if err != nil {
		writeS3Error(w, http.StatusBadRequest, "InvalidRequest", err.Error(), r.PathValue("key"))
		return
	}
	metadata := map[string]string{}
	for name, values := range r.Header {
		if meta, ok := strings.CutPrefix(name, metaPrefix); ok && len(values) > 0 {
			metadata[strings.ToLower(meta)] = values[0]
		}
	}
	o := Object{
		Bucket:       r.PathValue("bucket"),
		Key:          r.PathValue("key"),
		ContentType:  r.Header.Get("Content-Type"),
		Metadata:     metadata,
		Body:         body,
		LastModified: s.now().UTC(),
	}
	s.mu.Lock()
	s.storeOf(versionOf(r)).objects[o.Bucket+"/"+o.Key] = o
	s.mu.Unlock()
	w.Header().Set("ETag", etag(body))
	w.WriteHeader(http.StatusOK)
}

// getObject は、S3 の GetObject と、署名付きの URL の GetObject を受ける。署名付きの URL の問い合わせの値は見ない。
func (s *Server) getObject(w http.ResponseWriter, r *http.Request) {
	bucket, key := r.PathValue("bucket"), r.PathValue("key")
	s.mu.Lock()
	o, ok := s.storeOf(versionOf(r)).objects[bucket+"/"+key]
	s.mu.Unlock()
	if !ok {
		writeS3Error(w, http.StatusNotFound, "NoSuchKey", "The specified key does not exist.", key)
		return
	}
	h := w.Header()
	contentType := o.ContentType
	if contentType == "" {
		contentType = "binary/octet-stream"
	}
	h.Set("Content-Type", contentType)
	h.Set("Content-Length", strconv.Itoa(len(o.Body)))
	h.Set("ETag", etag(o.Body))
	h.Set("Last-Modified", o.LastModified.Format(http.TimeFormat))
	for name, value := range o.Metadata {
		h.Set(metaPrefix+name, value)
	}
	// AWS の SDK は、応答の本文の検査の値を求めたときに、その値で本文を確かめる
	if strings.EqualFold(r.Header.Get("X-Amz-Checksum-Mode"), "ENABLED") {
		h.Set("X-Amz-Checksum-Crc32", checksumCRC32(o.Body))
	}
	w.WriteHeader(http.StatusOK)
	if _, err := w.Write(o.Body); err != nil {
		slog.LogAttrs(r.Context(), slog.LevelWarn, "fakeaws_write_failed",
			slog.String("bucket", bucket), slog.String("key", key), slog.String("error", err.Error()))
	}
}

// deleteObject は、S3 の DeleteObject を受ける。S3 と同じく、無いキーを消しても成功にする。
func (s *Server) deleteObject(w http.ResponseWriter, r *http.Request) {
	s.mu.Lock()
	delete(s.storeOf(versionOf(r)).objects, r.PathValue("bucket")+"/"+r.PathValue("key"))
	s.mu.Unlock()
	w.WriteHeader(http.StatusNoContent)
}

// readObjectBody は、PutObject の本文を読む。
// AWS の SDK が本文を aws-chunked の形(大きさの行と中身を繰り返し、最後に検査の値を付ける形)で送ったときは、中身だけを取り出す。
func readObjectBody(w http.ResponseWriter, r *http.Request) ([]byte, error) {
	raw, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxObjectSize))
	if err != nil {
		return nil, fmt.Errorf("本文を読めません: %w", err)
	}
	if !strings.Contains(r.Header.Get("Content-Encoding"), "aws-chunked") &&
		!strings.HasPrefix(r.Header.Get("X-Amz-Content-Sha256"), "STREAMING-") {
		return raw, nil
	}
	body, err := decodeAWSChunked(raw)
	if err != nil {
		return nil, err
	}
	if decoded := r.Header.Get("X-Amz-Decoded-Content-Length"); decoded != "" && decoded != strconv.Itoa(len(body)) {
		return nil, fmt.Errorf("aws-chunked の中身の大きさ %d が x-amz-decoded-content-length の %s と違います", len(body), decoded)
	}
	return body, nil
}

// decodeAWSChunked は、aws-chunked の形の本文から中身を取り出す。
// 形は、「16進の大きさ[;chunk-signature=…]」の行、中身、改行の繰り返しで、大きさ 0 の行のあとに検査の値の行が続く。
func decodeAWSChunked(raw []byte) ([]byte, error) {
	reader := bufio.NewReader(bytes.NewReader(raw))
	var body bytes.Buffer
	for {
		line, err := reader.ReadString('\n')
		if err != nil {
			return nil, fmt.Errorf("aws-chunked の大きさの行を読めません: %w", err)
		}
		sizeText, _, _ := strings.Cut(strings.TrimRight(line, "\r\n"), ";")
		size, err := strconv.ParseInt(strings.TrimSpace(sizeText), 16, 64)
		if err != nil || size < 0 || size > maxObjectSize {
			return nil, fmt.Errorf("aws-chunked の大きさの行 %q が誤っています", line)
		}
		if size == 0 {
			return body.Bytes(), nil
		}
		if _, err := io.CopyN(&body, reader, size); err != nil {
			return nil, fmt.Errorf("aws-chunked の中身を読めません: %w", err)
		}
		end, err := reader.ReadString('\n')
		if err != nil || strings.TrimRight(end, "\r\n") != "" {
			return nil, errors.New("aws-chunked の中身のあとに改行がありません")
		}
	}
}

// etag は、本文から決まる ETag を返す。S3 の ETag は本文の MD5 だが、AWS の SDK は ETag で本文を確かめず、
// x-amz-checksum-crc32 で確かめるので、MD5 と同じ長さの SHA-256 の先頭を使う。
func etag(body []byte) string {
	sum := sha256.Sum256(body)
	return `"` + hex.EncodeToString(sum[:16]) + `"`
}

func checksumCRC32(body []byte) string {
	var b [4]byte
	binary.BigEndian.PutUint32(b[:], crc32.ChecksumIEEE(body))
	return base64.StdEncoding.EncodeToString(b[:])
}

// s3Error は、S3 の誤りの応答の本文である。
type s3Error struct {
	XMLName xml.Name `xml:"Error"`
	Code    string   `xml:"Code"`
	Message string   `xml:"Message"`
	Key     string   `xml:"Key,omitempty"`
}

func writeS3Error(w http.ResponseWriter, status int, code, message, key string) {
	writeXML(w, status, s3Error{Code: code, Message: message, Key: key})
}

func writeXML(w http.ResponseWriter, status int, v any) {
	body, err := xml.Marshal(v)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/xml")
	w.WriteHeader(status)
	if _, err := w.Write(append([]byte(xml.Header), body...)); err != nil {
		log.Printf("fakeaws: 応答を書けません: %v", err)
	}
}

// objectOnly は、オブジェクトの1つを読み書きする要求だけを next に渡し、ほかの S3 の操作は 501 で断る。
// キーが空の要求(バケットの一覧など)と、署名の値と SDK が付ける x-id のほかの問い合わせの値を持つ要求
// (タグや ACL の操作など)は、受けると決めていない操作である。
func (s *Server) objectOnly(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.PathValue("key") == "" {
			s.notImplemented(w, r)
			return
		}
		for name := range r.URL.Query() {
			if name != "x-id" && !strings.HasPrefix(strings.ToLower(name), "x-amz-") {
				s.notImplemented(w, r)
				return
			}
		}
		next(w, r)
	}
}
