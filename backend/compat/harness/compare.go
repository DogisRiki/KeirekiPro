//go:build compat

package harness

import (
	"bytes"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"mime"
	"net/http"
	"reflect"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/DogisRiki/KeirekiPro/backend/compat/fakeaws"
)

// 比べるものの名前である。変えた動きの一覧の match の target と同じ名前にしている。
// Markdown の本文は、ほかの本文と同じく TargetBody で報告する。
const (
	TargetStatus = "status"
	TargetHeader = "header"
	TargetBody   = "body"
	TargetPDF    = "pdf"
	TargetDB     = "db"
	TargetRedis  = "redis"
	TargetS3     = "s3"
	TargetMail   = "mail"
)

// absent は、片方の版に値が無いことを報告に書くときの記号である。
const absent = "(無し)"

// RedisTTLTolerance は、Redis の残りの有効な時間の比べで許すずれである。
const RedisTTLTolerance = 5 * time.Second

// StepRef は、違いが見つかった段である。
type StepRef struct {
	// Index は、筋書きの中の段の順番である。1から数える。
	Index int
	Name  string
	// Operation は、段が呼ぶ仕様書の操作の名前(operationId)である。変えた動きの一覧の match が使う。
	Operation string
	// JavaStatus と GoStatus は、段の応答のステータスである。status を書いた match が使う。
	JavaStatus int
	GoStatus   int
}

// Diff は、Java 版と Go 版の値の1つの違いである。
type Diff struct {
	Scenario string
	Step     StepRef
	// Target は、比べたもの(TargetStatus など)である。
	Target string
	// Path は、比べたものの中の場所である。本文なら JSON の場所、ヘッダならヘッダの名前、データベースなら表の名前である。
	Path string
	Java string
	Go   string
	// repeatKey は、前の段と同じ違いかを見分けるときに、両方の値の代わりに使う文字である。空なら両方の値を使う。
	repeatKey string
}

// Response は、1つの版の応答である。
type Response struct {
	Status int
	Header http.Header
	Body   []byte
	// Received は、harness が応答を読み終えた時刻である。メールアドレスの確認のリンクの lexp を、この時刻との差で比べる。
	// 偽の AWS が覚えたメールには時刻が無いので、harness が自分で持つ時刻を基準にする。
	Received time.Time
}

// PDFComparer は、2つの PDF を比べ、違いの説明と、許す幅に収まるかを返す。pdfcmp が実装する。
type PDFComparer func(java, goPDF []byte) (javaDetail, goDetail string, same bool, err error)

// Comparer は、1つの筋書きの比べを受け持つ。版ごとに Normalizer を持ち、筋書きの段をまたいで同じ番号を使う。
// 違いが見つかっても止まらず、筋書きの終わりに Report でまとめて返す。
type Comparer struct {
	Scenario string
	// PDF は、PDF の本文の比べ方である。nil のときは、PDF の本文を比べられないことを違いとして報告する。
	PDF PDFComparer
	// Behaviors は、変えた動きの一覧である。一覧の match に当たる違いは、報告で止める違いにしない。
	Behaviors []ChangedBehavior

	java  *Normalizer
	goVer *Normalizer
	diffs []Diff
}

// NewComparer は、筋書き scenario の比べを始める。
func NewComparer(scenario string) *Comparer {
	return &Comparer{Scenario: scenario, java: NewNormalizer(), goVer: NewNormalizer()}
}

func (c *Comparer) add(step StepRef, target, path, java, goValue string) {
	c.diffs = append(c.diffs, Diff{Scenario: c.Scenario, Step: step, Target: target, Path: path, Java: java, Go: goValue})
}

// CompareResponse は、段の応答のステータスとヘッダと本文を比べる。step の JavaStatus と GoStatus は、応答の値で埋める。
// 応答を受けた時刻は、版ごとに、JWT の lexp を差にするときの基準にする。
func (c *Comparer) CompareResponse(step StepRef, java, goResp Response) StepRef {
	c.java.received, c.goVer.received = java.Received, goResp.Received
	step.JavaStatus, step.GoStatus = java.Status, goResp.Status
	if java.Status != goResp.Status {
		c.add(step, TargetStatus, "", strconv.Itoa(java.Status), strconv.Itoa(goResp.Status))
	}
	c.compareHeaders(step, java.Header, goResp.Header)
	c.compareBody(step, java.Header.Get("Content-Type"), java.Body, goResp.Body)
	return step
}

// comparedHeaders は、値をそのまま比べるヘッダである。Set-Cookie は別に、Cookie の名前と性質だけを比べる。
var comparedHeaders = []string{"Content-Type", "Content-Disposition", "Cache-Control", "Location"}

func (c *Comparer) compareHeaders(step StepRef, java, goHeader http.Header) {
	for _, name := range comparedHeaders {
		j := c.headerValue(c.java, name, java.Values(name))
		g := c.headerValue(c.goVer, name, goHeader.Values(name))
		if j != g {
			c.add(step, TargetHeader, name, j, g)
		}
	}
	j, g := cookieShapes(java.Values("Set-Cookie")), cookieShapes(goHeader.Values("Set-Cookie"))
	if j != g {
		c.add(step, TargetHeader, "Set-Cookie", j, g)
	}
}

// headerValue は、ヘッダの値を比べる形にする。Location の URL の中のトークンも置き換える。
func (c *Comparer) headerValue(n *Normalizer, name string, values []string) string {
	if len(values) == 0 {
		return absent
	}
	out := make([]string, len(values))
	for i, v := range values {
		v = n.Text(v)
		if name == "Location" {
			v = n.URLs(v)
		}
		out[i] = v
	}
	return strings.Join(out, "\n")
}

// cookieAttributes は、比べる Cookie の性質を、報告に書く順に並べたものである。
var cookieAttributes = []string{"Path", "Max-Age", "HttpOnly", "Secure", "SameSite"}

// cookieShapes は、Set-Cookie の行を、Cookie の名前と比べる性質だけにして、名前の順に並べる。
// Cookie の値と Expires と Domain は比べない。性質の名前の大文字と小文字は区別しない。
func cookieShapes(lines []string) string {
	if len(lines) == 0 {
		return absent
	}
	shapes := make([]string, 0, len(lines))
	for _, line := range lines {
		parts := strings.Split(line, ";")
		name, _, _ := strings.Cut(strings.TrimSpace(parts[0]), "=")
		attrs := map[string]string{}
		for _, p := range parts[1:] {
			k, v, hasValue := strings.Cut(strings.TrimSpace(p), "=")
			for _, known := range cookieAttributes {
				if strings.EqualFold(k, known) {
					if hasValue {
						attrs[known] = known + "=" + v
					} else {
						attrs[known] = known
					}
				}
			}
		}
		shape := []string{name}
		for _, known := range cookieAttributes {
			if a, ok := attrs[known]; ok {
				shape = append(shape, a)
			}
		}
		shapes = append(shapes, strings.Join(shape, "; "))
	}
	slices.Sort(shapes)
	return strings.Join(shapes, "\n")
}

// compareBody は、本文を Content-Type で選んだ比べ方で比べる。Content-Type の違いは、ヘッダの比べで報告する。
func (c *Comparer) compareBody(step StepRef, contentType string, java, goBody []byte) {
	if len(java) == 0 && len(goBody) == 0 {
		return
	}
	mediaType, _, err := mime.ParseMediaType(contentType)
	if err != nil {
		mediaType = ""
	}
	switch {
	case mediaType == "application/json" || strings.HasSuffix(mediaType, "+json"):
		c.compareJSON(step, java, goBody)
	case mediaType == "application/pdf":
		c.comparePDF(step, java, goBody)
	case strings.HasPrefix(mediaType, "text/"):
		c.compareText(step, java, goBody)
	default:
		if !bytes.Equal(java, goBody) {
			c.add(step, TargetBody, "", describeBytes(java), describeBytes(goBody))
		}
	}
}

func describeBytes(b []byte) string {
	sum := sha256.Sum256(b)
	return fmt.Sprintf("%d バイト sha256:%x", len(b), sum)
}

// compareJSON は、JSON の本文を、解析して正規化した値で比べ、違う場所ごとに違いを報告する。
// 片方でも JSON として読めないときは、正規化した文字列のまま比べる。
func (c *Comparer) compareJSON(step StepRef, java, goBody []byte) {
	jv, jerr := decodeJSON(java)
	gv, gerr := decodeJSON(goBody)
	if jerr != nil || gerr != nil {
		c.compareText(step, java, goBody)
		return
	}
	sortOrderOnly(c.Behaviors, step, c.java, jv)
	sortOrderOnly(c.Behaviors, step, c.goVer, gv)
	diffJSON("$", c.java.value(jv, true), c.goVer.value(gv, true), func(path string, j, g any) {
		c.add(step, TargetBody, path, describeJSON(j), describeJSON(g))
	})
}

func decodeJSON(b []byte) (any, error) {
	dec := json.NewDecoder(bytes.NewReader(b))
	dec.UseNumber()
	var v any
	if err := dec.Decode(&v); err != nil {
		return nil, err
	}
	if dec.More() {
		return nil, fmt.Errorf("JSON の値のあとに続きがあります")
	}
	return v, nil
}

// missing は、JSON のオブジェクトに項目が無いことを表す。
type missing struct{}

func describeJSON(v any) string {
	if _, ok := v.(missing); ok {
		return absent
	}
	return canonicalJSON(v)
}

var plainKey = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*$`)

// diffJSON は、2つの値を比べ、違う場所ごとに emit を呼ぶ。配列の長さが違うときは、配列ごと1つの違いにする。
func diffJSON(path string, j, g any, emit func(path string, j, g any)) {
	jm, jIsMap := j.(map[string]any)
	gm, gIsMap := g.(map[string]any)
	if jIsMap && gIsMap {
		keys := sortedKeys(jm)
		for _, k := range sortedKeys(gm) {
			if _, ok := jm[k]; !ok {
				keys = append(keys, k)
			}
		}
		slices.Sort(keys)
		for _, k := range keys {
			child := path + "." + k
			if !plainKey.MatchString(k) {
				child = path + "[" + strconv.Quote(k) + "]"
			}
			jv, jok := jm[k]
			gv, gok := gm[k]
			switch {
			case !jok:
				emit(child, missing{}, gv)
			case !gok:
				emit(child, jv, missing{})
			default:
				diffJSON(child, jv, gv, emit)
			}
		}
		return
	}
	ja, jIsArr := j.([]any)
	ga, gIsArr := g.([]any)
	if jIsArr && gIsArr && len(ja) == len(ga) {
		for i := range ja {
			diffJSON(fmt.Sprintf("%s[%d]", path, i), ja[i], ga[i], emit)
		}
		return
	}
	if !reflect.DeepEqual(j, g) {
		emit(path, j, g)
	}
}

// compareText は、Markdown のような文字の本文を、UUID と日時と、Location と同じく URL の中のトークンを置き換えてから、
// 1文字も違わないかで比べる。Java 版のログインの開始の応答は、開始の URL をそのまま本文にした文字列で、state と
// code_challenge に版ごとに違う乱数を含むためである。違うときは、最初に違う行を報告する。
func (c *Comparer) compareText(step StepRef, java, goBody []byte) {
	j := strings.Split(c.java.URLs(c.java.Text(string(java))), "\n")
	g := strings.Split(c.goVer.URLs(c.goVer.Text(string(goBody))), "\n")
	for i := 0; i < max(len(j), len(g)); i++ {
		jl, gl := absent, absent
		if i < len(j) {
			jl = strconv.Quote(j[i])
		}
		if i < len(g) {
			gl = strconv.Quote(g[i])
		}
		if jl != gl {
			c.add(step, TargetBody, fmt.Sprintf("%d 行目", i+1), jl, gl)
			return
		}
	}
}

func (c *Comparer) comparePDF(step StepRef, java, goBody []byte) {
	if c.PDF == nil {
		c.add(step, TargetPDF, "", "PDF の比べ方が設定されていません: "+describeBytes(java), describeBytes(goBody))
		return
	}
	j, g, same, err := c.PDF(java, goBody)
	switch {
	case err != nil:
		c.add(step, TargetPDF, "", "PDF を比べられません: "+err.Error(), describeBytes(goBody))
	case !same:
		c.add(step, TargetPDF, "", j, g)
	}
}

// DBSnapshot は、データベースの表の名前ごとの、すべての行である。1つの行は、列の名前と値の組である。
type DBSnapshot map[string][]map[string]any

// CompareDB は、データベースのすべての表のすべての行を、UUID と日時を置き換えてから、置き換えたあとの値で並べ替えて比べる。
// 応答に現れた UUID は応答と同じ番号に、応答に現れない UUID は行のほかの列の値の順の番号に置き換える。
// 表ごとに、片方の版にしか無い行を1つの違いにして報告する。
func (c *Comparer) CompareDB(step StepRef, java, goDB DBSnapshot) {
	tables := sortedKeys(java)
	for _, name := range sortedKeys(goDB) {
		if _, ok := java[name]; !ok {
			tables = append(tables, name)
		}
	}
	slices.Sort(tables)
	for _, table := range tables {
		jRows, jok := java[table]
		gRows, gok := goDB[table]
		if !jok || !gok {
			c.add(step, TargetDB, table, tablePresence(jok), tablePresence(gok))
			continue
		}
		j := rowTexts(c.java, jRows)
		g := rowTexts(c.goVer, gRows)
		onlyJ, onlyG := sortedDifference(j, g)
		if len(onlyJ) > 0 || len(onlyG) > 0 {
			c.add(step, TargetDB, table, joinOrAbsent(onlyJ), joinOrAbsent(onlyG))
		}
	}
}

func tablePresence(ok bool) string {
	if ok {
		return "表がある"
	}
	return "表が無い"
}

func rowTexts(n *Normalizer, rows []map[string]any) []string {
	records := normalizeRecords(rows, func(row map[string]any, assign bool) string {
		return canonicalJSON(n.value(row, assign))
	})
	out := make([]string, len(records))
	for i, r := range records {
		out[i] = r.Text
	}
	return out
}

// sortedDifference は、並べ替えた2つの並びを多重集合として比べ、片方にしか無いものを返す。
func sortedDifference(a, b []string) (onlyA, onlyB []string) {
	i, k := 0, 0
	for i < len(a) || k < len(b) {
		switch {
		case k == len(b) || (i < len(a) && a[i] < b[k]):
			onlyA = append(onlyA, a[i])
			i++
		case i == len(a) || b[k] < a[i]:
			onlyB = append(onlyB, b[k])
			k++
		default:
			i++
			k++
		}
	}
	return onlyA, onlyB
}

func joinOrAbsent(lines []string) string {
	if len(lines) == 0 {
		return absent
	}
	return strings.Join(lines, "\n")
}

// RedisEntry は、Redis の1つのキーである。
type RedisEntry struct {
	Key  string
	Type string
	// Value は、型ごとに文字の形にした値である(DumpRedis を見よ)。
	Value string
	// TTL は、残りの有効な時間である。有効な時間の無いキーは負の値である。
	TTL time.Duration
}

// redisSeps は、Redis のキーと値を、トークンかを調べる語に分ける区切りである。
// 逆斜線を含めるのは、集合の値が、JSON の文字列の要素を JSON の配列にした形(["\"値\""])で、値の後ろに逆斜線が続くためである。
const redisSeps = ":\"'{}[],= \t\n&/?\\"

// CompareRedis は、Redis のキーの名前と型と値を比べ、残りの有効な時間は RedisTTLTolerance のずれを許して比べる。
// 有効な時間の有無は、同じでなければならない。
func (c *Comparer) CompareRedis(step StepRef, java, goEntries []RedisEntry) {
	j := redisByKey(c.java, java)
	g := redisByKey(c.goVer, goEntries)
	keys := sortedKeys(j)
	for _, k := range sortedKeys(g) {
		if _, ok := j[k]; !ok {
			keys = append(keys, k)
		}
	}
	slices.Sort(keys)
	for _, k := range keys {
		je, jok := j[k]
		ge, gok := g[k]
		switch {
		case !jok:
			c.addRedis(step, k, nil, &ge)
		case !gok:
			c.addRedis(step, k, &je, nil)
		case je.Type != ge.Type || je.Value != ge.Value || !ttlClose(je.TTL, ge.TTL):
			c.addRedis(step, k, &je, &ge)
		}
	}
}

// addRedis は、キー key の Redis の違いを足す。無い側は nil で渡す。
// 残りの有効な時間は段が進むたびに減るので、前の段と同じ違いかは、時間の有無だけを残した値で見分ける。
func (c *Comparer) addRedis(step StepRef, key string, java, goEntry *RedisEntry) {
	describe := func(e *RedisEntry) (string, string) {
		if e == nil {
			return absent, absent
		}
		return e.describe(), e.withoutTTL()
	}
	j, jKey := describe(java)
	g, gKey := describe(goEntry)
	c.add(step, TargetRedis, key, j, g)
	c.diffs[len(c.diffs)-1].repeatKey = jKey + "\x00" + gKey
}

// withoutTTL は、describe から残りの有効な時間の長さを除いた文字を返す。
func (e RedisEntry) withoutTTL() string {
	if e.TTL >= 0 {
		return e.Type + " " + e.Value + " (有効な時間あり)"
	}
	return e.Type + " " + e.Value + " (有効な時間なし)"
}

func (e RedisEntry) describe() string {
	ttl := "有効な時間なし"
	if e.TTL >= 0 {
		ttl = "残り " + e.TTL.String()
	}
	return e.Type + " " + e.Value + " (" + ttl + ")"
}

func ttlClose(a, b time.Duration) bool {
	if a < 0 || b < 0 {
		return a < 0 && b < 0
	}
	d := a - b
	return d <= RedisTTLTolerance && d >= -RedisTTLTolerance
}

// redisByKey は、Redis のキーと値を正規化し、正規化したキーごとに返す。
func redisByKey(n *Normalizer, entries []RedisEntry) map[string]RedisEntry {
	records := normalizeRecords(entries, func(e RedisEntry, assign bool) string {
		return n.words(e.Key, redisSeps, assign) + "\n" + e.Type + "\n" + sortedSetValue(e.Type, n.words(n.redisValue(e.Key, e.Value, assign), redisSeps, assign))
	})
	out := make(map[string]RedisEntry, len(records))
	for _, r := range records {
		key, rest, _ := strings.Cut(r.Text, "\n")
		typ, value, _ := strings.Cut(rest, "\n")
		key = uniqueKey(out, key)
		out[key] = RedisEntry{Key: key, Type: typ, Value: value, TTL: entries[r.Index].TTL}
	}
	return out
}

// sortedSetValue は、型 typ が集合のときに、正規化した値 value(JSON の文字列の配列)の要素を並べ替えて返す。
// DumpRedis は要素を置き換える前の値の順に並べるが、トークンの番号は現れた順に付くので、置き換えたあとの順は版ごとに違いうる。
// 集合の要素には順が無いので、並べ替えても違いを隠さない。
func sortedSetValue(typ, value string) string {
	var members []string
	if typ != "set" || json.Unmarshal([]byte(value), &members) != nil {
		return value
	}
	slices.Sort(members)
	return canonicalJSON(members)
}

// CompareS3 は、S3 のオブジェクトのキーの形と中身のバイトを比べる。キーの中の UUID は番号に置き換える。
func (c *Comparer) CompareS3(step StepRef, java, goObjects []fakeaws.Object) {
	j := objectsByKey(c.java, java)
	g := objectsByKey(c.goVer, goObjects)
	keys := sortedKeys(j)
	for _, k := range sortedKeys(g) {
		if _, ok := j[k]; !ok {
			keys = append(keys, k)
		}
	}
	slices.Sort(keys)
	for _, k := range keys {
		jb, jok := j[k]
		gb, gok := g[k]
		switch {
		case !jok:
			c.add(step, TargetS3, k, absent, describeBytes(gb))
		case !gok:
			c.add(step, TargetS3, k, describeBytes(jb), absent)
		case !bytes.Equal(jb, gb):
			c.add(step, TargetS3, k, describeBytes(jb), describeBytes(gb))
		}
	}
}

func objectsByKey(n *Normalizer, objects []fakeaws.Object) map[string][]byte {
	records := normalizeRecords(objects, func(o fakeaws.Object, assign bool) string {
		sum := sha256.Sum256(o.Body)
		return n.uuidsIn(o.Bucket+"/"+o.Key, assign) + fmt.Sprintf("\n%x", sum)
	})
	out := make(map[string][]byte, len(records))
	for _, r := range records {
		key, _, _ := strings.Cut(r.Text, "\n")
		key = uniqueKey(out, key)
		out[key] = objects[r.Index].Body
	}
	return out
}

// uniqueKey は、正規化したあとのキーが、すでに置いたキーと重なるとき、重なった順の番号を付けたキーを返す。
// 重なった記録を上書きして黙って捨てると、片方の版にだけある記録を見逃すためである。
func uniqueKey[V any](m map[string]V, key string) string {
	if _, ok := m[key]; !ok {
		return key
	}
	for i := 2; ; i++ {
		k := fmt.Sprintf("%s (同じ形の %d 個目)", key, i)
		if _, ok := m[k]; !ok {
			return k
		}
	}
}

// CompareMail は、送ったメールを送った順に比べる。送り元と宛先と件名と本文を比べ、本文の URL の中のトークンは記号に置き換える。
func (c *Comparer) CompareMail(step StepRef, java, goMails []fakeaws.Email) {
	for i := 0; i < max(len(java), len(goMails)); i++ {
		path := fmt.Sprintf("%d 通目", i+1)
		switch {
		case i >= len(java):
			c.add(step, TargetMail, path, absent, describeMail(c.goVer, goMails[i], i))
			continue
		case i >= len(goMails):
			c.add(step, TargetMail, path, describeMail(c.java, java[i], i), absent)
			continue
		}
		jf, gf := mailFields(c.java, java[i], i), mailFields(c.goVer, goMails[i], i)
		for f := range jf {
			if !sameNormalized(jf[f].value, gf[f].value) {
				c.add(step, TargetMail, path+"の"+jf[f].name, jf[f].value, gf[f].value)
			}
		}
	}
}

// sameNormalized は、正規化した2つの文字が同じかを返す。JWT の lexp の差は、Redis の残りの有効な時間と同じく
// RedisTTLTolerance のずれを許す。版ごとに、メールを送ってから応答を受けるまでの時間が違うためである。
func sameNormalized(j, g string) bool {
	if j == g {
		return true
	}
	if lexpMarkerPattern.ReplaceAllString(j, "<lexp>") != lexpMarkerPattern.ReplaceAllString(g, "<lexp>") {
		return false
	}
	jm, gm := lexpMarkerPattern.FindAllStringSubmatch(j, -1), lexpMarkerPattern.FindAllStringSubmatch(g, -1)
	tolerance := int64(RedisTTLTolerance / time.Second)
	for i := range jm {
		a, errA := strconv.ParseInt(jm[i][1], 10, 64)
		b, errB := strconv.ParseInt(gm[i][1], 10, 64)
		if errA != nil || errB != nil || a-b > tolerance || b-a > tolerance {
			return false
		}
	}
	return true
}

type mailField struct{ name, value string }

// mailFields は、i 通目のメール m の比べる項目を、正規化して返す。
func mailFields(n *Normalizer, m fakeaws.Email, i int) []mailField {
	var fields []mailField
	n.atMail(i, func() {
		fields = []mailField{
			{"送り元", m.Source},
			{"宛先", strings.Join(m.To, ", ")},
			{"Cc", strings.Join(m.Cc, ", ")},
			{"Bcc", strings.Join(m.Bcc, ", ")},
			{"返信先", strings.Join(m.ReplyTo, ", ")},
			{"件名", m.Subject},
			{"本文", n.URLs(n.mailText(m.Subject, m.Text))},
			{"HTML の本文", n.URLs(m.HTML)},
		}
	})
	return fields
}

func describeMail(n *Normalizer, m fakeaws.Email, i int) string {
	lines := make([]string, 0, 8)
	for _, f := range mailFields(n, m, i) {
		lines = append(lines, f.name+": "+f.value)
	}
	return strings.Join(lines, "\n")
}

// Diffs は、これまでに見つけた違いを、見つけた順に返す。
func (c *Comparer) Diffs() []Diff {
	return slices.Clone(c.diffs)
}
