package com.example.keirekipro.infrastructure.shared.aws.s3;

import java.io.IOException;
import java.time.Duration;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import com.example.keirekipro.usecase.shared.store.ObjectStore;
import com.example.keirekipro.usecase.shared.store.StoredObject;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import lombok.RequiredArgsConstructor;

import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.DeleteObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.s3.presigner.model.GetObjectPresignRequest;
import software.amazon.awssdk.services.s3.presigner.model.PresignedGetObjectRequest;

/**
 * S3オブジェクトストア
 */
@Component
@RequiredArgsConstructor
public class S3ObjectStore implements ObjectStore {

    /**
     * バケット名
     */
    @Value("${aws.s3.bucket-name}")
    private String bucketName;

    /**
     * S3クライアント
     */
    private final S3Client s3Client;

    /**
     * S3プリサイナー（署名付きURL生成用）
     */
    private final S3Presigner s3Presigner;

    /**
     * 署名付きURL変換戦略（環境差分吸収）
     */
    private final PresignedUrlTransformer presignedUrlTransformer;

    /**
     * オブジェクトを保存し、保存先キーを返す
     *
     * @param object    保存対象
     * @param keyPrefix 保存プレフィックス（末尾に/必須）
     * @return 保存されたキー
     */
    @Override
    public String put(StoredObject object, String keyPrefix) {

        String originalFilename = object.originalFilename();
        String extension = "";

        if (originalFilename != null && originalFilename.contains(".")) {
            extension = originalFilename.substring(originalFilename.lastIndexOf("."));
        }

        String key = keyPrefix + UUID.randomUUID().toString() + extension;

        Map<String, String> metadata = new HashMap<>();
        metadata.put("Content-Type", object.contentType());
        metadata.put("Original-Filename", originalFilename);

        PutObjectRequest putObjectRequest = PutObjectRequest.builder()
                .bucket(bucketName)
                .key(key)
                .contentType(object.contentType())
                .metadata(metadata)
                .build();

        s3Client.putObject(putObjectRequest, RequestBody.fromBytes(object.bytes()));

        return key;
    }

    /**
     * 任意のファイル名を指定して保存し、保存先キーを返す
     *
     * @param object    保存対象
     * @param keyPrefix 保存プレフィックス（末尾に/必須）
     * @param fileName  保存ファイル名（拡張子含む）
     * @return 保存されたキー
     */
    @Override
    public String putAs(StoredObject object, String keyPrefix, String fileName) {

        String key = keyPrefix + fileName;

        Map<String, String> metadata = new HashMap<>();
        metadata.put("Content-Type", object.contentType());
        metadata.put("Original-Filename", object.originalFilename());

        PutObjectRequest putObjectRequest = PutObjectRequest.builder()
                .bucket(bucketName)
                .key(key)
                .contentType(object.contentType())
                .metadata(metadata)
                .build();

        s3Client.putObject(putObjectRequest, RequestBody.fromBytes(object.bytes()));

        return key;
    }

    /**
     * バイト配列として取得する
     *
     * @param key オブジェクトキー
     * @return バイト配列
     */
    @Override
    public byte[] getBytes(String key) {

        GetObjectRequest getObjectRequest = GetObjectRequest.builder()
                .bucket(bucketName)
                .key(key)
                .build();

        try (ResponseInputStream<GetObjectResponse> responseInputStream = s3Client.getObject(getObjectRequest)) {
            return responseInputStream.readAllBytes();
        } catch (IOException e) {
            throw new RuntimeException("ファイル操作に失敗しました。: " + key, e);
        }
    }

    /**
     * オブジェクトを削除する
     *
     * @param key オブジェクトキー
     */
    @Override
    public void delete(String key) {
        DeleteObjectRequest deleteObjectRequest = DeleteObjectRequest.builder()
                .bucket(bucketName)
                .key(key)
                .build();

        s3Client.deleteObject(deleteObjectRequest);
    }

    /**
     * 取得用URLを発行する
     *
     * @param key オブジェクトキー
     * @param ttl 有効期限
     * @return 取得用URL
     */
    @Override
    public String issueGetUrl(String key, Duration ttl) {

        GetObjectRequest getObjectRequest = GetObjectRequest.builder()
                .bucket(bucketName)
                .key(key)
                .build();

        GetObjectPresignRequest presignRequest = GetObjectPresignRequest.builder()
                .signatureDuration(ttl)
                .getObjectRequest(getObjectRequest)
                .build();

        PresignedGetObjectRequest presignedRequest = s3Presigner.presignGetObject(presignRequest);
        String url = presignedRequest.url().toString();

        return presignedUrlTransformer.transform(url);
    }
}
