package com.example.keirekipro.usecase.resume;

import java.util.Map;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

import com.example.keirekipro.domain.model.resume.Link;
import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.model.resume.SocialLink;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.presentation.resume.dto.UpdateSocialLinksRequest;
import com.example.keirekipro.shared.Notification;
import com.example.keirekipro.usecase.resume.dto.ResumeInfoUseCaseDto;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import lombok.RequiredArgsConstructor;

/**
 * 職務経歴書 ソーシャルリンク更新ユースケース
 */
@Service
@RequiredArgsConstructor
public class UpdateSocialLinksUseCase {

    private final ResumeRepository resumeRepository;

    /**
     * ソーシャルリンクを更新する
     */
    @Transactional
    public ResumeInfoUseCaseDto execute(UUID userId, UUID resumeId, UpdateSocialLinksRequest request) {

        // 職務経歴書の存在チェック
        Resume resume = resumeRepository.find(resumeId)
                .orElseThrow(() -> new UseCaseException("職務経歴書が存在しません。"));

        // 認可チェック（本人の職務経歴書か）
        if (!resume.getUserId().equals(userId)) {
            throw new UseCaseException("職務経歴書が存在しません。");
        }

        Notification notification = new Notification();

        // 更新中の職務経歴書
        Resume updatedResume = resume;

        // 既存のソーシャルリンクをIDで引けるようにマッピング
        Map<UUID, SocialLink> remainingSocialLinksById = resume.getSocialLinks().stream()
                .collect(Collectors.toMap(SocialLink::getId, Function.identity()));

        // リクエストの内容に従って追加・更新
        for (UpdateSocialLinksRequest.SocialLinkRequest socialLinkRequest : request.getSocialLinks()) {

            Link link = Link.create(notification, socialLinkRequest.getLink());

            // 新規追加
            if (socialLinkRequest.getId() == null) {
                SocialLink newSocialLink = SocialLink.create(notification, socialLinkRequest.getName(), link);
                updatedResume = updatedResume.addSociealLink(notification, newSocialLink);
                continue;
            }

            // 既存更新
            SocialLink currentSocialLink = remainingSocialLinksById.remove(socialLinkRequest.getId());
            if (currentSocialLink == null) {
                throw new UseCaseException("更新対象のSNS情報が存在しません。");
            }

            SocialLink updatedSocialLink = currentSocialLink
                    .changeName(notification, socialLinkRequest.getName())
                    .changeLink(notification, link);

            updatedResume = updatedResume.updateSociealLink(notification, updatedSocialLink);
        }

        // リクエストに含まれなかったソーシャルリンクは削除
        for (SocialLink socialLinkToDelete : remainingSocialLinksById.values()) {
            updatedResume = updatedResume.removeSociealLink(socialLinkToDelete.getId());
        }

        resumeRepository.save(updatedResume);

        return ResumeInfoUseCaseDto.convertToUseCaseDto(updatedResume);
    }
}
