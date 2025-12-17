package com.example.keirekipro.domain.model.resume;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.UUID;

import com.example.keirekipro.domain.policy.resume.ResumeEntryOrderPolicy;
import com.example.keirekipro.domain.shared.Entity;
import com.example.keirekipro.domain.shared.exception.DomainException;
import com.example.keirekipro.shared.Notification;

import lombok.Getter;

/**
 * 職務経歴書(ルートエンティティ)
 */
@Getter
public class Resume extends Entity {

    /**
     * ユーザーID
     */
    private final UUID userId;

    /**
     * 職務経歴書名
     */
    private final ResumeName name;

    /**
     * 日付
     */
    private final LocalDate date;

    /**
     * 氏名
     */
    private final FullName fullName;

    /**
     * 作成日時
     */
    private final LocalDateTime createdAt;

    /**
     * 更新日時
     */
    private final LocalDateTime updatedAt;

    /**
     * 職歴リスト
     */
    private final List<Career> careers;

    /**
     * プロジェクトリスト
     */
    private final List<Project> projects;

    /**
     * 資格リスト
     */
    private final List<Certification> certifications;

    /**
     * ポートフォリオリスト
     */
    private final List<Portfolio> portfolios;

    /**
     * ソーシャルリンクリスト
     */
    private final List<SocialLink> socialLinks;

    /**
     * 自己PRリスト
     */
    private final List<SelfPromotion> selfPromotions;

    /**
     * リストは全てイミュータブルにし、リスト内を整列する
     * resume.getCareers().add(new Career()) のような操作を禁止する
     */
    public List<Career> getCareers() {
        return unmodifiableSortedCopy(careers, ResumeEntryOrderPolicy.careerDesc());
    }

    public List<Project> getProjects() {
        return unmodifiableSortedCopy(projects, ResumeEntryOrderPolicy.projectDesc());
    }

    public List<Certification> getCertifications() {
        return unmodifiableSortedCopy(certifications, ResumeEntryOrderPolicy.certificationDesc());
    }

    public List<Portfolio> getPortfolios() {
        return unmodifiableSortedCopy(portfolios, ResumeEntryOrderPolicy.portfolioNameAsc());
    }

    public List<SocialLink> getSocialLinks() {
        return unmodifiableSortedCopy(socialLinks, ResumeEntryOrderPolicy.socialLinkNameAsc());
    }

    public List<SelfPromotion> getSelfPromotions() {
        return unmodifiableSortedCopy(selfPromotions, ResumeEntryOrderPolicy.selfPromotionTitleAsc());
    }

    /**
     * 指定の比較器で整列したイミュータブルなリストを返す
     *
     * @param source     元リスト
     * @param comparator 並び替え用比較器
     * @param <T>        要素型
     * @return 整列済みイミュータブルリスト
     */
    private static <T> List<T> unmodifiableSortedCopy(List<T> source, Comparator<? super T> comparator) {
        List<T> copied = new ArrayList<>(source);
        copied.sort(comparator);
        return Collections.unmodifiableList(copied);
    }

    /**
     * 新規構築用のコンストラクタ
     */
    private Resume(UUID userId, ResumeName name, LocalDate date,
            FullName fullName,
            List<Career> careers, List<Project> projects,
            List<Certification> certifications, List<Portfolio> portfolios, List<SocialLink> socialLinks,
            List<SelfPromotion> selfPromotions) {
        super();
        this.userId = userId;
        this.name = name;
        this.date = date;
        this.fullName = fullName;
        this.createdAt = LocalDateTime.now();
        this.updatedAt = LocalDateTime.now();
        this.careers = careers;
        this.projects = projects;
        this.certifications = certifications;
        this.portfolios = portfolios;
        this.socialLinks = socialLinks;
        this.selfPromotions = selfPromotions;
    }

    /**
     * 再構築用のコンストラクタ
     */
    private Resume(UUID id, UUID userId, ResumeName name, LocalDate date, FullName fullName,
            LocalDateTime createdAt, LocalDateTime updatedAt, List<Career> careers, List<Project> projects,
            List<Certification> certifications, List<Portfolio> portfolios, List<SocialLink> socialLinks,
            List<SelfPromotion> selfPromotions) {
        super(id);
        this.userId = userId;
        this.name = name;
        this.date = date;
        this.fullName = fullName;
        this.createdAt = createdAt;
        this.updatedAt = updatedAt;
        this.careers = careers;
        this.projects = projects;
        this.certifications = certifications;
        this.portfolios = portfolios;
        this.socialLinks = socialLinks;
        this.selfPromotions = selfPromotions;
    }

    /**
     * 新規構築用のファクトリーメソッド
     *
     * @param notification   通知オブジェクト
     * @param userId         ユーザーID
     * @param name           職務経歴書名
     * @param fullName       氏名
     * @param date           日付
     * @param careers        職歴リスト
     * @param projects       プロジェクトリスト
     * @param certifications 資格リスト
     * @param portfolios     ポートフォリオリスト
     * @param socialLinks    ソーシャルリンクリスト
     * @param selfPromotions 自己PRリスト
     * @return 職務経歴書エンティティ
     */
    public static Resume create(Notification notification, UUID userId, ResumeName name, LocalDate date,
            FullName fullName,
            List<Career> careers,
            List<Project> projects, List<Certification> certifications, List<Portfolio> portfolios,
            List<SocialLink> socialLinks, List<SelfPromotion> selfPromotions) {

        validateOnCreate(notification, name, date);
        throwIfInvalid(notification);

        return new Resume(userId, name, date, fullName, careers, projects, certifications, portfolios,
                socialLinks, selfPromotions);
    }

    /**
     * 再構築用のファクトリーメソッド
     */
    public static Resume reconstruct(UUID id, UUID userId, ResumeName name, LocalDate date,
            FullName fullName,
            LocalDateTime createdAt, LocalDateTime updatedAt,
            List<Career> careers, List<Project> projects, List<Certification> certifications,
            List<Portfolio> portfolios, List<SocialLink> socialLinks,
            List<SelfPromotion> selfPromotions) {
        return new Resume(id, userId, name, date, fullName, createdAt, updatedAt, careers, projects, certifications,
                portfolios, socialLinks, selfPromotions);
    }

    /**
     * 職務経歴書名を変更する
     *
     * @param notification 通知オブジェクト
     * @param name         新しい職務経歴書名
     * @return 変更後の職務経歴書エンティティ
     */
    public Resume changeName(Notification notification, ResumeName name) {
        if (name == null) {
            notification.addError("name", "職務経歴書名は入力必須です。");
        }
        throwIfInvalid(notification);
        return new Resume(this.id, this.userId, name, this.date, this.fullName,
                this.createdAt, LocalDateTime.now(),
                this.careers, this.projects,
                this.certifications, this.portfolios, this.socialLinks, this.selfPromotions);
    }

    /**
     * 氏名を変更する
     *
     * @param notification 通知オブジェクト
     * @param fullName     新しい氏名
     * @return 変更後の職務経歴書エンティティ
     */
    public Resume ChangeFullName(Notification notification, FullName fullName) {
        if (fullName == null) {
            notification.addError("fullName", "氏名は入力必須です。");
        }
        throwIfInvalid(notification);
        return new Resume(this.id, this.userId, this.name, this.date, fullName,
                this.createdAt, LocalDateTime.now(),
                this.careers, this.projects,
                this.certifications, this.portfolios, this.socialLinks, this.selfPromotions);
    }

    /**
     * 日付を変更する
     *
     * @param notification 通知オブジェクト
     * @param date         新しい日付
     * @return 変更後の職務経歴書エンティティ
     */
    public Resume changeDate(Notification notification, LocalDate date) {
        if (date == null) {
            notification.addError("date", "日付は入力必須です。");
        }
        throwIfInvalid(notification);
        return new Resume(this.id, this.userId, this.name, date, this.fullName,
                this.createdAt, LocalDateTime.now(),
                this.careers, this.projects,
                this.certifications, this.portfolios, this.socialLinks, this.selfPromotions);
    }

    /**
     * 職歴を追加する
     *
     * @param notification 通知オブジェクト
     * @param career       追加する職歴
     * @return 変更後の職務経歴書エンティティ
     */
    public Resume addCareer(Notification notification, Career career) {
        if (career == null) {
            notification.addError("career", "職歴は入力必須です。");
            throwIfInvalid(notification);
            return this;
        }

        throwIfInvalid(notification);

        // 期間重複チェック
        validateIsCareerOverlap(career);

        List<Career> updatedCareers = new ArrayList<>(this.careers);
        updatedCareers.add(career);
        return new Resume(this.id, this.userId, this.name, this.date, this.fullName,
                this.createdAt, LocalDateTime.now(),
                updatedCareers, this.projects, this.certifications,
                this.portfolios, this.socialLinks, this.selfPromotions);
    }

    /**
     * 職歴を更新する
     *
     * @param notification  通知オブジェクト
     * @param updatedCareer 更新後の職歴エンティティ
     * @return 変更後の職務経歴書エンティティ
     */
    public Resume updateCareer(Notification notification, Career updatedCareer) {
        if (updatedCareer == null) {
            notification.addError("career", "職歴は入力必須です。");
            throwIfInvalid(notification);
            return this;
        }

        throwIfInvalid(notification);

        // 期間重複チェック
        validateIsCareerOverlap(updatedCareer);

        List<Career> updatedCareers = this.careers.stream()
                .map(career -> career.getId().equals(updatedCareer.getId()) ? updatedCareer : career)
                .toList();
        return new Resume(this.id, this.userId, this.name, this.date, this.fullName,
                this.createdAt, LocalDateTime.now(),
                updatedCareers, this.projects, this.certifications,
                this.portfolios, this.socialLinks, this.selfPromotions);
    }

    /**
     * 職歴を削除する
     *
     * @param careerId 削除する職歴の識別子
     * @return 変更後の職務経歴書エンティティ
     */
    public Resume removeCareer(UUID careerId) {
        List<Career> updatedCareers = this.careers.stream()
                .filter(career -> !career.getId().equals(careerId))
                .toList();
        return new Resume(this.id, this.userId, this.name, this.date, this.fullName,
                this.createdAt, LocalDateTime.now(),
                updatedCareers, this.projects, this.certifications,
                this.portfolios, this.socialLinks, this.selfPromotions);
    }

    /**
     * 職歴の在籍期間の重複を検証する
     *
     * @param targetCareer 対象の職歴エンティティ
     */
    private void validateIsCareerOverlap(Career targetCareer) {
        List<String> overlappingCompanies = new ArrayList<>();

        for (Career existingCareer : this.careers) {
            // 同一エンティティの場合はスキップ
            if (existingCareer.getId().equals(targetCareer.getId())) {
                continue;
            }

            // 2つの職歴が両方とも継続中の場合は重複
            if (targetCareer.getPeriod().isActive() && existingCareer.getPeriod().isActive()) {
                overlappingCompanies.add(existingCareer.getCompanyName().getValue());
                continue;
            }

            // targetCareerのみ継続中の場合
            if (targetCareer.getPeriod().isActive()) {
                // 既存の職歴が継続中の職歴の開始日以降にあれば重複
                if (!existingCareer.getPeriod().getStartDate().isBefore(targetCareer.getPeriod().getStartDate())) {
                    overlappingCompanies.add(existingCareer.getCompanyName().getValue());
                }
                continue;
            }

            // existingCareerのみ継続中の場合
            if (existingCareer.getPeriod().isActive()) {
                // 追加する職歴の開始日が、継続中の職歴の開始日以降なら重複
                if (!targetCareer.getPeriod().getStartDate().isBefore(existingCareer.getPeriod().getStartDate())) {
                    overlappingCompanies.add(existingCareer.getCompanyName().getValue());
                }
                continue;
            }

            // どちらも継続中でない場合は期間の重なりをチェック
            if (!existingCareer.getPeriod().getEndDate().isBefore(targetCareer.getPeriod().getStartDate())
                    && !existingCareer.getPeriod().getStartDate().isAfter(targetCareer.getPeriod().getEndDate())) {
                overlappingCompanies.add(existingCareer.getCompanyName().getValue());
            }
        }

        if (!overlappingCompanies.isEmpty()) {
            String message = String.format("「%s」と「%s」の期間が重複しています。",
                    targetCareer.getCompanyName().getValue(),
                    String.join("、", overlappingCompanies));
            throw new DomainException(message);
        }
    }

    /**
     * プロジェクトを追加する
     *
     * @param notification 通知オブジェクト
     * @param project      追加するプロジェクト
     * @return 変更後の職務経歴書エンティティ
     */
    public Resume addProject(Notification notification, Project project) {
        if (project == null) {
            notification.addError("project", "プロジェクトは入力必須です。");
            throwIfInvalid(notification);
            return this;
        }

        throwIfInvalid(notification);

        List<Project> updatedProjects = new ArrayList<>(this.projects);
        updatedProjects.add(project);
        return new Resume(this.id, this.userId, this.name, this.date, this.fullName,
                this.createdAt, LocalDateTime.now(),
                this.careers, updatedProjects, this.certifications,
                this.portfolios, this.socialLinks, this.selfPromotions);
    }

    /**
     * プロジェクトを更新する
     *
     * @param notification   通知オブジェクト
     * @param updatedProject 更新するプロジェクトエンティティ
     * @return 変更後の職務経歴書エンティティ
     */
    public Resume updateProject(Notification notification, Project updatedProject) {
        if (updatedProject == null) {
            notification.addError("project", "プロジェクトは入力必須です。");
            throwIfInvalid(notification);
            return this;
        }

        throwIfInvalid(notification);

        List<Project> updatedProjects = this.projects.stream()
                .map(project -> project.getId().equals(updatedProject.getId()) ? updatedProject : project)
                .toList();
        return new Resume(this.id, this.userId, this.name, this.date, this.fullName,
                this.createdAt, LocalDateTime.now(),
                this.careers, updatedProjects, this.certifications,
                this.portfolios, this.socialLinks, this.selfPromotions);
    }

    /**
     * プロジェクトを削除する
     *
     * @param projectId 削除するプロジェクトの識別子
     * @return 変更後の職務経歴書エンティティ
     */
    public Resume removeProject(UUID projectId) {
        List<Project> updatedProjects = this.projects.stream()
                .filter(project -> !project.getId().equals(projectId))
                .toList();
        return new Resume(this.id, this.userId, this.name, this.date, this.fullName,
                this.createdAt, LocalDateTime.now(),
                this.careers, updatedProjects, this.certifications,
                this.portfolios, this.socialLinks, this.selfPromotions);
    }

    /**
     * 資格を追加する
     *
     * @param notification  通知オブジェクト
     * @param certification 追加する資格
     * @return 変更後の職務経歴書エンティティ
     */
    public Resume addCertification(Notification notification, Certification certification) {
        if (certification == null) {
            notification.addError("certification", "資格は入力必須です。");
            throwIfInvalid(notification);
            return this;
        }

        throwIfInvalid(notification);

        List<Certification> updatedCertifications = new ArrayList<>(this.certifications);
        updatedCertifications.add(certification);
        return new Resume(this.id, this.userId, this.name, this.date, this.fullName,
                this.createdAt, LocalDateTime.now(),
                this.careers, this.projects, updatedCertifications,
                this.portfolios, this.socialLinks, this.selfPromotions);
    }

    /**
     * 資格を更新する
     *
     * @param notification         通知オブジェクト
     * @param updatedCertification 更新する資格エンティティ
     * @return 変更後の職務経歴書エンティティ
     */
    public Resume updateCertification(Notification notification, Certification updatedCertification) {
        if (updatedCertification == null) {
            notification.addError("certification", "資格は入力必須です。");
            throwIfInvalid(notification);
            return this;
        }

        throwIfInvalid(notification);

        List<Certification> updatedCertifications = this.certifications.stream()
                .map(certification -> certification.getId().equals(updatedCertification.getId()) ? updatedCertification
                        : certification)
                .toList();
        return new Resume(this.id, this.userId, this.name, this.date, this.fullName,
                this.createdAt, LocalDateTime.now(),
                this.careers, this.projects, updatedCertifications,
                this.portfolios, this.socialLinks, this.selfPromotions);
    }

    /**
     * 資格を削除する
     *
     * @param certificationId 削除する資格の識別子
     * @return 変更後の職務経歴書エンティティ
     */
    public Resume removeCertification(UUID certificationId) {
        List<Certification> updatedCertifications = this.certifications.stream()
                .filter(certification -> !certification.getId().equals(certificationId))
                .toList();
        return new Resume(this.id, this.userId, this.name, this.date, this.fullName,
                this.createdAt, LocalDateTime.now(),
                this.careers, this.projects, updatedCertifications,
                this.portfolios, this.socialLinks, this.selfPromotions);
    }

    /**
     * ポートフォリオを追加する
     *
     * @param notification 通知オブジェクト
     * @param portfolio    追加するポートフォリオ
     * @return 変更後の職務経歴書エンティティ
     */
    public Resume addPortfolio(Notification notification, Portfolio portfolio) {
        if (portfolio == null) {
            notification.addError("portfolio", "ポートフォリオは入力必須です。");
            throwIfInvalid(notification);
            return this;
        }

        throwIfInvalid(notification);

        List<Portfolio> updatedPortfolios = new ArrayList<>(this.portfolios);
        updatedPortfolios.add(portfolio);
        return new Resume(this.id, this.userId, this.name, this.date, this.fullName,
                this.createdAt, LocalDateTime.now(),
                this.careers, this.projects, this.certifications,
                updatedPortfolios, this.socialLinks, this.selfPromotions);
    }

    /**
     * ポートフォリオを更新する
     *
     * @param notification     通知オブジェクト
     * @param updatedPortfolio 更新するポートフォリオ
     * @return 変更後の職務経歴書エンティティ
     */
    public Resume updatePortfolio(Notification notification, Portfolio updatedPortfolio) {
        if (updatedPortfolio == null) {
            notification.addError("portfolio", "ポートフォリオは入力必須です。");
            throwIfInvalid(notification);
            return this;
        }

        throwIfInvalid(notification);

        List<Portfolio> updatedPortfolios = this.portfolios.stream()
                .map(portfolio -> portfolio.getId().equals(updatedPortfolio.getId()) ? updatedPortfolio : portfolio)
                .toList();
        return new Resume(this.id, this.userId, this.name, this.date, this.fullName,
                this.createdAt, LocalDateTime.now(),
                this.careers, this.projects, this.certifications,
                updatedPortfolios, this.socialLinks, this.selfPromotions);
    }

    /**
     * ポートフォリオを削除する
     *
     * @param portfolioId 削除するポートフォリオの識別子
     * @return 変更後の職務経歴書エンティティ
     */
    public Resume removePortfolio(UUID portfolioId) {
        List<Portfolio> updatedPortfolios = this.portfolios.stream()
                .filter(portfolio -> !portfolio.getId().equals(portfolioId))
                .toList();
        return new Resume(this.id, this.userId, this.name, this.date, this.fullName,
                this.createdAt, LocalDateTime.now(),
                this.careers, this.projects, this.certifications,
                updatedPortfolios, this.socialLinks, this.selfPromotions);
    }

    /**
     * ソーシャルリンクを追加する
     *
     * @param notification 通知オブジェクト
     * @param sociealLink  追加するソーシャルリンク
     * @return 変更後の職務経歴書エンティティ
     */
    public Resume addSociealLink(Notification notification, SocialLink sociealLink) {
        if (sociealLink == null) {
            notification.addError("socialLink", "ソーシャルリンクは入力必須です。");
            throwIfInvalid(notification);
            return this;
        }

        throwIfInvalid(notification);

        List<SocialLink> updatedSocialLinks = new ArrayList<>(this.socialLinks);
        updatedSocialLinks.add(sociealLink);
        return new Resume(this.id, this.userId, this.name, this.date, this.fullName,
                this.createdAt, LocalDateTime.now(),
                this.careers, this.projects, this.certifications,
                this.portfolios, updatedSocialLinks, this.selfPromotions);
    }

    /**
     * ソーシャルリンクを更新する
     *
     * @param notification       通知オブジェクト
     * @param updatedSociealLink 更新するソーシャルリンク
     * @return 変更後の職務経歴書エンティティ
     */
    public Resume updateSociealLink(Notification notification, SocialLink updatedSociealLink) {
        if (updatedSociealLink == null) {
            notification.addError("socialLink", "ソーシャルリンクは入力必須です。");
            throwIfInvalid(notification);
            return this;
        }

        throwIfInvalid(notification);

        List<SocialLink> updatedSocialLinks = this.socialLinks.stream()
                .map(sociealLink -> sociealLink.getId().equals(updatedSociealLink.getId()) ? updatedSociealLink
                        : sociealLink)
                .toList();
        return new Resume(this.id, this.userId, this.name, this.date, this.fullName,
                this.createdAt, LocalDateTime.now(),
                this.careers, this.projects, this.certifications,
                this.portfolios, updatedSocialLinks, this.selfPromotions);
    }

    /**
     * ソーシャルリンクを削除する
     *
     * @param sociealLinkId 削除するソーシャルリンクの識別子
     * @return 変更後の職務経歴書エンティティ
     */
    public Resume removeSociealLink(UUID sociealLinkId) {
        List<SocialLink> updatedSocialLinks = this.socialLinks.stream()
                .filter(sociealLink -> !sociealLink.getId().equals(sociealLinkId))
                .toList();
        return new Resume(this.id, this.userId, this.name, this.date, this.fullName,
                this.createdAt, LocalDateTime.now(),
                this.careers, this.projects, this.certifications,
                this.portfolios, updatedSocialLinks, this.selfPromotions);
    }

    /**
     * 自己PRを追加する
     *
     * @param notification  通知オブジェクト
     * @param selfPromotion 追加する自己PR
     * @return 変更後の職務経歴書エンティティ
     */
    public Resume addSelfPromotion(Notification notification, SelfPromotion selfPromotion) {
        if (selfPromotion == null) {
            notification.addError("selfPromotion", "自己PRは入力必須です。");
            throwIfInvalid(notification);
            return this;
        }

        throwIfInvalid(notification);

        List<SelfPromotion> updatedSelfPromotions = new ArrayList<>(this.selfPromotions);
        updatedSelfPromotions.add(selfPromotion);
        return new Resume(this.id, this.userId, this.name, this.date, this.fullName,
                this.createdAt, LocalDateTime.now(),
                this.careers, this.projects, this.certifications,
                this.portfolios, this.socialLinks, updatedSelfPromotions);
    }

    /**
     * 自己PRを削除する
     *
     * @param selfPromotionId 削除する自己PRの識別子
     * @return 変更後の職務経歴書エンティティ
     */
    public Resume removeSelfPromotion(UUID selfPromotionId) {
        List<SelfPromotion> updatedSelfPromotions = this.selfPromotions.stream()
                .filter(selfPromotion -> !selfPromotion.getId().equals(selfPromotionId))
                .toList();
        return new Resume(this.id, this.userId, this.name, this.date, this.fullName,
                this.createdAt, LocalDateTime.now(),
                this.careers, this.projects, this.certifications,
                this.portfolios, this.socialLinks, updatedSelfPromotions);
    }

    /**
     * 自己PRを更新する
     *
     * @param notification         通知オブジェクト
     * @param updatedSelfPromotion 更新する自己PR
     * @return 変更後の職務経歴書エンティティ
     */
    public Resume updateSelfPromotion(Notification notification, SelfPromotion updatedSelfPromotion) {
        if (updatedSelfPromotion == null) {
            notification.addError("selfPromotion", "自己PRは入力必須です。");
            throwIfInvalid(notification);
            return this;
        }

        throwIfInvalid(notification);

        List<SelfPromotion> updatedSelfPromotions = this.selfPromotions.stream()
                .map(selfPromotion -> selfPromotion.getId().equals(updatedSelfPromotion.getId()) ? updatedSelfPromotion
                        : selfPromotion)
                .toList();
        return new Resume(this.id, this.userId, this.name, this.date, this.fullName,
                this.createdAt, LocalDateTime.now(),
                this.careers, this.projects, this.certifications,
                this.portfolios, this.socialLinks, updatedSelfPromotions);
    }

    /**
     * 新規作成時の必須チェック
     */
    private static void validateOnCreate(Notification notification, ResumeName name, LocalDate date) {
        if (name == null) {
            notification.addError("name", "職務経歴書名は入力必須です。");
        }
        if (date == null) {
            notification.addError("date", "日付は入力必須です。");
        }
    }

    /**
     * NotificationにエラーがあればDomainExceptionをスローする
     *
     * @param notification 通知オブジェクト
     */
    private static void throwIfInvalid(Notification notification) {
        if (notification != null && notification.hasErrors()) {
            throw new DomainException(notification.getErrors());
        }
    }
}
