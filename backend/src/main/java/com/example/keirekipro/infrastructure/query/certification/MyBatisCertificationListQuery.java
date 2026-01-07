package com.example.keirekipro.infrastructure.query.certification;

import java.util.List;
import java.util.stream.Collectors;

import com.example.keirekipro.usecase.query.certification.CertificationListQuery;
import com.example.keirekipro.usecase.query.certification.dto.CertificationListQueryDto;

import org.springframework.stereotype.Repository;

import lombok.RequiredArgsConstructor;

/**
 * 資格一覧取得クエリ実装
 */
@Repository
@RequiredArgsConstructor
public class MyBatisCertificationListQuery implements CertificationListQuery {

    private final CertificationQueryMapper mapper;

    @Override
    public CertificationListQueryDto findAll() {
        List<CertificationQueryMapper.CertificationRow> rows = mapper.selectAll();

        List<String> names = rows.stream()
                .map(CertificationQueryMapper.CertificationRow::getName)
                .collect(Collectors.toList());

        return CertificationListQueryDto.builder()
                .names(names)
                .build();
    }
}
