package com.example.keirekipro.infrastructure.export.resume;

import java.time.LocalDate;
import java.time.YearMonth;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import com.example.keirekipro.domain.model.resume.FullName;
import com.example.keirekipro.domain.model.resume.Period;
import com.example.keirekipro.domain.model.resume.Project;
import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.model.resume.TechStack;

import org.springframework.stereotype.Component;

/**
 * 職務経歴書（Resume）をテンプレート用のexportモデルを構築するビルダー
 */
@Component
public class ResumeExportModelBuilder {

    /**
     * thymeleafテンプレートへ渡すモデルを構築する
     *
     * @param resume 職務経歴書エンティティ
     * @return exportモデル（テンプレートはexport.xxxで参照する）
     */
    public Map<String, Object> build(Resume resume) {
        Map<String, Object> export = new LinkedHashMap<>();

        // ヘッダ情報
        export.put("title", "職務経歴書");
        export.put("asOfDateLabel", formatAsOfDate(resume.getDate()));
        export.put("fullName", formatFullName(resume.getFullName()));

        // 職歴
        export.put("careers", resume.getCareers().stream()
                .map(c -> Map.<String, Object>of(
                        "periodLabel", formatPeriod(c.getPeriod()),
                        "companyName", c.getCompanyName() != null ? c.getCompanyName().getValue() : ""))
                .toList());

        List<Map<String, Object>> companySections = new ArrayList<>();
        Map<String, Map<String, Object>> companySectionIndex = new LinkedHashMap<>();
        List<Project> projects = safeList(resume.getProjects());

        // プロジェクト
        for (Project p : projects) {
            Map<String, Object> projectModel = new LinkedHashMap<>();
            projectModel.put("periodStartLabel", formatPeriodStart(p.getPeriod()));
            projectModel.put("periodEndLabel", formatPeriodEnd(p.getPeriod()));
            projectModel.put("projectLabel", formatProjectLabel(p));
            projectModel.put("projectName", p.getName() != null ? p.getName() : "");
            projectModel.put("overview", p.getOverview());
            projectModel.put("teamComp", p.getTeamComp());
            projectModel.put("role", p.getRole());
            projectModel.put("achievements", splitLines(p.getAchievement()));
            projectModel.put("process", buildProcessModel(p.getProcess()));
            projectModel.put("tech", buildTechModel(p.getTechStack()));
            projectModel.put("techSections", buildTechSections(p.getTechStack()));

            final String companyLabel = buildCompanyLabel(p);

            // 同一勤務先のプロジェクトは、添付PDFに近い形式で1つの勤務先表にまとめる
            Map<String, Object> companyModel = companySectionIndex.get(companyLabel);
            if (companyModel == null) {
                companyModel = new LinkedHashMap<>();
                companyModel.put("companyLabel", companyLabel);
                companyModel.put("companyPeriodLabel", buildCompanyPeriodLabel(companyLabel, resume));
                companyModel.put("projects", new ArrayList<Map<String, Object>>());
                companySectionIndex.put(companyLabel, companyModel);
                companySections.add(companyModel);
            }

            @SuppressWarnings("unchecked")
            List<Map<String, Object>> companyProjects = (List<Map<String, Object>>) companyModel.get("projects");
            companyProjects.add(projectModel);
        }

        export.put("companySections", companySections);

        // 資格（セクションの表示有無はテンプレート側で制御）
        export.put("certifications", resume.getCertifications().stream()
                .map(c -> Map.<String, Object>of(
                        "acquiredAtLabel", formatYearMonth(c.getDate()),
                        "name", c.getName()))
                .toList());

        // ポートフォリオ（存在する場合、url/techStack/overviewは必ずある前提でそのまま渡す）
        export.put("portfolios", resume.getPortfolios().stream()
                .map(p -> {
                    Map<String, Object> m = new LinkedHashMap<>();
                    m.put("name", p.getName());
                    m.put("url", p.getLink() != null ? p.getLink().getValue() : "");
                    m.put("techStack", p.getTechStack());
                    m.put("overview", p.getOverview());
                    return m;
                }).toList());

        // SNS（セクションの表示有無はテンプレート側で制御）
        export.put("snsPlatforms", resume.getSnsPlatforms().stream()
                .map(s -> Map.<String, Object>of(
                        "name", s.getName(),
                        "url", s.getLink() != null ? s.getLink().getValue() : ""))
                .toList());

        // 自己PR
        export.put("selfPromotions", resume.getSelfPromotions().stream()
                .map(sp -> Map.<String, Object>of(
                        "title", sp.getTitle(),
                        "content", sp.getContent()))
                .toList());

        return export;
    }

    /**
     * 会社ラベルを構築する
     *
     * @param project プロジェクト
     * @return 会社ラベル
     */
    private static String buildCompanyLabel(Project project) {
        if (project == null) {
            return "";
        }
        return project.getCompanyName() != null ? project.getCompanyName().getValue() : "";
    }

    /**
     * 勤務先の期間ラベルを構築する
     *
     * @param companyLabel 会社ラベル
     * @param resume 職務経歴書エンティティ
     * @return 勤務期間ラベル
     */
    private static String buildCompanyPeriodLabel(String companyLabel, Resume resume) {
        if (companyLabel == null || companyLabel.isBlank() || resume == null) {
            return "";
        }

        return safeList(resume.getCareers()).stream()
                .filter(c -> c.getCompanyName() != null && companyLabel.equals(c.getCompanyName().getValue()))
                .findFirst()
                .map(c -> formatPeriod(c.getPeriod()))
                .orElse("");
    }

    /**
     * 作業工程をテンプレート向けに整形する
     *
     * @param process 作業工程
     * @return テンプレート用モデル
     */
    private static Map<String, Object> buildProcessModel(Project.Process process) {
        Map<String, Object> model = new LinkedHashMap<>();

        if (process == null) {
            model.put("requirements", false);
            model.put("basicDesign", false);
            model.put("detailedDesign", false);
            model.put("implementation", false);
            model.put("integrationTest", false);
            model.put("systemTest", false);
            model.put("maintenance", false);
            model.put("label", "");
            return model;
        }

        model.put("requirements", process.isRequirements());
        model.put("basicDesign", process.isBasicDesign());
        model.put("detailedDesign", process.isDetailedDesign());
        model.put("implementation", process.isImplementation());
        model.put("integrationTest", process.isIntegrationTest());
        model.put("systemTest", process.isSystemTest());
        model.put("maintenance", process.isMaintenance());
        model.put("label", formatProcess(process));

        return model;
    }

    /**
     * 技術スタックをテンプレート向けに整形する。
     *
     * @param techStack 技術スタック
     * @return テンプレート用モデル（表示可能な値が無い場合はnull）
     */
    private static Map<String, Object> buildTechModel(TechStack techStack) {
        if (techStack == null) {
            return null;
        }

        Map<String, Object> tech = new LinkedHashMap<>();

        TechStack.Frontend fe = techStack.getFrontend();
        if (fe != null) {
            Map<String, Object> m = new LinkedHashMap<>();
            putIfNotNull(m, "languages", normalizeList(fe.getLanguages()));
            putIfNotNull(m, "frameworks", normalizeList(fe.getFrameworks()));
            putIfNotNull(m, "libraries", normalizeList(fe.getLibraries()));
            putIfNotNull(m, "buildTools", normalizeList(fe.getBuildTools()));
            putIfNotNull(m, "packageManagers", normalizeList(fe.getPackageManagers()));
            putIfNotNull(m, "linters", normalizeList(fe.getLinters()));
            putIfNotNull(m, "formatters", normalizeList(fe.getFormatters()));
            putIfNotNull(m, "testingTools", normalizeList(fe.getTestingTools()));

            // 表示可能な値が1つでもあるカテゴリのみ出力する
            if (!m.isEmpty()) {
                tech.put("frontend", m);
            }
        }

        TechStack.Backend be = techStack.getBackend();
        if (be != null) {
            Map<String, Object> m = new LinkedHashMap<>();
            putIfNotNull(m, "languages", normalizeList(be.getLanguages()));
            putIfNotNull(m, "frameworks", normalizeList(be.getFrameworks()));
            putIfNotNull(m, "libraries", normalizeList(be.getLibraries()));
            putIfNotNull(m, "buildTools", normalizeList(be.getBuildTools()));
            putIfNotNull(m, "packageManagers", normalizeList(be.getPackageManagers()));
            putIfNotNull(m, "linters", normalizeList(be.getLinters()));
            putIfNotNull(m, "formatters", normalizeList(be.getFormatters()));
            putIfNotNull(m, "testingTools", normalizeList(be.getTestingTools()));
            putIfNotNull(m, "ormTools", normalizeList(be.getOrmTools()));
            putIfNotNull(m, "auth", normalizeList(be.getAuth()));

            if (!m.isEmpty()) {
                tech.put("backend", m);
            }
        }

        TechStack.Infrastructure infra = techStack.getInfrastructure();
        if (infra != null) {
            Map<String, Object> m = new LinkedHashMap<>();
            putIfNotNull(m, "clouds", normalizeList(infra.getClouds()));
            putIfNotNull(m, "operatingSystems", normalizeList(infra.getOperatingSystems()));
            putIfNotNull(m, "containers", normalizeList(infra.getContainers()));
            putIfNotNull(m, "databases", normalizeList(infra.getDatabases()));
            putIfNotNull(m, "webServers", normalizeList(infra.getWebServers()));
            putIfNotNull(m, "ciCdTools", normalizeList(infra.getCiCdTools()));
            putIfNotNull(m, "iacTools", normalizeList(infra.getIacTools()));
            putIfNotNull(m, "monitoringTools", normalizeList(infra.getMonitoringTools()));
            putIfNotNull(m, "loggingTools", normalizeList(infra.getLoggingTools()));

            if (!m.isEmpty()) {
                tech.put("infrastructure", m);
            }
        }

        TechStack.Tools tools = techStack.getTools();
        if (tools != null) {
            Map<String, Object> m = new LinkedHashMap<>();
            putIfNotNull(m, "sourceControls", normalizeList(tools.getSourceControls()));
            putIfNotNull(m, "projectManagements", normalizeList(tools.getProjectManagements()));
            putIfNotNull(m, "communicationTools", normalizeList(tools.getCommunicationTools()));
            putIfNotNull(m, "documentationTools", normalizeList(tools.getDocumentationTools()));
            putIfNotNull(m, "apiDevelopmentTools", normalizeList(tools.getApiDevelopmentTools()));
            putIfNotNull(m, "designTools", normalizeList(tools.getDesignTools()));
            putIfNotNull(m, "editors", normalizeList(tools.getEditors()));
            putIfNotNull(m, "developmentEnvironments", normalizeList(tools.getDevelopmentEnvironments()));

            if (!m.isEmpty()) {
                tech.put("tools", m);
            }
        }

        // 表示可能な値が無い場合はnull扱いにして、テンプレート側でセクション自体を出さない
        return tech.isEmpty() ? null : tech;
    }

    /**
     * 技術スタックを帳票表示向けに整形する。
     *
     * @param techStack 技術スタック
     * @return 帳票表示用の技術スタックセクション
     */
    private static List<Map<String, Object>> buildTechSections(TechStack techStack) {
        if (techStack == null) {
            return List.of();
        }

        List<Map<String, Object>> sections = new ArrayList<>();

        TechStack.Frontend fe = techStack.getFrontend();
        if (fe != null) {
            List<Map<String, Object>> lines = new ArrayList<>();
            putTechLine(lines, "開発言語", fe.getLanguages());
            putTechLine(lines, "フレームワーク", fe.getFrameworks());
            putTechLine(lines, "ライブラリ", fe.getLibraries());
            putTechLine(lines, "ビルドツール", fe.getBuildTools());
            putTechLine(lines, "パッケージマネージャー", fe.getPackageManagers());
            putTechLine(lines, "リンター", fe.getLinters());
            putTechLine(lines, "フォーマッター", fe.getFormatters());
            putTechLine(lines, "テストツール", fe.getTestingTools());
            putTechSection(sections, "フロントエンド", lines);
        }

        TechStack.Backend be = techStack.getBackend();
        if (be != null) {
            List<Map<String, Object>> lines = new ArrayList<>();
            putTechLine(lines, "開発言語", be.getLanguages());
            putTechLine(lines, "フレームワーク", be.getFrameworks());
            putTechLine(lines, "ライブラリ", be.getLibraries());
            putTechLine(lines, "ビルドツール", be.getBuildTools());
            putTechLine(lines, "パッケージマネージャー", be.getPackageManagers());
            putTechLine(lines, "リンター", be.getLinters());
            putTechLine(lines, "フォーマッター", be.getFormatters());
            putTechLine(lines, "テストツール", be.getTestingTools());
            putTechLine(lines, "ORM", be.getOrmTools());
            putTechLine(lines, "認証", be.getAuth());
            putTechSection(sections, "バックエンド", lines);
        }

        TechStack.Infrastructure infra = techStack.getInfrastructure();
        if (infra != null) {
            List<Map<String, Object>> lines = new ArrayList<>();
            putTechLine(lines, "クラウド", infra.getClouds());
            putTechLine(lines, "OS", infra.getOperatingSystems());
            putTechLine(lines, "コンテナ", infra.getContainers());
            putTechLine(lines, "データベース", infra.getDatabases());
            putTechLine(lines, "Webサーバー", infra.getWebServers());
            putTechLine(lines, "CI/CD", infra.getCiCdTools());
            putTechLine(lines, "IaC", infra.getIacTools());
            putTechLine(lines, "監視", infra.getMonitoringTools());
            putTechLine(lines, "ロギング", infra.getLoggingTools());
            putTechSection(sections, "インフラ", lines);
        }

        TechStack.Tools tools = techStack.getTools();
        if (tools != null) {
            List<Map<String, Object>> lines = new ArrayList<>();
            putTechLine(lines, "ソース管理", tools.getSourceControls());
            putTechLine(lines, "プロジェクト管理", tools.getProjectManagements());
            putTechLine(lines, "コミュニケーション", tools.getCommunicationTools());
            putTechLine(lines, "ドキュメント", tools.getDocumentationTools());
            putTechLine(lines, "API開発", tools.getApiDevelopmentTools());
            putTechLine(lines, "デザイン", tools.getDesignTools());
            putTechLine(lines, "エディタ", tools.getEditors());
            putTechLine(lines, "開発環境", tools.getDevelopmentEnvironments());
            putTechSection(sections, "開発支援ツール", lines);
        }

        return sections;
    }

    /**
     * 技術スタックセクションを追加する
     *
     * @param sections 追加先セクションリスト
     * @param title セクションタイトル
     * @param lines 技術スタック行リスト
     */
    private static void putTechSection(List<Map<String, Object>> sections, String title,
            List<Map<String, Object>> lines) {
        if (lines == null || lines.isEmpty()) {
            return;
        }

        Map<String, Object> section = new LinkedHashMap<>();
        section.put("title", title);
        section.put("lines", lines);
        sections.add(section);
    }

    /**
     * 技術スタック行を追加する
     *
     * @param lines 追加先行リスト
     * @param label 表示ラベル
     * @param values 表示値リスト
     */
    private static void putTechLine(List<Map<String, Object>> lines, String label, List<String> values) {
        String value = joinValues(values);
        if (value == null || value.isBlank()) {
            return;
        }

        Map<String, Object> line = new LinkedHashMap<>();
        line.put("label", label);
        line.put("value", value);
        lines.add(line);
    }

    /**
     * 値がnullでない場合のみMapへ格納する
     *
     * @param map 格納先Map
     * @param key キー
     * @param value 値（nullの場合は格納しない）
     */
    private static void putIfNotNull(Map<String, Object> map, String key, Object value) {
        if (value != null) {
            map.put(key, value);
        }
    }

    /**
     * 「yyyy年M月d日現在」の文字列を生成する
     *
     * @param date 日付
     * @return 表示用日付文字列
     */
    private static String formatAsOfDate(LocalDate date) {
        if (date == null) {
            return "";
        }
        return date.getYear() + "年" + date.getMonthValue() + "月" + date.getDayOfMonth() + "日現在";
    }

    /**
     * 氏名を「姓 名」形式で生成する
     *
     * @param fullName 氏名
     * @return 表示用氏名文字列
     */
    private static String formatFullName(FullName fullName) {
        if (fullName == null) {
            return "";
        }
        String last = fullName.getLastName() != null ? fullName.getLastName() : "";
        String first = fullName.getFirstName() != null ? fullName.getFirstName() : "";
        return (last + " " + first).trim();
    }

    /**
     * プロジェクト見出しを「プロジェクト名（期間）」形式で生成する
     *
     * @param project プロジェクト
     * @return 表示用プロジェクト見出し
     */
    private static String formatProjectLabel(Project project) {
        String name = project.getName() != null ? project.getName() : "";
        return name + "（" + formatPeriod(project.getPeriod()) + "）";
    }

    /**
     * プロジェクト期間の開始年月を生成する
     *
     * @param period 期間
     * @return 表示用開始年月
     */
    private static String formatPeriodStart(Period period) {
        if (period == null || period.getStartDate() == null) {
            return "";
        }
        return formatYearMonth(period.getStartDate());
    }

    /**
     * プロジェクト期間の終了年月を生成する
     *
     * @param period 期間
     * @return 表示用終了年月
     */
    private static String formatPeriodEnd(Period period) {
        if (period == null || period.getStartDate() == null) {
            return "";
        }
        if (period.isActive()) {
            return "現在";
        }
        return formatYearMonth(period.getEndDate());
    }

    /**
     * 期間を「開始年月 〜 終了年月」または「開始年月 〜 現在」形式で生成する
     *
     * @param period 期間
     * @return 表示用期間文字列
     */
    private static String formatPeriod(Period period) {
        if (period == null || period.getStartDate() == null) {
            return "";
        }
        String start = formatYearMonth(period.getStartDate());
        if (period.isActive()) {
            return start + " 〜 現在";
        }
        String end = formatYearMonth(period.getEndDate());
        return start + " 〜 " + end;
    }

    /**
     * 作業工程を帳票表示用に整形する
     *
     * @param process 作業工程
     * @return 表示用作業工程
     */
    private static String formatProcess(Project.Process process) {
        if (process == null) {
            return "";
        }

        List<String> labels = new ArrayList<>();

        if (process.isRequirements()) {
            labels.add("要件定義");
        }
        if (process.isBasicDesign()) {
            labels.add("基本設計");
        }
        if (process.isDetailedDesign()) {
            labels.add("詳細設計");
        }
        if (process.isImplementation()) {
            labels.add("実装・単体テスト");
        }
        if (process.isIntegrationTest()) {
            labels.add("結合テスト");
        }
        if (process.isSystemTest()) {
            labels.add("総合テスト");
        }
        if (process.isMaintenance()) {
            labels.add("運用・保守");
        }

        return String.join("、", labels);
    }

    /**
     * 年月を「yyyy年M月」形式に整形する
     *
     * @param ym 年月
     * @return 表示用年月文字列
     */
    private static String formatYearMonth(YearMonth ym) {
        if (ym == null) {
            return "";
        }
        return ym.getYear() + "年" + ym.getMonthValue() + "月";
    }

    /**
     * 成果（複数行）を行ごとのリストに分割する
     * 「-」「*」「•」等は「・」へ正規化する
     *
     * @param raw 複数行テキスト
     * @return 分割後の行リスト
     */
    private static List<String> splitLines(String raw) {
        if (raw == null || raw.isBlank()) {
            return List.of();
        }
        return raw.lines()
                .map(s -> s == null ? "" : s.trim())
                .map(ResumeExportModelBuilder::normalizeBulletPrefix)
                .filter(s -> !s.isBlank())
                .toList();
    }

    private static String normalizeBulletPrefix(String s) {
        if (s == null) {
            return "";
        }
        if (s.startsWith("・")) {
            return s;
        }
        if (s.startsWith("- ")) {
            return "・" + s.substring(2).trim();
        }
        if (s.startsWith("* ")) {
            return "・" + s.substring(2).trim();
        }
        if (s.startsWith("• ")) {
            return "・" + s.substring(2).trim();
        }
        if (s.matches("^[\\-\\*•]\\s+.*$")) {
            return "・" + s.replaceFirst("^[\\-\\*•]\\s+", "").trim();
        }
        return s;
    }

    /**
     * 文字列リストをトリム・空要素除去・重複排除し、空の場合はnullを返す
     *
     * @param values 文字列リスト
     * @return 正規化済みリスト（空の場合はnull）
     */
    private static List<String> normalizeList(List<String> values) {
        if (values == null) {
            return null;
        }
        List<String> normalized = values.stream()
                .filter(v -> v != null && !v.isBlank())
                .map(String::trim)
                .distinct()
                .toList();
        return normalized.isEmpty() ? null : normalized;
    }

    /**
     * 文字列リストを帳票表示用に結合する
     *
     * @param values 文字列リスト
     * @return 結合済み文字列（空の場合はnull）
     */
    private static String joinValues(List<String> values) {
        List<String> normalized = normalizeList(values);
        if (normalized == null || normalized.isEmpty()) {
            return null;
        }
        return String.join("、", normalized);
    }

    /**
     * nullの場合に空リストを返す
     *
     * @param list 対象リスト
     * @param <T> 要素型
     * @return nullの場合は空リスト、それ以外は元リスト
     */
    private static <T> List<T> safeList(List<T> list) {
        return list == null ? List.of() : list;
    }
}
