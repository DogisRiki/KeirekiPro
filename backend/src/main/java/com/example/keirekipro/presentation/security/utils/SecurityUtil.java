package com.example.keirekipro.presentation.security.utils;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.util.Base64;

import org.springframework.stereotype.Component;

/**
 * OIDCで使用するユーティリティクラス
 * PKCEとstate値の生成を行う
 */
@Component
public class SecurityUtil {

    /**
     * 乱数ジェネレータ
     */
    private final SecureRandom secureRandom = new SecureRandom();

    /**
     * Base64 URLエンコーダー
     */
    private final Base64.Encoder base64Encoder = Base64.getUrlEncoder().withoutPadding();

    /**
     * セキュリティトークンとして利用するためのランダムな値を生成する
     * このメソッドは、PKCEのcode_verifierやCSRF対策のstateなど、任意のセキュリティ用途に使用する
     * 32バイトのランダムなバイト列をBase64URLエンコードした値（約43文字のASCII文字列）を返す
     *
     * @return Base64URLエンコードされたランダムトークン
     */
    public String generateRandomToken() {
        byte[] bytes = new byte[32];
        secureRandom.nextBytes(bytes);
        return base64Encoder.encodeToString(bytes);
    }

    /**
     * code_verifierからcode_challengeを生成する
     * SHA-256ハッシュアルゴリズムを使用し、RFC7636で定義されたS256メソッドに準拠する
     *
     * @param codeVerifier PKCE用のcode_verifier
     * @return SHA-256ハッシュをBase64URLエンコードしたcode_challenge
     * @throws NoSuchAlgorithmException ハッシュアルゴリズムが利用できない場合
     */
    public String generateCodeChallenge(String codeVerifier) {
        try {
            // SHA-256ハッシュアルゴリズムのインスタンスを取得
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            // code_verifierをハッシュ化
            byte[] hash = digest.digest(codeVerifier.getBytes(StandardCharsets.UTF_8));
            // ハッシュ値をBase64URLエンコード
            return base64Encoder.encodeToString(hash);
        } catch (NoSuchAlgorithmException e) {
            throw new RuntimeException("SHA-256が使用できません。", e);
        }
    }

    /**
     * 任意の桁数の数値を0埋めで生成する
     * 例: digits=6 → 000001〜999999
     *
     * @param digits 生成する桁数
     * @return 0埋めされた乱数文字列
     */
    public String generateRandomNumber(int digits) {
        if (digits < 1) {
            throw new IllegalArgumentException("桁数は1以上を指定してください。digits=" + digits);
        }
        int bound = (int) Math.pow(10, digits);
        int num = secureRandom.nextInt(bound);
        // 0埋めして返す
        return String.format("%0" + digits + "d", num);
    }
}
