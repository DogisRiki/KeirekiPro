package com.example.keirekipro.infrastructure.query.techstack;

import lombok.Data;

/**
 * 技術スタックマスタDTO
 */
@Data
public class TechStackDto {

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
