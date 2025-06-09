package com.example.keirekipro.infrastructure.repository.resume;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;

/**
 * 職務経歴書マッパー
 */
@Mapper
public interface ResumeMapper {

    /**
     * ユーザーIDから職務経歴書一覧を取得する
     *
     * @param userId ユーザーID
     * @return 職務経歴書リストDTO
     */
    List<ResumeDto> selectAllByUserId(@Param("userId") UUID userId);

    /**
     * 職務経歴書IDから単一の職務経歴書を取得する
     *
     * @param resumeId 職務経歴書ID
     * @return 職務経歴書DTO
     */
    Optional<ResumeDto> selectByResumeId(@Param("resumeId") UUID resumeId);

    /**
     * 職務経歴書を作成/更新する
     *
     * @param resumeDto 職務経歴書DTO
     */
    void upsert(ResumeDto resumeDto);

    /**
     * 職務経歴書を削除する
     *
     * @param resumeId 職務経歴書ID
     */
    void delete(@Param("resumeId") UUID resumeId);

    /**
     * 職務経歴書IDに紐づく職歴一覧を取得する
     *
     * @param resumeId 職務経歴書ID
     * @return 職歴リストDTO
     */
    List<ResumeDto.CareerDto> selectCareersByResumeId(@Param("resumeId") UUID resumeId);

    /**
     * 職歴を挿入する
     *
     * @param careerDto 職歴DTO
     */
    void insertCareer(@Param("dto") ResumeDto.CareerDto careerDto);

    /**
     * 職歴を更新する
     *
     * @param careerDto 職歴DTO
     */
    void updateCareer(@Param("dto") ResumeDto.CareerDto careerDto);

    /**
     * 職歴を削除する
     *
     * @param careerId 職歴ID
     */
    void deleteCareer(@Param("careerId") UUID careerId);

    /**
     * 職務経歴書IDに紐づくすべての職歴を削除する
     *
     * @param resumeId 職務経歴書ID
     */
    void deleteCareersByResumeId(@Param("resumeId") UUID resumeId);

    /**
     * 職務経歴書IDに紐づくプロジェクト一覧を取得する
     *
     * @param resumeId 職務経歴書ID
     * @return プロジェクトリストDTO
     */
    List<ResumeDto.ProjectDto> selectProjectsByResumeId(@Param("resumeId") UUID resumeId);

    /**
     * プロジェクトを挿入する
     *
     * @param projectDto プロジェクトDTO
     */
    void insertProject(@Param("dto") ResumeDto.ProjectDto projectDto);

    /**
     * プロジェクトを更新する
     *
     * @param projectDto プロジェクトDTO
     */
    void updateProject(@Param("dto") ResumeDto.ProjectDto projectDto);

    /**
     * プロジェクトを削除する
     *
     * @param projectId プロジェクトID
     */
    void deleteProject(@Param("projectId") UUID projectId);

    /**
     * 職務経歴書IDに紐づくすべてのプロジェクトを削除する
     *
     * @param resumeId 職務経歴書ID
     */
    void deleteProjectsByResumeId(@Param("resumeId") UUID resumeId);

    /**
     * 職務経歴書IDに紐づく資格一覧を取得する
     *
     * @param resumeId 職務経歴書ID
     * @return 資格DTOリスト
     */
    List<ResumeDto.CertificationDto> selectCertificationsByResumeId(@Param("resumeId") UUID resumeId);

    /**
     * 資格を挿入する
     *
     * @param certificationDto 資格DTO
     */
    void insertCertification(@Param("dto") ResumeDto.CertificationDto certificationDto);

    /**
     * 資格を更新する
     *
     * @param certificationDto 資格DTO
     */
    void updateCertification(@Param("dto") ResumeDto.CertificationDto certificationDto);

    /**
     * 資格を削除する
     *
     * @param certificationId 資格ID
     */
    void deleteCertification(@Param("certificationId") UUID certificationId);

    /**
     * 職務経歴書IDに紐づくすべての資格を削除する
     *
     * @param resumeId 職務経歴書ID
     */
    void deleteCertificationsByResumeId(@Param("resumeId") UUID resumeId);

    /**
     * 職務経歴書IDに紐づくポートフォリオ一覧を取得する
     *
     * @param resumeId 職務経歴書ID
     * @return ポートフォリオDTOリスト
     */
    List<ResumeDto.PortfolioDto> selectPortfoliosByResumeId(@Param("resumeId") UUID resumeId);

    /**
     * ポートフォリオを挿入する
     *
     * @param portfolioDto ポートフォリオDTO
     */
    void insertPortfolio(@Param("dto") ResumeDto.PortfolioDto portfolioDto);

    /**
     * ポートフォリオを更新する
     *
     * @param portfolioDto ポートフォリオDTO
     */
    void updatePortfolio(@Param("dto") ResumeDto.PortfolioDto portfolioDto);

    /**
     * ポートフォリオを削除する
     *
     * @param portfolioId ポートフォリオID
     */
    void deletePortfolio(@Param("portfolioId") UUID portfolioId);

    /**
     * 職務経歴書IDに紐づくすべてのポートフォリオを削除する
     *
     * @param resumeId 職務経歴書ID
     */
    void deletePortfoliosByResumeId(@Param("resumeId") UUID resumeId);

    /**
     * 職務経歴書IDに紐づくソーシャルリンク一覧を取得する
     *
     * @param resumeId 職務経歴書ID
     * @return ソーシャルリンクDTOリスト
     */
    List<ResumeDto.SocialLinkDto> selectSocialLinksByResumeId(@Param("resumeId") UUID resumeId);

    /**
     * ソーシャルリンクを挿入する
     *
     * @param socialLinkDto ソーシャルリンクDTO
     */
    void insertSocialLink(@Param("dto") ResumeDto.SocialLinkDto socialLinkDto);

    /**
     * ソーシャルリンクを更新する
     *
     * @param socialLinkDto ソーシャルリンクDTO
     */
    void updateSocialLink(@Param("dto") ResumeDto.SocialLinkDto socialLinkDto);

    /**
     * ソーシャルリンクを削除する
     *
     * @param socialLinkId ソーシャルリンクID
     */
    void deleteSocialLink(@Param("socialLinkId") UUID socialLinkId);

    /**
     * 職務経歴書IDに紐づくすべてのソーシャルリンクを削除する
     *
     * @param resumeId 職務経歴書ID
     */
    void deleteSocialLinksByResumeId(@Param("resumeId") UUID resumeId);

    /**
     * 職務経歴書IDに紐づく自己PR一覧を取得する
     *
     * @param resumeId 職務経歴書ID
     * @return 自己PR DTOリスト
     */
    List<ResumeDto.SelfPromotionDto> selectSelfPromotionsByResumeId(@Param("resumeId") UUID resumeId);

    /**
     * 自己PRを挿入する
     *
     * @param selfPromotionDto 自己PR DTO
     */
    void insertSelfPromotion(@Param("dto") ResumeDto.SelfPromotionDto selfPromotionDto);

    /**
     * 自己PRを更新する
     *
     * @param selfPromotionDto 自己PR DTO
     */
    void updateSelfPromotion(@Param("dto") ResumeDto.SelfPromotionDto selfPromotionDto);

    /**
     * 自己PRを削除する
     *
     * @param selfPromotionId 自己PR ID
     */
    void deleteSelfPromotion(@Param("selfPromotionId") UUID selfPromotionId);

    /**
     * 職務経歴書IDに紐づくすべての自己PRを削除する
     *
     * @param resumeId 職務経歴書ID
     */
    void deleteSelfPromotionsByResumeId(@Param("resumeId") UUID resumeId);
}
