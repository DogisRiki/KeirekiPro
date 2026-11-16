package resume

import (
	"context"
	"fmt"
)

// techStackCategory は、技術スタックのマスタの大分類と小分類の組である。tech_stack_category_mst の main_category と sub_category の値である。
type techStackCategory struct {
	main, sub string
}

// techStackMasterFields は、技術スタックのマスタの大分類と小分類の組と、答えの小分類の並びの組の表である。
// 組の値は、Java 版の MyBatisTechStackListQuery の振り分けと同じである。たとえば、小分類 framework は答えの frameworks になる。
var techStackMasterFields = map[techStackCategory]func(m *TechStackMaster) *[]string{
	{"frontend", "languages"}:             func(m *TechStackMaster) *[]string { return &m.Frontend.Languages },
	{"frontend", "framework"}:             func(m *TechStackMaster) *[]string { return &m.Frontend.Frameworks },
	{"frontend", "libraries"}:             func(m *TechStackMaster) *[]string { return &m.Frontend.Libraries },
	{"frontend", "buildTool"}:             func(m *TechStackMaster) *[]string { return &m.Frontend.BuildTools },
	{"frontend", "packageManager"}:        func(m *TechStackMaster) *[]string { return &m.Frontend.PackageManagers },
	{"frontend", "linters"}:               func(m *TechStackMaster) *[]string { return &m.Frontend.Linters },
	{"frontend", "formatters"}:            func(m *TechStackMaster) *[]string { return &m.Frontend.Formatters },
	{"frontend", "testingTools"}:          func(m *TechStackMaster) *[]string { return &m.Frontend.TestingTools },
	{"backend", "languages"}:              func(m *TechStackMaster) *[]string { return &m.Backend.Languages },
	{"backend", "framework"}:              func(m *TechStackMaster) *[]string { return &m.Backend.Frameworks },
	{"backend", "libraries"}:              func(m *TechStackMaster) *[]string { return &m.Backend.Libraries },
	{"backend", "buildTool"}:              func(m *TechStackMaster) *[]string { return &m.Backend.BuildTools },
	{"backend", "packageManager"}:         func(m *TechStackMaster) *[]string { return &m.Backend.PackageManagers },
	{"backend", "linters"}:                func(m *TechStackMaster) *[]string { return &m.Backend.Linters },
	{"backend", "formatters"}:             func(m *TechStackMaster) *[]string { return &m.Backend.Formatters },
	{"backend", "testingTools"}:           func(m *TechStackMaster) *[]string { return &m.Backend.TestingTools },
	{"backend", "ormTools"}:               func(m *TechStackMaster) *[]string { return &m.Backend.OrmTools },
	{"backend", "auth"}:                   func(m *TechStackMaster) *[]string { return &m.Backend.Auth },
	{"infrastructure", "clouds"}:          func(m *TechStackMaster) *[]string { return &m.Infrastructure.Clouds },
	{"infrastructure", "operatingSystem"}: func(m *TechStackMaster) *[]string { return &m.Infrastructure.OperatingSystems },
	{"infrastructure", "containers"}:      func(m *TechStackMaster) *[]string { return &m.Infrastructure.Containers },
	{"infrastructure", "database"}:        func(m *TechStackMaster) *[]string { return &m.Infrastructure.Databases },
	{"infrastructure", "webServer"}:       func(m *TechStackMaster) *[]string { return &m.Infrastructure.WebServers },
	{"infrastructure", "ciCdTool"}:        func(m *TechStackMaster) *[]string { return &m.Infrastructure.CiCdTools },
	{"infrastructure", "iacTools"}:        func(m *TechStackMaster) *[]string { return &m.Infrastructure.IacTools },
	{"infrastructure", "monitoringTools"}: func(m *TechStackMaster) *[]string { return &m.Infrastructure.MonitoringTools },
	{"infrastructure", "loggingTools"}:    func(m *TechStackMaster) *[]string { return &m.Infrastructure.LoggingTools },
	{"tools", "sourceControl"}:            func(m *TechStackMaster) *[]string { return &m.Tools.SourceControls },
	{"tools", "projectManagement"}:        func(m *TechStackMaster) *[]string { return &m.Tools.ProjectManagements },
	{"tools", "communicationTool"}:        func(m *TechStackMaster) *[]string { return &m.Tools.CommunicationTools },
	{"tools", "documentationTools"}:       func(m *TechStackMaster) *[]string { return &m.Tools.DocumentationTools },
	{"tools", "apiDevelopmentTools"}:      func(m *TechStackMaster) *[]string { return &m.Tools.APIDevelopmentTools },
	{"tools", "designTools"}:              func(m *TechStackMaster) *[]string { return &m.Tools.DesignTools },
	{"tools", "editor"}:                   func(m *TechStackMaster) *[]string { return &m.Tools.Editors },
	{"tools", "developmentEnvironment"}:   func(m *TechStackMaster) *[]string { return &m.Tools.DevelopmentEnvironments },
}

// listCertificationNames は、資格のマスタの名前を、表に入っている並びのまま読む。行が無ければ空の並びを返す。
func (s store) listCertificationNames(ctx context.Context) ([]string, error) {
	names, err := s.q.ListCertificationNames(ctx)
	if err != nil {
		return nil, fmt.Errorf("資格のマスタを読めません: %w", err)
	}
	return nonNil(names), nil
}

// listSnsPlatformNames は、SNS のマスタの名前を、表に入っている並びのまま読む。行が無ければ空の並びを返す。
func (s store) listSnsPlatformNames(ctx context.Context) ([]string, error) {
	names, err := s.q.ListSnsPlatformNames(ctx)
	if err != nil {
		return nil, fmt.Errorf("SNS のマスタを読めません: %w", err)
	}
	return nonNil(names), nil
}

// listTechStacks は、技術スタックのマスタの名前を、大分類と小分類の組ごとに答えの小分類に振り分けて読む。
// 小分類の中は、問い合わせのとおり技術スタックの ID の順である。表に無い組の行は捨てる。名前の無い小分類は空の並びにする。
func (s store) listTechStacks(ctx context.Context) (TechStackMaster, error) {
	rows, err := s.q.ListTechStacks(ctx)
	if err != nil {
		return TechStackMaster{}, fmt.Errorf("技術スタックのマスタを読めません: %w", err)
	}
	var m TechStackMaster
	for _, field := range techStackMasterFields {
		*field(&m) = []string{}
	}
	for _, row := range rows {
		if field, ok := techStackMasterFields[techStackCategory{row.MainCategory, row.SubCategory}]; ok {
			*field(&m) = append(*field(&m), row.Name)
		}
	}
	return m, nil
}

// nonNil は、nil の並びを空の並びにする。
func nonNil(s []string) []string {
	if s == nil {
		return []string{}
	}
	return s
}
