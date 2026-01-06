package com.example.keirekipro.usecase.query.resume;

import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.usecase.query.resume.dto.ResumeBackupQueryDto;

/**
 * 職務経歴書バックアップ用クエリインターフェース
 */
public interface ResumeBackupQuery {

    /**
     * バックアップ用に職務経歴書データを取得する
     *
     * @param resumeId 職務経歴書ID
     * @param userId   ユーザーID
     * @return 職務経歴書バックアップ用DTO
     */
    Optional<ResumeBackupQueryDto> findByIdForBackup(UUID resumeId, UUID userId);
}
