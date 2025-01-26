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
     * 全ての職務経歴書を取得する
     */
    List<Resume> findAll(UUID userId);

    /**
     * 単一の職務経歴書を取得する
     */
    Optional<Resume> find(UUID userId, UUID resumeId);

    /**
     * 職務経歴書を保存する（新規作成または更新）
     */
    void save(Resume resume);

    /**
     * 職務経歴書を削除する
     */
    void delete(UUID userId, UUID resumeId);
}
