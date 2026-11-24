package resume

import (
	"context"
	"errors"
	"strings"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
	"github.com/google/uuid"
)

// errRestoreServer は、戻すファイルの経歴書が無いか、6つの欄のどれかの並びに値の無い要素があるときの誤りである。
// Java 版はサーバの誤りとして 500 で答える。
var errRestoreServer = errors.New("resume: 戻すファイルの経歴書が無いか、欄の並びに値の無い要素がある")

// RestoreResume は、バックアップのファイルの本文 body から、利用者 userID の経歴書を1件作る。Java 版の RestoreResumeUseCase の写しである。
// 確かめる順は Java 版と同じく、本文、値の無い要素を持つ欄、ファイルの版、経歴書の数の上限、経歴書の中身、名前の重なり、値の決まりである。
// 経歴書の数を数えてから経歴書を入れるまでを、CreateResume と同じく1つのトランザクションで行う。
// トランザクションの誤りが 400 の誤りでなければ、利用者が居るかを調べ、退会して居なければ無い経歴書の誤りを返す。
// 返す経歴書は、データベースに入れる字に直す前の値である。
func (s *Service) RestoreResume(ctx context.Context, userID uuid.UUID, body []byte) (Resume, error) {
	f, ok := readRestoreFile(body)
	if !ok {
		return Resume{}, errUnreadableInput()
	}
	now := s.deps.Now().In(japanZone)
	var restored Resume
	err := inTx(ctx, s.deps.Pool, func(st store) error {
		if f.nullElement {
			return errRestoreServer
		}
		if f.version == nil || *f.version != backupVersion {
			return auth.ErrBusiness(MessageUnsupportedBackupVersion)
		}
		count, err := st.countResumes(ctx, userID)
		if err != nil {
			return err
		}
		if e := resumeLimit.check(count); e != nil {
			return e
		}
		if f.resume == nil {
			return errRestoreServer
		}
		// データベースの経歴書の名前は対になっていないサロゲートを含まないので、そのような名前は重ならない
		if name := f.resume.name; name != nil && toDBText(*name) == *name {
			if exists, err := st.resumeNameExists(ctx, userID, *name); err != nil {
				return err
			} else if exists {
				return errResumeNameDuplicated()
			}
		}
		r, ok := buildRestored(f.resume, userID)
		if !ok {
			return auth.ErrBusiness(MessageInvalidBackupFile)
		}
		r.CreatedAt, r.UpdatedAt = now, now
		if err := st.insertResume(ctx, dbResume(r)); err != nil {
			return err
		}
		restored = r
		return nil
	})
	if err != nil {
		var ae *auth.Error
		if !errors.As(err, &ae) {
			if exists, lookupErr := poolStore(s.deps.Pool).userExists(ctx, userID); lookupErr == nil && !exists {
				return Resume{}, errResumeNotFound()
			}
		}
		return Resume{}, err
	}
	return restored, nil
}

// buildRestored は、戻すファイルの経歴書 rr から、要求を送った利用者 userID の経歴書を作る。rr の値が、Java 版が戻すときに
// 経歴書と項目のクラスを作って確かめる値の決まり(RestoreResumeUseCase の 97-138行と、ResumeName、FullName、Period、Link などの
// クラス)を1つでも満たさなければ、false を返す。長さは、Java の String.length と同じく javaLen で UTF-16 の単位で数える。
// 年月の範囲、職歴の期間の重なり、リンクの長さ、欄ごとの項目の数は、Java 版の戻しと同じく確かめない。
// 経歴書と項目には新しい ID を付け、最後に sortEntries で項目を並べる。字は WTF-8 のまま写し、作った日時と直した日時は付けない。
// rr と6つの欄の要素は nil でないこと。
func buildRestored(rr *rsResume, userID uuid.UUID) (Resume, bool) {
	b := restoreBuilder{ok: true}
	r := Resume{
		ID:             uuid.New(),
		UserID:         userID,
		Name:           b.resumeName(rr.name),
		Careers:        make([]Career, 0, len(rr.careers)),
		Projects:       make([]Project, 0, len(rr.projects)),
		Certifications: make([]Certification, 0, len(rr.certifications)),
		Portfolios:     make([]Portfolio, 0, len(rr.portfolios)),
		SnsPlatforms:   make([]SnsPlatform, 0, len(rr.snsPlatforms)),
		SelfPromotions: make([]SelfPromotion, 0, len(rr.selfPromotions)),
	}
	if rr.date == nil {
		b.ok = false
	} else {
		r.Date = *rr.date
	}
	r.LastName, r.FirstName = b.fullName(rr.lastName, rr.firstName)
	for _, c := range rr.careers {
		r.Careers = append(r.Careers, Career{
			ID:          uuid.New(),
			CompanyName: b.text(c.companyName, companyNameMaxLength),
			Period:      b.period(c.startDate, c.endDate, c.active),
		})
	}
	for _, p := range rr.projects {
		r.Projects = append(r.Projects, Project{
			ID:          uuid.New(),
			CompanyName: b.text(p.companyName, companyNameMaxLength),
			Period:      b.period(p.startDate, p.endDate, p.active),
			Name:        b.text(p.name, projectNameMaxLength),
			Overview:    b.text(p.overview, longTextMaxLength),
			TeamComp:    b.text(p.teamComp, teamCompMaxLength),
			Role:        b.text(p.role, longTextMaxLength),
			Achievement: b.text(p.achievement, longTextMaxLength),
			Process:     p.process,
			TechStack:   p.techStack,
		})
	}
	for _, c := range rr.certifications {
		e := Certification{ID: uuid.New(), Name: b.text(c.name, certificationNameMaxLength)}
		if c.date == nil {
			b.ok = false
		} else {
			e.Date = *c.date
		}
		r.Certifications = append(r.Certifications, e)
	}
	for _, p := range rr.portfolios {
		if p.techStack != nil && javaLen(*p.techStack) > longTextMaxLength {
			b.ok = false
		}
		r.Portfolios = append(r.Portfolios, Portfolio{
			ID:        uuid.New(),
			Name:      b.text(p.name, portfolioNameMaxLength),
			Overview:  b.text(p.overview, longTextMaxLength),
			TechStack: p.techStack,
			Link:      b.link(p.link),
		})
	}
	for _, s := range rr.snsPlatforms {
		r.SnsPlatforms = append(r.SnsPlatforms, SnsPlatform{
			ID:   uuid.New(),
			Name: b.text(s.name, snsPlatformNameMaxLength),
			Link: b.link(s.link),
		})
	}
	for _, s := range rr.selfPromotions {
		r.SelfPromotions = append(r.SelfPromotions, SelfPromotion{
			ID:      uuid.New(),
			Title:   b.text(s.title, selfPromotionTitleMaxLength),
			Content: b.text(s.content, longTextMaxLength),
		})
	}
	if !b.ok {
		return Resume{}, false
	}
	sortEntries(&r)
	return r, true
}

// restoreBuilder は、buildRestored が値を1つずつ確かめるときに、決まりを満たさない値があったかを覚える。
type restoreBuilder struct {
	ok bool
}

// text は、空白だけでなく長さが limit 以下であるべき字 s を確かめ、字を返す。
func (b *restoreBuilder) text(s *string, limit int) string {
	if s == nil || !auth.NotBlank(*s) || javaLen(*s) > limit {
		b.ok = false
		return ""
	}
	return *s
}

// resumeName は、経歴書の名前 s を Java 版の ResumeName の決まりで確かめる。Java 版は正規表現 .*[...].* で照らすので、
// 5つの改行の文字のどれかを含む名前では、使えない文字を断らない。
func (b *restoreBuilder) resumeName(s *string) string {
	name := b.text(s, resumeNameMaxLength)
	if strings.ContainsAny(name, resumeNameInvalidChars) && !strings.ContainsAny(name, resumeNameLineTerminators) {
		b.ok = false
	}
	if strings.HasPrefix(name, ".") || strings.HasSuffix(name, ".") {
		b.ok = false
	}
	return name
}

// fullName は、姓と名を Java 版の FullName の決まりで確かめる。両方が無いか空白だけなら、氏名の無い経歴書にする。
func (b *restoreBuilder) fullName(lastName, firstName *string) (*string, *string) {
	blank := func(s *string) bool { return s == nil || !auth.NotBlank(*s) }
	if blank(lastName) && blank(firstName) {
		return nil, nil
	}
	return b.personName(lastName), b.personName(firstName)
}

func (b *restoreBuilder) personName(s *string) *string {
	name := b.text(s, personNameMaxLength)
	if !isPersonName(name) {
		b.ok = false
	}
	return &name
}

// period は、期間を Java 版の Period の決まりで確かめる。始まりの年月があること、続いていなければ終わりの年月があって
// 始まりの年月より前でないこと、続いていれば終わりの年月が無いこと。
func (b *restoreBuilder) period(start, end *YearMonth, active bool) Period {
	if start == nil || !active && (end == nil || start.after(*end)) || active && end != nil {
		b.ok = false
		return Period{}
	}
	return Period{StartDate: *start, EndDate: end, Active: active}
}

// link は、リンクを Java 版の Link の決まりで確かめる。空白だけでなく、URI として読め、スキームが ASCII の大文字と小文字を
// 区別せずに https であること。
func (b *restoreBuilder) link(s *string) string {
	if s == nil || !auth.NotBlank(*s) {
		b.ok = false
		return ""
	}
	scheme, ok := parseJavaURI(wtf8Units(*s))
	if !ok || !equalsIgnoreCaseASCII(scheme, "https") {
		b.ok = false
	}
	return *s
}
