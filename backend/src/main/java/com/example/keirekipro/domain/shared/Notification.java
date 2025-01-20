package com.example.keirekipro.domain.shared;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import lombok.Getter;

/**
 * 複数のドメインエラーを一時的に蓄積する通知クラス
 */
@Getter
public class Notification {

    /**
     * 蓄積したエラー
     */
    private final Map<String, List<String>> errors = new HashMap<>();

    /**
     * エラーを追加する
     *
     * @param fieldName    フィールド名
     * @param errorMessage エラーメッセージ
     */
    public void addError(String fieldName, String errorMessage) {
        errors.computeIfAbsent(fieldName, k -> new ArrayList<>()).add(errorMessage);
    }

    /**
     * エラーが存在するかをチェックする
     *
     * @return チェック結果(エラーが存在する: true, エラーが存在しない: false)
     */
    public boolean hasErrors() {
        return !errors.isEmpty();
    }
}
