package com.example.keirekipro.domain.repository.resume;

import java.util.List;
import java.util.Optional;

import com.example.keirekipro.domain.model.resume.Resume;

/**
 * 職務経歴書リポジトリ
 */
public interface ResumeRepository {
    /**
     * 全ての職務経歴書を取得する
     */
    List<Resume> findAll(String userId);

    /**
     * 単一の職務経歴書を取得する
     */
    Optional<Resume> find(String userId, String resumeId);

    /**
     * 職務経歴書を保存する（新規作成または更新）
     */
    void save(Resume resume);

    /**
     * 職務経歴書を削除する
     */
    void delete(String userId, String resumeId);
}
