package com.example.keirekipro.infrastructure.query.certification;

import java.util.List;

import org.apache.ibatis.annotations.Mapper;

import lombok.Data;

/**
 * 資格マスタクエリマッパー
 */
@Mapper
public interface CertificationQueryMapper {

    /**
     * 資格マスタを全件取得する
     *
     * @return 資格マスタ行リスト
     */
    List<CertificationRow> selectAll();

    /**
     * 資格マスタ行
     */
    @Data
    class CertificationRow {
        /**
         * 資格名
         */
        private String name;
    }
}
