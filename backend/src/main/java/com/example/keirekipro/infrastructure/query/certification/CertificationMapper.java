package com.example.keirekipro.infrastructure.query.certification;

import java.util.List;

import org.apache.ibatis.annotations.Mapper;

/**
 * 資格マスタマッパー
 */
@Mapper
public interface CertificationMapper {

    /**
     * 資格マスタを全件取得する
     *
     * @return 資格マスタDTOリスト
     */
    List<CertificationDto> selectAll();
}
