package com.example.keirekipro.domain.model.resume;

import java.util.UUID;

import com.example.keirekipro.domain.shared.Entity;
import com.example.keirekipro.shared.Notification;

import lombok.EqualsAndHashCode;
import lombok.Getter;

/**
 * プロジェクト
 */
@Getter
public class Project extends Entity {

    /**
     * 会社名
     */
    private final CompanyName companyName;

    /**
     * 期間
     */
    private final Period period;

    /**
     * プロジェクト名
     */
    private final String name;

    /**
     * プロジェクト概要
     */
    private final String overview;

    /**
     * チーム構成
     */
    private final String teamComp;

    /**
     * 役割
     */
    private final String role;

    /**
     * 成果
     */
    private final String achievement;

    /**
     * 作業工程
     */
    private final Process process;

    /**
     * 技術スタック
     */
    private final TechStack techStack;

    /**
     * 新規構築用のコンストラクタ
     */
    private Project(CompanyName companyName, Period period, String name, String overview, String teamComp,
            String role,
            String achievement, Process process, TechStack techStack) {
        super();
        this.companyName = companyName;
        this.period = period;
        this.name = name;
        this.overview = overview;
        this.teamComp = teamComp;
        this.role = role;
        this.achievement = achievement;
        this.process = process;
        this.techStack = techStack;
    }

    /**
     * 再構築用のコンストラクタ
     */
    private Project(UUID id, CompanyName companyName, Period period, String name, String overview,
            String teamComp,
            String role,
            String achievement, Process process, TechStack techStack) {
        super(id);
        this.companyName = companyName;
        this.period = period;
        this.name = name;
        this.overview = overview;
        this.teamComp = teamComp;
        this.role = role;
        this.achievement = achievement;
        this.process = process;
        this.techStack = techStack;
    }

    /**
     * 新規構築用のファクトリーメソッド
     *
     * @param notification 通知オブジェクト
     * @param companyName  会社名
     * @param period       期間
     * @param name         プロジェクト名
     * @param overview     プロジェクト概要
     * @param teamComp     チーム構成
     * @param role         役割
     * @param achievement  成果
     * @param process      作業工程
     * @param techStack    技術スタック
     * @return プロジェクトエンティティ
     */
    public static Project create(Notification notification, CompanyName companyName, Period period, String name,
            String overview,
            String teamComp,
            String role,
            String achievement, Process process, TechStack techStack) {
        validate(notification, companyName, period, name, overview, teamComp, role, achievement);
        return new Project(companyName, period, name, overview, teamComp, role, achievement, process,
                techStack);
    }

    /**
     * 再構築用のファクトリーメソッド
     *
     * @param id          識別子
     * @param companyName 会社名
     * @param period      期間
     * @param name        プロジェクト名
     * @param overview    プロジェクト概要
     * @param teamComp    チーム構成
     * @param role        役割
     * @param achievement 成果
     * @param process     作業工程
     * @param techStack   技術スタック
     * @return プロジェクトエンティティ
     */
    public static Project reconstruct(UUID id, CompanyName companyName, Period period, String name,
            String overview,
            String teamComp,
            String role,
            String achievement, Process process, TechStack techStack) {
        return new Project(id, companyName, period, name, overview, teamComp, role, achievement, process,
                techStack);
    }

    /**
     * 会社名を変更する
     *
     * @param notification 通知オブジェクト
     * @param companyName  新しい会社名
     * @return 変更後のプロジェクトエンティティ
     */
    public Project changeCompanyName(Notification notification, CompanyName companyName) {
        validate(notification, companyName, this.period, this.name, this.overview, this.teamComp, this.role,
                this.achievement);
        return new Project(this.id, companyName, this.period, this.name, this.overview, this.teamComp, this.role,
                this.achievement, this.process, this.techStack);
    }

    /**
     * 期間を変更する
     *
     * @param notification 通知オブジェクト
     * @param period       新しい期間
     * @return 変更後のプロジェクトエンティティ
     */
    public Project changePeriod(Notification notification, Period period) {
        validate(notification, this.companyName, period, this.name, this.overview, this.teamComp, this.role,
                this.achievement);
        return new Project(this.id, this.companyName, period, this.name, this.overview, this.teamComp, this.role,
                this.achievement, this.process, this.techStack);
    }

    /**
     * プロジェクト名を変更する
     *
     * @param notification 通知オブジェクト
     * @param name         新しいプロジェクト名
     * @return 変更後のプロジェクトエンティティ
     */
    public Project changeName(Notification notification, String name) {
        validate(notification, this.companyName, this.period, name, this.overview, this.teamComp, this.role,
                this.achievement);
        return new Project(this.id, this.companyName, this.period, name, this.overview, this.teamComp, this.role,
                this.achievement, this.process, this.techStack);
    }

    /**
     * プロジェクト概要を変更する
     *
     * @param notification 通知オブジェクト
     * @param overview     新しいプロジェクト概要
     * @return 変更後のプロジェクトエンティティ
     */
    public Project changeOverview(Notification notification, String overview) {
        validate(notification, this.companyName, this.period, this.name, overview, this.teamComp, this.role,
                this.achievement);
        return new Project(this.id, this.companyName, this.period, this.name, overview, this.teamComp, this.role,
                this.achievement, this.process, this.techStack);
    }

    /**
     * チーム構成を変更する
     *
     * @param notification 通知オブジェクト
     * @param teamComp     新しいチーム構成
     * @return 変更後のプロジェクトエンティティ
     */
    public Project changeTeamComp(Notification notification, String teamComp) {
        validate(notification, this.companyName, this.period, this.name, this.overview, teamComp, this.role,
                this.achievement);
        return new Project(this.id, this.companyName, this.period, this.name, this.overview, teamComp, this.role,
                this.achievement, this.process, this.techStack);
    }

    /**
     * 役割を変更する
     *
     * @param notification 通知オブジェクト
     * @param role         新しい役割
     * @return 変更後のプロジェクトエンティティ
     */
    public Project changeRole(Notification notification, String role) {
        validate(notification, this.companyName, this.period, this.name, this.overview, this.teamComp, role,
                this.achievement);
        return new Project(this.id, this.companyName, this.period, this.name, this.overview, this.teamComp, role,
                this.achievement, this.process, this.techStack);
    }

    /**
     * 成果を変更する
     *
     * @param notification 通知オブジェクト
     * @param achievement  新しい成果
     * @return 変更後のプロジェクトエンティティ
     */
    public Project changeAchievement(Notification notification, String achievement) {
        validate(notification, this.companyName, this.period, this.name, this.overview, this.teamComp, this.role,
                achievement);
        return new Project(this.id, this.companyName, this.period, this.name, this.overview, this.teamComp, this.role,
                achievement, this.process, this.techStack);
    }

    /**
     * 作業工程を変更する
     *
     * @param process 新しい作業工程
     * @return 変更後のプロジェクトエンティティ
     */
    public Project changeProcess(Process process) {
        return new Project(this.id, this.companyName, this.period, this.name, this.overview, this.teamComp, this.role,
                this.achievement, process, this.techStack);
    }

    /**
     * 技術スタックを変更する
     *
     * @param techStack 新しい技術スタック
     * @return 変更後のプロジェクトエンティティ
     */
    public Project changeTechStack(TechStack techStack) {
        return new Project(this.id, this.companyName, this.period, this.name, this.overview, this.teamComp, this.role,
                this.achievement, this.process, techStack);
    }

    private static void validate(Notification notification, CompanyName companyName, Period period, String name,
            String overview, String teamComp, String role, String achievement) {

        if (companyName == null) {
            notification.addError("companyName", "会社名は入力必須です。");
        }

        if (period == null) {
            notification.addError("period", "期間は入力必須です。");
        }

        if (name == null || name.isBlank()) {
            notification.addError("name", "プロジェクト名は入力必須です。");
        } else if (name.length() > 50) {
            notification.addError("name", "プロジェクト名は50文字以内で入力してください。");
        }

        if (overview == null || overview.isBlank()) {
            notification.addError("overview", "プロジェクト概要は入力必須です。");
        } else if (overview.length() > 1000) {
            notification.addError("overview", "プロジェクト概要は1000文字以内で入力してください。");
        }

        if (teamComp == null || teamComp.isBlank()) {
            notification.addError("teamComp", "チーム構成は入力必須です。");
        } else if (teamComp.length() > 100) {
            notification.addError("teamComp", "チーム構成は100文字以内で入力してください。");
        }

        if (role == null || role.isBlank()) {
            notification.addError("role", "役割は入力必須です。");
        } else if (role.length() > 1000) {
            notification.addError("role", "役割は1000文字以内で入力してください。");
        }

        if (achievement == null || achievement.isBlank()) {
            notification.addError("achievement", "成果は入力必須です。");
        } else if (achievement.length() > 1000) {
            notification.addError("achievement", "成果は1000文字以内で入力してください。");
        }
    }

    /**
     * 作業工程
     */
    @Getter
    @EqualsAndHashCode
    public static class Process {

        /**
         * 要件定義
         */
        private final boolean requirements;

        /**
         * 基本設計
         */
        private final boolean basicDesign;

        /**
         * 詳細設計
         */
        private final boolean detailedDesign;

        /**
         * 実装・単体テスト
         */
        private final boolean implementation;

        /**
         * 結合テスト
         */
        private final boolean integrationTest;

        /**
         * 総合テスト
         */
        private final boolean systemTest;

        /**
         * 運用・保守
         */
        private final boolean maintenance;

        private Process(boolean requirements, boolean basicDesign, boolean detailedDesign, boolean implementation,
                boolean integrationTest, boolean systemTest, boolean maintenance) {
            this.requirements = requirements;
            this.basicDesign = basicDesign;
            this.detailedDesign = detailedDesign;
            this.implementation = implementation;
            this.integrationTest = integrationTest;
            this.systemTest = systemTest;
            this.maintenance = maintenance;
        }

        /**
         * ファクトリーメソッド
         *
         * @param requirements    要件定義
         * @param basicDesign     基本設計
         * @param detailedDesign  詳細設計
         * @param implementation  実装・単体テスト
         * @param integrationTest 結合テスト
         * @param systemTest      総合テスト
         * @param maintenance     運用・保守
         * @return 値オブジェクト
         */
        public static Process create(boolean requirements, boolean basicDesign, boolean detailedDesign,
                boolean implementation,
                boolean integrationTest, boolean systemTest, boolean maintenance) {
            return new Process(requirements, basicDesign, detailedDesign, implementation, integrationTest, systemTest,
                    maintenance);
        }
    }
}
