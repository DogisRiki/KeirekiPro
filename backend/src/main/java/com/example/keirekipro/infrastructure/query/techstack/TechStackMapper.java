package com.example.keirekipro.infrastructure.query.techstack;

import java.util.List;

import org.apache.ibatis.annotations.Mapper;

/**
 * 技術スタックマスタマッパー
 */
@Mapper
public interface TechStackMapper {

    /**
     * 技術スタックマスタを全件取得する
     *
     * @return 技術スタックマスタDTOリスト
     */
    List<TechStackDto> selectAll();
}
