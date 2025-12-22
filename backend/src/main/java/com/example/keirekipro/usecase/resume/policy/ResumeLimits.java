package com.example.keirekipro.usecase.resume.policy;

import lombok.AccessLevel;
import lombok.NoArgsConstructor;

/**
 * 職務経歴書における各種上限値（件数上限など）を定義するクラス
 */
@NoArgsConstructor(access = AccessLevel.PRIVATE)
public class ResumeLimits {

    /**
     * 職務経歴書作成上限数
     */
    public static final int RESUMES_CREATION_LIMIT = 50;

    /**
     * 職歴作成上限数
     */
    public static final int CAREERS_CREATION_LIMIT = 30;

    /**
     * プロジェクト作成上限数
     */
    public static final int PROJECTS_CREATION_LIMIT = 100;

    /**
     * 資格作成上限数
     */
    public static final int CERTIFICATIONS_CREATION_LIMIT = 50;

    /**
     * SNSプラットフォーム作成上限数
     */
    public static final int SNS_PLATFORMS_CREATION_LIMIT = 10;

    /**
     * ポートフォリオ作成上限数
     */
    public static final int PORTFOLIOS_CREATION_LIMIT = 50;

    /**
     * 自己PR作成上限数
     */
    public static final int SELF_PROMOTIONS_CREATION_LIMIT = 5;
}
