package com.example.keirekipro.infrastructure.query.snsplatform;

import java.util.List;

import org.apache.ibatis.annotations.Mapper;

import lombok.Data;

/**
 * SNSプラットフォームマスタクエリマッパー
 */
@Mapper
public interface SnsPlatformQueryMapper {

    /**
     * SNSプラットフォームマスタを全件取得する
     *
     * @return SNSプラットフォームマスタ行リスト
     */
    List<SnsPlatformRow> selectAll();

    /**
     * SNSプラットフォームマスタ行
     */
    @Data
    class SnsPlatformRow {
        /**
         * プラットフォーム名
         */
        private String name;
    }
}
