package com.example.keirekipro.usecase.shared.exception;

/**
 * ユースケース層でリソースが見つからない場合の例外
 */
public class ResourceNotFoundUseCaseException extends UseCaseException {

    /**
     * メッセージのみのコンストラクタ
     *
     * @param message エラーメッセージ
     */
    public ResourceNotFoundUseCaseException(String message) {
        super(message);
    }
}
