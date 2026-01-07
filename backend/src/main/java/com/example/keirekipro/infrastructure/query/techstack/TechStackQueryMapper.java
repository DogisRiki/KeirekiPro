package com.example.keirekipro.infrastructure.query.techstack;

import java.util.List;

import org.apache.ibatis.annotations.Mapper;

import lombok.Data;

/**
 * 技術スタックマスタクエリマッパー
 */
@Mapper
public interface TechStackQueryMapper {

    /**
     * 技術スタックマスタを全件取得する
     *
     * @return 技術スタックマスタ行リスト
     */
    List<TechStackRow> selectAll();

    /**
     * 技術スタックマスタ行
     */
    @Data
    class TechStackRow {
        /**
         * メインカテゴリ
         */
        private String mainCategory;

        /**
         * サブカテゴリ
         */
        private String subCategory;

        /**
         * 技術名
         */
        private String name;
    }
}
