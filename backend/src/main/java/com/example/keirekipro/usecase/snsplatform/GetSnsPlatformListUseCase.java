package com.example.keirekipro.usecase.snsplatform;

import java.util.List;
import java.util.stream.Collectors;

import com.example.keirekipro.infrastructure.repository.snsplatform.SnsPlatformDto;
import com.example.keirekipro.infrastructure.repository.snsplatform.SnsPlatformMapper;
import com.example.keirekipro.usecase.snsplatform.dto.SnsPlatformListUseCaseDto;

import org.springframework.stereotype.Service;

import lombok.RequiredArgsConstructor;

/**
 * SNSプラットフォーム一覧取得ユースケース
 */
@Service
@RequiredArgsConstructor
public class GetSnsPlatformListUseCase {

    private final SnsPlatformMapper snsPlatformMapper;

    /**
     * SNSプラットフォーム一覧取得ユースケースを実行する
     *
     * @return SNSプラットフォーム一覧ユースケースDTO
     */
    public SnsPlatformListUseCaseDto execute() {

        List<SnsPlatformDto> rows = snsPlatformMapper.selectAll();

        List<String> names = rows.stream()
                .map(SnsPlatformDto::getName)
                .collect(Collectors.toList());

        return SnsPlatformListUseCaseDto.create(names);
    }
}
