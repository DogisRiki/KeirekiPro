package com.example.keirekipro.domain.service.resume;

import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.model.resume.ResumeName;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.domain.shared.exception.DomainException;

import org.springframework.stereotype.Service;

import lombok.RequiredArgsConstructor;

/**
 * 職務経歴書名の重複チェックドメインサービス
 */
@Service
@RequiredArgsConstructor
public class ResumeNameDuplicationCheckService {

    private final ResumeRepository resumeRepository;

    /**
     * 職務経歴書名の重複をチェックする
     *
     * @param userId     ユーザーID
     * @param resumeName チェック対象の職務経歴書
     * @throws DomainException 職務経歴書の重複があった場合
     */
    public void execute(UUID userId, ResumeName resumeName) {

        // 職務経歴書名がnullなら重複チェック不要
        if (resumeName == null) {
            return;
        }

        resumeRepository.findAll(userId).stream()
                // ResumeからResumeNameを取り出し
                .map(Resume::getName)
                // 引数のresumeNameと同じものを探し
                .filter(resumeName::equals)
                // 見つかったら例外を投げる
                .findAny()
                .ifPresent(n -> {
                    throw new DomainException("この職務経歴書名は既に登録されています。");
                });
    }
}
