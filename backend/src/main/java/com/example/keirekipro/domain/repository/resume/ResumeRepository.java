package com.example.keirekipro.domain.repository.resume;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Resume;

/**
 * 職務経歴書リポジトリ
 */
public interface ResumeRepository {
    /**
     * 対象ユーザーの全ての職務経歴書を取得する
     *
     * @param userId ユーザーID
     * @return 職務経歴書エンティティ
     */
    List<Resume> findAll(UUID userId);

    /**
     * 単一の職務経歴書を取得する
     *
     * @param resumeId 職務経歴書ID
     * @return 職務経歴書エンティティ
     */
    Optional<Resume> find(UUID resumeId);

    /**
     * 職務経歴書を保存する（新規作成または更新）
     *
     * @param resume 職務経歴書エンティティ
     */
    void save(Resume resume);

    /**
     * 職務経歴書を削除する
     *
     * @param resumeId 職務経歴書ID
     */
    void delete(UUID resumeId);
}
