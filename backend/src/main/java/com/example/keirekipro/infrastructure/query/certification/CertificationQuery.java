package com.example.keirekipro.infrastructure.query.certification;

import java.util.List;
import java.util.stream.Collectors;

import com.example.keirekipro.usecase.query.certification.dto.CertificationListItemDto;

import org.springframework.stereotype.Repository;

import lombok.RequiredArgsConstructor;

/**
 * 資格一覧取得クエリ
 */
@Repository
@RequiredArgsConstructor
public class CertificationQuery {

    private final CertificationMapper certificationMapper;

    /**
     * 資格一覧を取得して整形して返却する
     *
     * @return 資格一覧DTO
     */
    public CertificationListItemDto selectCertificationListItem() {

        List<CertificationDto> rows = certificationMapper.selectAll();

        List<String> names = rows.stream()
                .map(CertificationDto::getName)
                .collect(Collectors.toList());

        return CertificationListItemDto.create(names);
    }
}
