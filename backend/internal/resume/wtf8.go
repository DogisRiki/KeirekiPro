package resume

import (
	"slices"
	"strings"
	"unicode/utf16"
)

// wtf8Units は、WTF-8 の字 s を、Java の文字列と同じ UTF-16 の単位の並びにする。BMP の外の字はサロゲートの組の2つの単位に、
// 対になっていないサロゲートの3バイトはそのサロゲートの1つの単位にする。UTF-8 として読めないバイトは、1バイトずつ U+FFFD の
// 1つの単位にする。parseJTree が作る字は、UTF-8 として読めないバイトを持たない。
func wtf8Units(s string) []uint16 {
	units := make([]uint16, 0, len(s))
	for len(s) > 0 {
		r, n := decodeWTF8(s)
		s = s[n:]
		if r >= 0x10000 {
			hi, lo := utf16.EncodeRune(r)
			units = append(units, uint16(hi&0xFFFF), uint16(lo&0xFFFF))
			continue
		}
		units = append(units, uint16(r&0xFFFF))
	}
	return units
}

// javaLen は、WTF-8 の字 s の長さを、Java の String.length と同じ UTF-16 の単位の数で返す。BMP の外の字を2、
// 対になっていないサロゲートを1と数える。
func javaLen(s string) int {
	return len(wtf8Units(s))
}

// toDBText は、WTF-8 の字 s の対になっていないサロゲートを1つずつ ? にして、データベースに入れる字にする。
// PostgreSQL の UTF-8 の列は、対になっていないサロゲートを入れられない。Java 版は、対になっていないサロゲートを ? にした字を
// データベースに入れた(research.md の試作の記録)。ほかの字は変えない。
func toDBText(s string) string {
	var b strings.Builder
	b.Grow(len(s))
	for len(s) > 0 {
		r, n := decodeWTF8(s)
		if utf16.IsSurrogate(r) {
			b.WriteByte('?')
		} else {
			b.WriteString(s[:n])
		}
		s = s[n:]
	}
	return b.String()
}

// dbTextPtr は、字のポインタ s の指す字に toDBText を当てた字のポインタを返す。s が nil なら nil を返す。
func dbTextPtr(s *string) *string {
	if s == nil {
		return nil
	}
	t := toDBText(*s)
	return &t
}

// dbEntries は、項目の並び entries を写し、写した要素ごとに fix を当てる。entries が nil なら nil を返し、空なら空の並びを返す。
// 渡された並びは変えない。
func dbEntries[E any](entries []E, fix func(*E)) []E {
	if entries == nil {
		return nil
	}
	out := slices.Clone(entries)
	for i := range out {
		fix(&out[i])
	}
	return out
}

// dbTechStack は、技術スタックの35の並びの要素に toDBText を当てた技術スタックを返す。nil の並びと並びの nil の要素は、
// nil のまま残す。データベースに書くときに、nil の並びは NULL に、空の並びは {} になるためである(store.go の encodeTechStack)。
func dbTechStack(t TechStack) TechStack {
	for _, c := range techStackColumns {
		f := c.field(&t)
		*f = dbEntries(*f, func(s **string) { *s = dbTextPtr(*s) })
	}
	return t
}

// dbResume は、経歴書 r と6つの欄の項目のすべての字の欄に toDBText を当てた経歴書を返す。渡された経歴書は変えない。
func dbResume(r Resume) Resume {
	r.Name = toDBText(r.Name)
	r.LastName = dbTextPtr(r.LastName)
	r.FirstName = dbTextPtr(r.FirstName)
	r.Careers = dbEntries(r.Careers, func(c *Career) {
		c.CompanyName = toDBText(c.CompanyName)
	})
	r.Projects = dbEntries(r.Projects, func(p *Project) {
		p.CompanyName = toDBText(p.CompanyName)
		p.Name = toDBText(p.Name)
		p.Overview = toDBText(p.Overview)
		p.TeamComp = toDBText(p.TeamComp)
		p.Role = toDBText(p.Role)
		p.Achievement = toDBText(p.Achievement)
		p.TechStack = dbTechStack(p.TechStack)
	})
	r.Certifications = dbEntries(r.Certifications, func(c *Certification) {
		c.Name = toDBText(c.Name)
	})
	r.Portfolios = dbEntries(r.Portfolios, func(p *Portfolio) {
		p.Name = toDBText(p.Name)
		p.Overview = toDBText(p.Overview)
		p.TechStack = dbTextPtr(p.TechStack)
		p.Link = toDBText(p.Link)
	})
	r.SnsPlatforms = dbEntries(r.SnsPlatforms, func(s *SnsPlatform) {
		s.Name = toDBText(s.Name)
		s.Link = toDBText(s.Link)
	})
	r.SelfPromotions = dbEntries(r.SelfPromotions, func(s *SelfPromotion) {
		s.Title = toDBText(s.Title)
		s.Content = toDBText(s.Content)
	})
	return r
}
