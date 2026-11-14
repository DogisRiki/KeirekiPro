//go:build compat

// Package fakeaws は、比べる検査で Java 版と Go 版がつなぐ AWS の代わりである。
//
// 1つの HTTP のサーバで、次の操作だけを受ける。署名と権限は調べない。
//   - S3 のパスの形の PutObject、GetObject、DeleteObject と、署名付きの URL の GetObject
//   - SES v1 の SendEmail(Query の形)
//   - Secrets Manager の GetSecretValue(JSON の形)
//
// 受けたオブジェクトとメールと、比べる検査が登録した秘密の値は、版ごとに分けて覚える。
// 版は、要求の宛先のホスト名で決める。比べる検査は、このサーバのコンテナに fakeaws-java と fakeaws-go の
// 名前を付け、Java 版を http://fakeaws-java:4566 に、Go 版を http://fakeaws-go:4566 につなぐ。
// fakeaws-<版> の形でないホスト名(版をまたぐ確認で両方の版がつなぐ fakeaws など)は、共有の版 SharedVersion とみなす。
//
// 比べる検査は、/_compat/ の下の口で、秘密の値を登録し、覚えたオブジェクトとメールを読み、記録を空にする。
// S3 のバケットの名前は _ で始まらないので、この口が S3 の要求と重なることは無い。
package fakeaws

import (
	"net"
	"net/http"
	"sort"
	"strings"
	"sync"
	"time"
)

const (
	// HostPrefix は、版を表すホスト名の始まりである。fakeaws-java なら版は java である。
	HostPrefix = "fakeaws-"
	// SharedVersion は、ホスト名が fakeaws-<版> の形でないときの版である。
	SharedVersion = "shared"
	// Port は、このサーバが受けるポートである。開発環境の LocalStack と同じ番号にしている。
	Port = "4566"
)

// Object は、S3 に置かれたオブジェクトである。
type Object struct {
	Bucket      string            `json:"bucket"`
	Key         string            `json:"key"`
	ContentType string            `json:"contentType"`
	Metadata    map[string]string `json:"metadata"`
	Body        []byte            `json:"body"`
	// LastModified は、比べる検査では比べない。GetObject の応答の Last-Modified に使う。
	LastModified time.Time `json:"-"`
}

// Email は、SES の SendEmail で受けたメールである。
type Email struct {
	Source  string   `json:"source"`
	To      []string `json:"to"`
	Cc      []string `json:"cc"`
	Bcc     []string `json:"bcc"`
	ReplyTo []string `json:"replyTo"`
	Subject string   `json:"subject"`
	Text    string   `json:"text"`
	HTML    string   `json:"html"`
}

// store は、1つの版の記録である。
type store struct {
	objects map[string]Object // キーは <バケット>/<キー>
	emails  []Email
	secrets map[string]string
}

// Server は、AWS の代わりの HTTP のサーバの処理である。
type Server struct {
	mux *http.ServeMux
	now func() time.Time

	mu       sync.Mutex
	versions map[string]*store
	sent     int
}

// NewServer は、何も覚えていない Server を作る。
func NewServer() *Server {
	s := &Server{now: time.Now, versions: map[string]*store{}}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /_compat/healthz", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) })
	mux.HandleFunc("PUT /_compat/{version}/secrets/{name...}", s.putSecret)
	mux.HandleFunc("GET /_compat/{version}/objects", s.listObjects)
	mux.HandleFunc("GET /_compat/{version}/emails", s.listEmails)
	mux.HandleFunc("DELETE /_compat/records", s.clearRecords)
	mux.HandleFunc("POST /{$}", s.postRoot)
	// 名前が空でないオブジェクトの要求は、ServeHTTP の objectHandler が先に受ける。
	// 次の3つが受けるのは、/<置き場所>/ のように画像の名前が空の要求だけで、objectOnly が 501 で断る
	mux.HandleFunc("PUT /{bucket}/{key...}", s.objectOnly(s.putObject))
	mux.HandleFunc("GET /{bucket}/{key...}", s.objectOnly(s.getObject))
	mux.HandleFunc("DELETE /{bucket}/{key...}", s.objectOnly(s.deleteObject))
	// 末尾に / の無いバケットの単位のパスを登録しないと、ServeMux が /{bucket}/ へ転送し、501 にならない
	mux.HandleFunc("/{bucket}", s.notImplemented)
	mux.HandleFunc("/", s.notImplemented)
	s.mux = mux
	return s
}

// ServeHTTP は、要求を操作ごとの処理に振り分ける。
// オブジェクトの1つを読み書きする要求は、ServeMux に渡す前に、objectHandler が振り分ける。
func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if h, ok := s.objectHandler(r); ok {
		h(w, r)
		return
	}
	s.mux.ServeHTTP(w, r)
}

// objectHandler は、オブジェクトの1つを読み書きする要求の、URL のパスをそのまま読み、
// 最初の / までを置き場所の名前に、残りを画像の名前にして、処理を返す。
// 名前が / で始まる画像の path-style の URL は、/<置き場所>//profile/image/... と // を含む。
// ServeMux は、// を含むパスを、/ を1つにしたパスへ移すように答えるので、この要求を ServeMux に渡さない。
// 置き場所の名前か画像の名前が空の要求と、/_compat/ で始まる要求は、ServeMux に任せる。
func (s *Server) objectHandler(r *http.Request) (http.HandlerFunc, bool) {
	var next http.HandlerFunc
	switch r.Method {
	case http.MethodPut:
		next = s.putObject
	case http.MethodGet, http.MethodHead:
		next = s.getObject
	case http.MethodDelete:
		next = s.deleteObject
	default:
		return nil, false
	}
	rest, ok := strings.CutPrefix(r.URL.Path, "/")
	if !ok {
		return nil, false
	}
	bucket, key, ok := strings.Cut(rest, "/")
	if !ok || bucket == "" || bucket == "_compat" || key == "" {
		return nil, false
	}
	r.SetPathValue("bucket", bucket)
	r.SetPathValue("key", key)
	return s.objectOnly(next), true
}

// versionOf は、要求の宛先のホスト名から版を決める。
func versionOf(r *http.Request) string {
	host := r.Host
	if h, _, err := net.SplitHostPort(host); err == nil {
		host = h
	}
	host = strings.ToLower(host)
	if v, ok := strings.CutPrefix(host, HostPrefix); ok && v != "" {
		return v
	}
	return SharedVersion
}

// storeOf は、版の記録を返す。無ければ作る。s.mu を持って呼ぶ。
func (s *Server) storeOf(version string) *store {
	st, ok := s.versions[version]
	if !ok {
		st = &store{objects: map[string]Object{}, secrets: map[string]string{}}
		s.versions[version] = st
	}
	return st
}

// Objects は、版が覚えているオブジェクトを、バケットとキーの順に並べて返す。
func (s *Server) Objects(version string) []Object {
	s.mu.Lock()
	defer s.mu.Unlock()
	st := s.storeOf(version)
	objects := make([]Object, 0, len(st.objects))
	for _, o := range st.objects {
		objects = append(objects, o)
	}
	sort.Slice(objects, func(i, j int) bool {
		if objects[i].Bucket != objects[j].Bucket {
			return objects[i].Bucket < objects[j].Bucket
		}
		return objects[i].Key < objects[j].Key
	})
	return objects
}

// Emails は、版が受けたメールを、受けた順に返す。
func (s *Server) Emails(version string) []Email {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]Email{}, s.storeOf(version).emails...)
}

// SetSecret は、版の Secrets Manager に秘密の値を登録する。
func (s *Server) SetSecret(version, name, value string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.storeOf(version).secrets[name] = value
}

// ClearRecords は、すべての版のオブジェクトとメールを消す。秘密の値は、起動の前に登録したものなので残す。
func (s *Server) ClearRecords() {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, st := range s.versions {
		st.objects = map[string]Object{}
		st.emails = nil
	}
}
