package com.example.keirekipro.infrastructure.shared.aws;

import java.io.IOException;
import java.net.URI;
import java.time.Duration;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import org.springframework.beans.factory.annotation.Autowired;
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
import software.amazon.awssdk.services.s3.S3Configuration;
import software.amazon.awssdk.services.s3.model.DeleteObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.model.S3Exception;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.s3.presigner.model.GetObjectPresignRequest;
import software.amazon.awssdk.services.s3.presigner.model.PresignedGetObjectRequest;

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
     * S3プリサイナー (署名付きURL生成用)
     */
    private S3Presigner s3Presigner;

    /**
     * Bean初期化時にS3ClientおよびS3Presignerを初期化する
     */
    @PostConstruct
    public void init() {
        // S3Clientのビルダー初期化(Region, CredentialsProviderをセット)
        S3ClientBuilder builder = S3Client.builder()
                .region(Region.of(this.region))
                .credentialsProvider(DefaultCredentialsProvider.create());

        // エンドポイントが設定されていれば上書きし、パススタイル形式にする(localStackに対応)
        if (this.endpoint != null && !this.endpoint.isEmpty()) {
            builder
                    .endpointOverride(URI.create(this.endpoint))
                    .serviceConfiguration(
                            S3Configuration.builder().pathStyleAccessEnabled(true).build());
        }
        // S3Client生成
        this.s3Client = builder.build();

        // S3Presignerのビルダー初期化(Region, CredentialsProviderをセット)
        S3Presigner.Builder presignerBuilder = S3Presigner.builder()
                .region(Region.of(this.region))
                .credentialsProvider(DefaultCredentialsProvider.create());

        // エンドポイントが設定されていれば上書き(localStackに対応)
        if (this.endpoint != null && !this.endpoint.isEmpty()) {
            presignerBuilder
                    .endpointOverride(URI.create(this.endpoint))
                    .serviceConfiguration(
                            S3Configuration.builder()
                                    .pathStyleAccessEnabled(true)
                                    .build());
        }
        // S3Presigner生成
        this.s3Presigner = presignerBuilder.build();
    }

    /**
     * 外部からS3Presignerを差し替えるためのセッター
     * Bean定義やテスト時に別インスタンスを注入可能
     *
     * @param s3Presigner 置き換えるS3Presignerインスタンス
     */
    @Autowired(required = false)
    public void setS3Presigner(S3Presigner s3Presigner) {
        this.s3Presigner = s3Presigner;
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

    /**
     * 署名付きURLを生成する
     *
     * @param key    オブジェクトキー
     * @param expiry 有効期限
     * @return 署名付きURL
     */
    public String generatePresignedUrl(String key, Duration expiry) {
        GetObjectRequest getObjectRequest = GetObjectRequest.builder()
                .bucket(bucketName)
                .key(key)
                .build();

        GetObjectPresignRequest presignRequest = GetObjectPresignRequest.builder()
                .signatureDuration(expiry)
                .getObjectRequest(getObjectRequest)
                .build();

        PresignedGetObjectRequest presignedRequest = s3Presigner.presignGetObject(presignRequest);
        String url = presignedRequest.url().toString();

        // エンドポイントが設定されている場合、開発環境とみなしホスト名をlocalhostに置換
        if (this.endpoint != null && !this.endpoint.isEmpty()) {
            String originalHost = URI.create(this.endpoint).getHost();
            url = url.replace(originalHost, "localhost");
        }

        return url;
    }
}
