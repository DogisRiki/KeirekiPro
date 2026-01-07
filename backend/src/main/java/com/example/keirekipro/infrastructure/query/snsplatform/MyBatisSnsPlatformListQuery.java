package com.example.keirekipro.infrastructure.query.snsplatform;

import java.util.List;
import java.util.stream.Collectors;

import com.example.keirekipro.usecase.query.snsplatform.SnsPlatformListQuery;
import com.example.keirekipro.usecase.query.snsplatform.dto.SnsPlatformListQueryDto;

import org.springframework.stereotype.Repository;

import lombok.RequiredArgsConstructor;

/**
 * SNSプラットフォーム一覧取得クエリ実装
 */
@Repository
@RequiredArgsConstructor
public class MyBatisSnsPlatformListQuery implements SnsPlatformListQuery {

    private final SnsPlatformQueryMapper mapper;

    @Override
    public SnsPlatformListQueryDto findAll() {
        List<SnsPlatformQueryMapper.SnsPlatformRow> rows = mapper.selectAll();

        List<String> names = rows.stream()
                .map(SnsPlatformQueryMapper.SnsPlatformRow::getName)
                .collect(Collectors.toList());

        return SnsPlatformListQueryDto.builder()
                .names(names)
                .build();
    }
}
