package com.example.keirekipro.infrastructure.shared.aws;

import java.io.IOException;
import java.net.URI;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;
import org.springframework.web.multipart.MultipartFile;

import lombok.Getter;
import lombok.Setter;

import jakarta.annotation.PostConstruct;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.S3ClientBuilder;
import software.amazon.awssdk.services.s3.model.DeleteObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.model.S3Exception;

/**
 * AWS S3ストレージを操作する汎用クラス
 */
@Component
@Getter
@Setter
@ConfigurationProperties(prefix = "aws.s3")
public class AwsS3Client {

    /**
     * リージョン
     */
    private String region;

    /**
     * AWS SESへのエンドポイントURL(localStackの場合のみ必要)
     * localStackを使用する開発環境の場合は必要。
     * AWS本番環境ではSDKが自動的にAWSの正規エンドポイントを判断するため不要。
     */
    private String endpoint;

    /**
     * S3バケット名
     */
    private String bucketName;

    /**
     * S3クライアント
     */
    private S3Client s3Client;

    /**
     * Bean初期化時にS3Clientを初期化する
     */
    @PostConstruct
    public void init() {
        // ビルダー初期化(Region, CredentialsProviderをセット)
        S3ClientBuilder builder = S3Client.builder()
                .region(Region.of(this.region))
                .credentialsProvider(DefaultCredentialsProvider.create());
        // エンドポイントが設定されていれば上書き(localStackの場合)
        if (this.endpoint != null && !this.endpoint.isEmpty()) {
            builder.endpointOverride(URI.create(this.endpoint));
        }
        // クライアント生成
        this.s3Client = builder.build();
    }

    /**
     * ファイルをS3に保存し、保存先のキーを返す
     *
     * @param file 保存するファイルデータ
     * @param path 保存パス（フォルダ構造、末尾に/必須）
     * @return 保存されたオブジェクトのS3キー
     * @throws IOException ファイル操作中にエラーが発生した場合
     */
    public String uploadFile(MultipartFile file, String path) throws IOException {
        String originalFilename = file.getOriginalFilename();
        String extension = "";

        if (originalFilename != null && originalFilename.contains(".")) {
            extension = originalFilename.substring(originalFilename.lastIndexOf("."));
        }

        // ユニークなファイル名を生成
        String key = path + UUID.randomUUID().toString() + extension;

        // メタデータ設定
        Map<String, String> metadata = new HashMap<>();
        metadata.put("Content-Type", file.getContentType());
        metadata.put("Original-Filename", originalFilename);

        // S3へのアップロードリクエスト作成
        PutObjectRequest putObjectRequest = PutObjectRequest.builder()
                .bucket(bucketName)
                .key(key)
                .contentType(file.getContentType())
                .metadata(metadata)
                .build();

        // ファイルアップロード実行
        s3Client.putObject(putObjectRequest, RequestBody.fromInputStream(file.getInputStream(), file.getSize()));

        return key;
    }

    /**
     * 任意のファイル名を指定してファイルをS3に保存し、保存先のキーを返す
     *
     * @param file     保存するファイルデータ
     * @param path     保存パス（フォルダ構造、末尾に/必須）
     * @param fileName 保存するファイル名（拡張子含む）
     * @return 保存されたオブジェクトのS3キー
     * @throws IOException ファイル操作中にエラーが発生した場合
     */
    public String uploadFileWithName(MultipartFile file, String path, String fileName) throws IOException {
        String key = path + fileName;

        // メタデータ設定
        Map<String, String> metadata = new HashMap<>();
        metadata.put("Content-Type", file.getContentType());
        metadata.put("Original-Filename", file.getOriginalFilename());

        // S3へのアップロードリクエスト作成
        PutObjectRequest putObjectRequest = PutObjectRequest.builder()
                .bucket(bucketName)
                .key(key)
                .contentType(file.getContentType())
                .metadata(metadata)
                .build();

        // ファイルアップロード実行
        s3Client.putObject(putObjectRequest, RequestBody.fromInputStream(file.getInputStream(), file.getSize()));

        return key;
    }

    /**
     * ファイルをバイト配列として取得する
     *
     * @param key S3オブジェクトキー
     * @return ファイルのバイト配列
     * @throws IOException ファイル操作に失敗した場合
     * @throws S3Exception S3操作中にエラーが発生した場合
     */
    public byte[] getFileAsBytes(String key) throws IOException {
        GetObjectRequest getObjectRequest = GetObjectRequest.builder()
                .bucket(bucketName)
                .key(key)
                .build();

        try (ResponseInputStream<GetObjectResponse> responseInputStream = s3Client.getObject(getObjectRequest)) {
            return responseInputStream.readAllBytes();
        }
    }

    /**
     * S3からオブジェクトを削除する
     *
     * @param key 削除するオブジェクトのS3キー
     */
    public void deleteObject(String key) {
        DeleteObjectRequest deleteObjectRequest = DeleteObjectRequest.builder()
                .bucket(bucketName)
                .key(key)
                .build();

        s3Client.deleteObject(deleteObjectRequest);
    }
}
