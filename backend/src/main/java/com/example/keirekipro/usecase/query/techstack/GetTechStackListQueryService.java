package com.example.keirekipro.usecase.query.techstack;

import com.example.keirekipro.infrastructure.query.techstack.TechStackQuery;
import com.example.keirekipro.usecase.query.techstack.dto.TechStackListItemDto;

import org.springframework.stereotype.Service;

import lombok.RequiredArgsConstructor;

/**
 * 技術スタック一覧取得クエリサービス
 */
@Service
@RequiredArgsConstructor
public class GetTechStackListQueryService {

    private final TechStackQuery techStackQuery;

    /**
     * 技術スタック一覧取得クエリサービスを実行する
     *
     * @return 技術スタック一覧クエリDTO
     */
    public TechStackListItemDto execute() {
        return techStackQuery.selectTechStackListItem();
    }
}
