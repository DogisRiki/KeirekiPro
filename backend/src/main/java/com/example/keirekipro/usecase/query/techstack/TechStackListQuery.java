package com.example.keirekipro.usecase.query.techstack;

import com.example.keirekipro.usecase.query.techstack.dto.TechStackListQueryDto;

/**
 * 技術スタック一覧取得クエリインターフェース
 */
public interface TechStackListQuery {

    /**
     * 技術スタック一覧を取得する
     *
     * @return 技術スタック一覧クエリDTO
     */
    TechStackListQueryDto findAll();
}
