package com.example.keirekipro.infrastructure.repository.snsplatform;

import java.util.List;

import org.apache.ibatis.annotations.Mapper;

/**
 * SNSプラットフォームマスタマッパー
 */
@Mapper
public interface SnsPlatformMapper {

    /**
     * SNSプラットフォームマスタを全件取得する
     *
     * @return SNSプラットフォームマスタDTOリスト
     */
    List<SnsPlatformDto> selectAll();
}
