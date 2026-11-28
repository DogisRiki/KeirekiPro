package resume

import (
	"context"
	"errors"
	"strings"

	"github.com/google/uuid"

	"github.com/DogisRiki/KeirekiPro/backend/internal/auth"
)

// RestoreResume は、バックアップのファイルの本文 body から、利用者 userID の経歴書を1件作る。
// 確かめる順は、本文、ファイルの版、経歴書の数の上限、経歴書の中身があること、名前の重なり、値の決まりである。
// 経歴書の数を数えてから経歴書を入れるまでを、CreateResume と同じく1つのトランザクションで行う。
// トランザクションの誤りが 400 の誤りでなければ、利用者が居るかを調べ、退会して居なければ無い経歴書の誤りを返す。
func (s *Service) RestoreResume(ctx context.Context, userID uuid.UUID, body []byte) (Resume, error) {
	f, ok := readRestoreFile(body)
	if !ok {
		return Resume{}, errUnreadableInput()
	}
	now := s.deps.Now().In(japanZone)
	var restored Resume
	err := inTx(ctx, s.deps.Pool, func(st store) error {
		if f.Version == nil || *f.Version != backupVersion {
			return auth.ErrBusiness(MessageUnsupportedBackupVersion)
		}
		count, err := st.countResumes(ctx, userID)
		if err != nil {
			return err
		}
		if e := resumeLimit.check(count); e != nil {
			return e
		}
		if f.Resume == nil {
			return auth.ErrBusiness(MessageInvalidBackupFile)
		}
		if name := f.Resume.Name; name != nil {
			if exists, err := st.resumeNameExists(ctx, userID, *name); err != nil {
				return err
			} else if exists {
				return errResumeNameDuplicated()
			}
		}
		r, ok := buildRestored(f.Resume, userID)
		if !ok {
			return auth.ErrBusiness(MessageInvalidBackupFile)
		}
		r.CreatedAt, r.UpdatedAt = now, now
		if err := st.insertResume(ctx, r); err != nil {
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

// buildRestored は、戻すファイルの経歴書 rr から、要求を送った利用者 userID の経歴書を作る。rr の値が、戻すときの値の決まりを
// 1つでも満たさないか、6つの欄の並びに値の無い要素があれば、false を返す。長さは、画面で保存するときと同じく UTF-16 の単位で数える。
// 年月の範囲、職歴の期間の重なり、リンクの長さ、欄ごとの項目の数は確かめない。
// 経歴書と項目には新しい ID を付け、最後に sortEntries で項目を並べる。作った日時と直した日時は付けない。rr は nil でないこと。
func buildRestored(rr *rsResume, userID uuid.UUID) (Resume, bool) {
	b := restoreBuilder{ok: true}
	r := Resume{
		ID:             uuid.New(),
		UserID:         userID,
		Name:           b.resumeName(rr.Name),
		Date:           rr.Date.Value,
		Careers:        make([]Career, 0, len(rr.Careers)),
		Projects:       make([]Project, 0, len(rr.Projects)),
		Certifications: make([]Certification, 0, len(rr.Certifications)),
		Portfolios:     make([]Portfolio, 0, len(rr.Portfolios)),
		SnsPlatforms:   make([]SnsPlatform, 0, len(rr.SnsPlatforms)),
		SelfPromotions: make([]SelfPromotion, 0, len(rr.SelfPromotions)),
	}
	if !rr.Date.Present {
		b.ok = false
	}
	r.LastName, r.FirstName = b.fullName(rr.LastName, rr.FirstName)
	for _, c := range rr.Careers {
		if c == nil {
			return Resume{}, false
		}
		r.Careers = append(r.Careers, Career{
			ID:          uuid.New(),
			CompanyName: b.text(c.CompanyName, companyNameMaxLength),
			Period:      b.period(c.StartDate, c.EndDate, c.Active),
		})
	}
	for _, p := range rr.Projects {
		if p == nil {
			return Resume{}, false
		}
		r.Projects = append(r.Projects, Project{
			ID:          uuid.New(),
			CompanyName: b.text(p.CompanyName, companyNameMaxLength),
			Period:      b.period(p.StartDate, p.EndDate, p.Active),
			Name:        b.text(p.Name, projectNameMaxLength),
			Overview:    b.text(p.Overview, longTextMaxLength),
			TeamComp:    b.text(p.TeamComp, teamCompMaxLength),
			Role:        b.text(p.Role, longTextMaxLength),
			Achievement: b.text(p.Achievement, longTextMaxLength),
			Process:     Process(p.Process),
			TechStack:   p.TechStack,
		})
	}
	for _, c := range rr.Certifications {
		if c == nil {
			return Resume{}, false
		}
		if !c.Date.Present {
			b.ok = false
		}
		r.Certifications = append(r.Certifications, Certification{
			ID: uuid.New(), Name: b.text(c.Name, certificationNameMaxLength), Date: c.Date.Value,
		})
	}
	for _, p := range rr.Portfolios {
		if p == nil {
			return Resume{}, false
		}
		if p.TechStack != nil && auth.UTF16Len(*p.TechStack) > longTextMaxLength {
			b.ok = false
		}
		r.Portfolios = append(r.Portfolios, Portfolio{
			ID:        uuid.New(),
			Name:      b.text(p.Name, portfolioNameMaxLength),
			Overview:  b.text(p.Overview, longTextMaxLength),
			TechStack: p.TechStack,
			Link:      b.link(p.Link),
		})
	}
	for _, s := range rr.SnsPlatforms {
		if s == nil {
			return Resume{}, false
		}
		r.SnsPlatforms = append(r.SnsPlatforms, SnsPlatform{
			ID:   uuid.New(),
			Name: b.text(s.Name, snsPlatformNameMaxLength),
			Link: b.link(s.Link),
		})
	}
	for _, s := range rr.SelfPromotions {
		if s == nil {
			return Resume{}, false
		}
		r.SelfPromotions = append(r.SelfPromotions, SelfPromotion{
			ID:      uuid.New(),
			Title:   b.text(s.Title, selfPromotionTitleMaxLength),
			Content: b.text(s.Content, longTextMaxLength),
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
	if s == nil || !auth.NotBlank(*s) || auth.UTF16Len(*s) > limit {
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

// period は、期間を確かめる。始まりの年月があること、続いていなければ終わりの年月があって始まりの年月より前でないこと、
// 続いていれば終わりの年月が無いこと。
func (b *restoreBuilder) period(start, end jsonYearMonth, active bool) Period {
	if !start.Present || !active && (!end.Present || start.Value.after(end.Value)) || active && end.Present {
		b.ok = false
		return Period{}
	}
	p := Period{StartDate: start.Value, Active: active}
	if end.Present {
		p.EndDate = &end.Value
	}
	return p
}

// link は、リンクを Java 版の Link の決まりで確かめる。空白だけでなく、URI として読め、スキームが ASCII の大文字と小文字を
// 区別せずに https であること。
func (b *restoreBuilder) link(s *string) string {
	if s == nil || !auth.NotBlank(*s) {
		b.ok = false
		return ""
	}
	scheme, ok := parseJavaURI(javaChars(*s))
	if !ok || !equalsIgnoreCaseASCII(scheme, "https") {
		b.ok = false
	}
	return *s
}
