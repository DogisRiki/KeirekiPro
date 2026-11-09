// Package awsclient は、S3 と SES v1 と Secrets Manager のクライアントを作る。
// つなぎ先の値は引数で受け取り、設定の部品を読まない。
package awsclient

import (
	"context"
	"errors"
	"fmt"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"
	"github.com/aws/aws-sdk-go-v2/service/ses"
)

// Options は、AWS のつなぎ先である。
type Options struct {
	// Region は、AWS のリージョンである。
	Region string
	// Endpoint は、dev と test で AWS の代わりにつなぐ先の URL である(KEIREKIPRO_AWS_ENDPOINT の値)。
	// 本番では空にする。
	Endpoint string
}

// Clients は、Go 版が使う AWS のクライアントである。
type Clients struct {
	S3             *s3.Client
	SES            *ses.Client
	SecretsManager *secretsmanager.Client
}

// devCredential は、dev と test で AWS の代わりにつなぐときの認証の値である。
// Java 版の application-dev.yaml の access-key と secret-key と同じ値である。
const devCredential = "dummy"

// New は、AWS のクライアントを作る。
// Endpoint が空なら、本番の AWS に、実行の環境の認証(ECS のタスクのロール)でつなぐ。
// Endpoint があれば、3つのクライアントの接続先をその URL に替え、S3 をパスの形にする。
func New(ctx context.Context, opts Options) (Clients, error) {
	if opts.Region == "" {
		return Clients{}, errors.New("awsclient: リージョンが空です")
	}
	loadOptions := []func(*config.LoadOptions) error{config.WithRegion(opts.Region)}
	if opts.Endpoint != "" {
		loadOptions = append(loadOptions, config.WithCredentialsProvider(
			credentials.NewStaticCredentialsProvider(devCredential, devCredential, "")))
	}
	cfg, err := config.LoadDefaultConfig(ctx, loadOptions...)
	if err != nil {
		return Clients{}, fmt.Errorf("awsclient: AWS の設定を読めません: %w", err)
	}

	var endpoint *string
	if opts.Endpoint != "" {
		endpoint = aws.String(opts.Endpoint)
	}
	return Clients{
		S3: s3.NewFromConfig(cfg, func(o *s3.Options) {
			o.BaseEndpoint = endpoint
			o.UsePathStyle = endpoint != nil
		}),
		SES: ses.NewFromConfig(cfg, func(o *ses.Options) {
			o.BaseEndpoint = endpoint
		}),
		SecretsManager: secretsmanager.NewFromConfig(cfg, func(o *secretsmanager.Options) {
			o.BaseEndpoint = endpoint
		}),
	}, nil
}
