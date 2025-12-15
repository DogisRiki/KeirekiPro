package com.example.keirekipro.usecase.resume;

import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Link;
import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.model.resume.SocialLink;
import com.example.keirekipro.domain.repository.resume.ResumeRepository;
import com.example.keirekipro.presentation.resume.dto.UpdateSocialLinkRequest;
import com.example.keirekipro.shared.Notification;
import com.example.keirekipro.usecase.resume.dto.ResumeInfoUseCaseDto;
import com.example.keirekipro.usecase.shared.exception.UseCaseException;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import lombok.RequiredArgsConstructor;

/**
 * SNS更新ユースケース
 */
@Service
@RequiredArgsConstructor
public class UpdateSocialLinkUseCase {

    private final ResumeRepository resumeRepository;

    /**
     * SNS更新ユースケースを実行する
     *
     * @param userId       ユーザーID
     * @param resumeId     職務経歴書ID
     * @param socialLinkId SNSID
     * @param request      リクエスト
     * @return 職務経歴書ユースケースDTO
     */
    @Transactional
    public ResumeInfoUseCaseDto execute(UUID userId, UUID resumeId, UUID socialLinkId,
            UpdateSocialLinkRequest request) {

        Resume resume = resumeRepository.find(resumeId)
                .orElseThrow(() -> new UseCaseException("職務経歴書が存在しません。"));

        if (!resume.getUserId().equals(userId)) {
            throw new UseCaseException("職務経歴書が存在しません。");
        }

        SocialLink existing = resume.getSocialLinks().stream()
                .filter(s -> s.getId().equals(socialLinkId))
                .findFirst()
                .orElseThrow(() -> new UseCaseException("対象のSNSが存在しません。"));

        Notification notification = new Notification();

        Link link = Link.create(notification, request.getLink());

        SocialLink updatedSocialLink = existing
                .changeName(notification, request.getName())
                .changeLink(notification, link);

        Resume updated = resume.updateSociealLink(notification, updatedSocialLink);

        resumeRepository.save(updated);

        return ResumeInfoUseCaseDto.convertToUseCaseDto(updated);
    }
}
