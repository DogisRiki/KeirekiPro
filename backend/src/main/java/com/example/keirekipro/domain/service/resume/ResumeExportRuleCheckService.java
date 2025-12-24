package com.example.keirekipro.domain.service.resume;

import java.util.ArrayList;
import java.util.List;

import com.example.keirekipro.domain.model.resume.FullName;
import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.shared.exception.DomainException;

import org.springframework.stereotype.Service;

/**
 * 職務経歴書エクスポート前提条件チェックドメインサービス
 */
@Service
public class ResumeExportRuleCheckService {

    /**
     * 職務経歴書エクスポート前提条件をチェックする
     *
     * @param resume 職務経歴書エンティティ
     * @throws DomainException エクスポート前提条件を満たさない場合
     */
    public void execute(Resume resume) {

        List<String> errors = new ArrayList<>();

        if (resume.getName() == null || resume.getName().getValue() == null || resume.getName().getValue().isBlank()) {
            errors.add("職務経歴書名を入力してください。");
        }

        if (resume.getDate() == null) {
            errors.add("日付を設定してください。");
        }

        FullName fullName = resume.getFullName();
        if (fullName == null) {
            errors.add("氏名（姓・名）を入力してください。");
        } else {
            if (fullName.getLastName() == null || fullName.getLastName().isBlank()) {
                errors.add("姓を入力してください。");
            }
            if (fullName.getFirstName() == null || fullName.getFirstName().isBlank()) {
                errors.add("名を入力してください。");
            }
        }

        if (resume.getCareers() == null || resume.getCareers().isEmpty()) {
            errors.add("職歴を1件以上登録してください。");
        }

        if (resume.getProjects() == null || resume.getProjects().isEmpty()) {
            errors.add("プロジェクトを1件以上登録してください。");
        }

        if (resume.getSelfPromotions() == null || resume.getSelfPromotions().isEmpty()) {
            errors.add("自己PRを1件以上登録してください。");
        }

        if (!errors.isEmpty()) {
            throw new DomainException("職務経歴書をエクスポートできません。\n- " + String.join("\n- ", errors));
        }
    }
}
