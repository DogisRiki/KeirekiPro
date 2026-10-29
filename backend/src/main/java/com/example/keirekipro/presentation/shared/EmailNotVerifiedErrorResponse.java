package com.example.keirekipro.presentation.shared;

import java.util.List;
import java.util.Map;

import com.example.keirekipro.usecase.shared.exception.EmailNotVerifiedUseCaseException.Kind;

import lombok.Getter;

/**
 * メールアドレスの確認がまだのときのエラーレスポンス
 *
 * @example
 *          {
 *          "message": "メールアドレスの確認が済んでいません。",
 *          "errors": {},
 *          "kind": "PENDING_REGISTRATION"
 *          }
 */
@Getter
public class EmailNotVerifiedErrorResponse extends ErrorResponse {

    /**
     * 確認がまだのものの種類
     */
    private final Kind kind;

    /**
     * コンストラクタ
     *
     * @param message ジェネラルエラーメッセージ
     * @param errors フィールドエラー
     * @param kind 確認がまだのものの種類
     */
    public EmailNotVerifiedErrorResponse(String message, Map<String, List<String>> errors, Kind kind) {
        super(message, errors);
        this.kind = kind;
    }
}
