package com.example.keirekipro.domain.service.resume;

import java.util.List;

import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;

import org.springframework.stereotype.Service;

import lombok.RequiredArgsConstructor;

/**
 * 職務経歴書の重複チェックドメインサービス
 */
@Service
@RequiredArgsConstructor
public class ResumeNameDuplicationCheckService {

    private final ResumeRepository resumeRepository;

    /**
     * ドメインサービスを実行する
     *
     * @param resume 職務経歴書エンティティ
     * @return 重複チェック結果
     */
    public boolean execute(Resume resume) {
        List<Resume> resumeList = resumeRepository.findAll(resume.getUserId());
        return resumeList.stream()
                // 「同じID」の場合はスキップ = 自分自身は除外
                .filter(d -> !d.getId().equals(resume.getId()))
                // 名前が同じなら重複
                .anyMatch(d -> d.getName().equals(resume.getName()));
    }
}
