package com.example.keirekipro.usecase.certification;

import java.util.List;
import java.util.stream.Collectors;

import com.example.keirekipro.infrastructure.repository.certification.CertificationDto;
import com.example.keirekipro.infrastructure.repository.certification.CertificationMapper;
import com.example.keirekipro.usecase.certification.dto.CertificationListUseCaseDto;

import org.springframework.stereotype.Service;

import lombok.RequiredArgsConstructor;

/**
 * 資格一覧取得ユースケース
 */
@Service
@RequiredArgsConstructor
public class GetCertificationListUseCase {

    private final CertificationMapper certificationMapper;

    /**
     * 資格一覧取得ユースケースを実行する
     *
     * @return 資格一覧ユースケースDTO
     */
    public CertificationListUseCaseDto execute() {

        List<CertificationDto> rows = certificationMapper.selectAll();

        List<String> names = rows.stream()
                .map(CertificationDto::getName)
                .collect(Collectors.toList());

        return CertificationListUseCaseDto.create(names);
    }
}
