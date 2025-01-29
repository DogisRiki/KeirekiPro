package com.example.keirekipro.presentation.shared;

import java.util.List;
import java.util.Map;

import lombok.Getter;
import lombok.RequiredArgsConstructor;

/**
 * エラーレスポンス
 *
 * @example
 *          {
 *          "message": "入力内容に誤りがあります",
 *          "errors": {
 *          "resumeName": [
 *          "職務経歴書名は20文字以内で入力してください。",
 *          "職務経歴書に「/:*?\"<>|」を含むことはできません。"
 *          ],
 *          "firstName": [
 *          "名に不正文字が含まれています。"
 *          ],
 *          "lastName": [
 *          "姓に不正文字が含まれています。"
 *          ]
 *          }
 *          }
 */
@RequiredArgsConstructor
@Getter
public class ErrorResponse {

    /**
     * ジェネラルエラーメッセージ
     */
    private final String message;

    /**
     * フィールドエラー
     */
    private final Map<String, List<String>> errors;
}
