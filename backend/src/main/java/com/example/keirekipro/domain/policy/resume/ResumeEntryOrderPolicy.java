package com.example.keirekipro.domain.policy.resume;

import java.text.Collator;
import java.time.YearMonth;
import java.util.Comparator;
import java.util.Locale;
import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Career;
import com.example.keirekipro.domain.model.resume.Certification;
import com.example.keirekipro.domain.model.resume.Period;
import com.example.keirekipro.domain.model.resume.Portfolio;
import com.example.keirekipro.domain.model.resume.Project;
import com.example.keirekipro.domain.model.resume.SelfPromotion;
import com.example.keirekipro.domain.model.resume.SnsPlatform;

import lombok.AccessLevel;
import lombok.NoArgsConstructor;

/**
 * 職務経歴書エントリーの並び順ポリシー
 * <p>
 * 並び順ルール:
 * <ul>
 * <li>職歴・プロジェクト: 継続中が最上位 → 終了日が新しい順 → 終了日が同じ場合は開始日が新しい順</li>
 * <li>資格: 取得日が新しい順</li>
 * <li>ポートフォリオ・SNS・自己PR: 名前/タイトルの辞書順（日本語照合）</li>
 * </ul>
 */
@NoArgsConstructor(access = AccessLevel.PRIVATE)
public final class ResumeEntryOrderPolicy {

    /**
     * 日本語の辞書順比較に使用するコレータ
     */
    private static final Collator JAPANESE_COLLATOR = Collator.getInstance(Locale.JAPANESE);

    /**
     * 職歴の並び順（新しい順）の比較規則を返す
     *
     * <p>
     * ルール:
     * <ul>
     * <li>期間の比較（継続中最上位 → 終了日降順 → 開始日降順）</li>
     * <li>期間が同一の場合は UUID の昇順で安定化</li>
     * </ul>
     *
     * @return 職歴の比較規則
     */
    public static Comparator<Career> careerDesc() {
        return (a, b) -> {
            int periodCmp = comparePeriodDesc(a != null ? a.getPeriod() : null, b != null ? b.getPeriod() : null);
            if (periodCmp != 0) {
                return periodCmp;
            }
            return compareUuidNullable(a != null ? a.getId() : null, b != null ? b.getId() : null);
        };
    }

    /**
     * プロジェクトの並び順（新しい順）の比較規則を返す
     *
     * <p>
     * ルール:
     * <ul>
     * <li>期間の比較（継続中最上位 → 終了日降順 → 開始日降順）</li>
     * <li>期間が同一の場合は UUID の昇順で安定化</li>
     * </ul>
     *
     * @return プロジェクトの比較規則
     */
    public static Comparator<Project> projectDesc() {
        return (a, b) -> {
            int periodCmp = comparePeriodDesc(a != null ? a.getPeriod() : null, b != null ? b.getPeriod() : null);
            if (periodCmp != 0) {
                return periodCmp;
            }
            return compareUuidNullable(a != null ? a.getId() : null, b != null ? b.getId() : null);
        };
    }

    /**
     * 資格の並び順（取得日が新しい順）の比較規則を返す
     *
     * <p>
     * ルール:
     * <ul>
     * <li>取得日の降順</li>
     * <li>取得日が同一の場合は UUID の昇順で安定化</li>
     * </ul>
     *
     * @return 資格の比較規則
     */
    public static Comparator<Certification> certificationDesc() {
        return (a, b) -> {
            int dateCmp = compareYearMonthDesc(a != null ? a.getDate() : null, b != null ? b.getDate() : null);
            if (dateCmp != 0) {
                return dateCmp;
            }
            return compareUuidNullable(a != null ? a.getId() : null, b != null ? b.getId() : null);
        };
    }

    /**
     * ポートフォリオの並び順（名前の辞書順）の比較規則を返す
     *
     * <p>
     * ルール:
     * <ul>
     * <li>名前の日本語辞書順（昇順）</li>
     * <li>名前が同一の場合は UUID の昇順で安定化</li>
     * </ul>
     *
     * @return ポートフォリオの比較規則
     */
    public static Comparator<Portfolio> portfolioNameAsc() {
        return (a, b) -> {
            int nameCmp = compareTextAsc(a != null ? a.getName() : null, b != null ? b.getName() : null);
            if (nameCmp != 0) {
                return nameCmp;
            }
            return compareUuidNullable(a != null ? a.getId() : null, b != null ? b.getId() : null);
        };
    }

    /**
     * SNSプラットフォームの並び順（名前の辞書順）の比較規則を返す
     *
     * <p>
     * ルール:
     * <ul>
     * <li>名前の日本語辞書順（昇順）</li>
     * <li>名前が同一の場合は UUID の昇順で安定化</li>
     * </ul>
     *
     * @return SNSプラットフォームの比較規則
     */
    public static Comparator<SnsPlatform> snsPlatFormNameAsc() {
        return (a, b) -> {
            int nameCmp = compareTextAsc(a != null ? a.getName() : null, b != null ? b.getName() : null);
            if (nameCmp != 0) {
                return nameCmp;
            }
            return compareUuidNullable(a != null ? a.getId() : null, b != null ? b.getId() : null);
        };
    }

    /**
     * 自己PRの並び順（タイトルの辞書順）の比較規則を返す
     *
     * <p>
     * ルール:
     * <ul>
     * <li>タイトルの日本語辞書順（昇順）</li>
     * <li>タイトルが同一の場合は UUID の昇順で安定化</li>
     * </ul>
     *
     * @return 自己PR の比較規則
     */
    public static Comparator<SelfPromotion> selfPromotionTitleAsc() {
        return (a, b) -> {
            int titleCmp = compareTextAsc(a != null ? a.getTitle() : null, b != null ? b.getTitle() : null);
            if (titleCmp != 0) {
                return titleCmp;
            }
            return compareUuidNullable(a != null ? a.getId() : null, b != null ? b.getId() : null);
        };
    }

    /**
     * 期間（{@link Period}）を「新しい順」で比較する
     *
     * <p>
     * ルール:
     * <ol>
     * <li>継続中（{@link Period#isActive()} が true）が最上位</li>
     * <li>両方とも非継続の場合は終了日（{@link Period#getEndDate()}）が新しい順</li>
     * <li>終了日が同じ場合は開始日（{@link Period#getStartDate()}）が新しい順</li>
     * <li>両方継続中の場合は開始日が新しい順</li>
     * </ol>
     *
     * <p>
     * null は「情報なし」として末尾扱いにする
     *
     * @param a 期間A（null許容）
     * @param b 期間B（null許容）
     * @return 比較結果（負: aが先、正: bが先、0: 同一）
     */
    private static int comparePeriodDesc(Period a, Period b) {
        if (a == null && b == null) {
            return 0;
        }
        if (a == null) {
            return 1;
        }
        if (b == null) {
            return -1;
        }

        // 継続中が最上位
        int activeCmp = Boolean.compare(b.isActive(), a.isActive());
        if (activeCmp != 0) {
            return activeCmp;
        }

        // 両方継続中: 開始日が新しい順
        if (a.isActive() && b.isActive()) {
            return compareYearMonthDesc(a.getStartDate(), b.getStartDate());
        }

        // 両方非継続: 終了日が新しい順 → 終了日が同じ場合は開始日が新しい順
        int endCmp = compareYearMonthDesc(a.getEndDate(), b.getEndDate());
        if (endCmp != 0) {
            return endCmp;
        }

        return compareYearMonthDesc(a.getStartDate(), b.getStartDate());
    }

    /**
     * {@link YearMonth} を「新しい順（降順）」で比較する
     *
     * <p>
     * null は「情報なし」として末尾扱いにする
     *
     * @param a 年月A（null許容）
     * @param b 年月B（null許容）
     * @return 比較結果（負: aが先、正: bが先、0: 同一）
     */
    private static int compareYearMonthDesc(YearMonth a, YearMonth b) {
        if (a == null && b == null) {
            return 0;
        }
        if (a == null) {
            return 1;
        }
        if (b == null) {
            return -1;
        }
        return b.compareTo(a);
    }

    /**
     * 文字列を「日本語の辞書順（昇順）」で比較する
     *
     * <p>
     * null は「情報なし」として末尾扱いにする
     *
     * @param a 文字列A（null許容）
     * @param b 文字列B（null許容）
     * @return 比較結果（負: aが先、正: bが先、0: 同一）
     */
    private static int compareTextAsc(String a, String b) {
        if (a == null && b == null) {
            return 0;
        }
        if (a == null) {
            return 1;
        }
        if (b == null) {
            return -1;
        }
        return JAPANESE_COLLATOR.compare(a, b);
    }

    /**
     * {@link UUID} を null 安全に比較する
     *
     * <p>
     * null は「情報なし」として末尾扱いする
     *
     * @param a UUID A（null許容）
     * @param b UUID B（null許容）
     * @return 比較結果（負: aが先、正: bが先、0: 同一）
     */
    private static int compareUuidNullable(UUID a, UUID b) {
        if (a == null && b == null) {
            return 0;
        }
        if (a == null) {
            return 1;
        }
        if (b == null) {
            return -1;
        }
        return a.compareTo(b);
    }
}
