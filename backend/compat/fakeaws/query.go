//go:build compat

package fakeaws

import (
	"encoding/json"
	"encoding/xml"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"strconv"
)

// maxQuerySize は、SES と Secrets Manager の要求の本文の大きさの上限である。
const maxQuerySize = 1 << 20

// region と accountID は、Secrets Manager の ARN に使う値である。比べる検査では値の中身を使わない。
const (
	region    = "ap-northeast-1"
	accountID = "000000000000"
)

// postRoot は、パスが / の POST を受ける。
// ヘッダ X-Amz-Target があれば Secrets Manager の JSON の形の要求、無ければ SES の Query の形の要求とみなす。
func (s *Server) postRoot(w http.ResponseWriter, r *http.Request) {
	if target := r.Header.Get("X-Amz-Target"); target != "" {
		s.secretsManager(w, r, target)
		return
	}
	s.ses(w, r)
}

// ses は、SES v1 の SendEmail を受ける。
func (s *Server) ses(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, maxQuerySize)
	if err := r.ParseForm(); err != nil {
		writeQueryError(w, "MalformedQueryString", "要求の本文を読めません: "+err.Error())
		return
	}
	form := r.PostForm
	if action := form.Get("Action"); action != "SendEmail" {
		s.reject(w, r, "SES "+action)
		return
	}
	email := Email{
		Source:  form.Get("Source"),
		To:      members(form, "Destination.ToAddresses"),
		Cc:      members(form, "Destination.CcAddresses"),
		Bcc:     members(form, "Destination.BccAddresses"),
		ReplyTo: members(form, "ReplyToAddresses"),
		Subject: form.Get("Message.Subject.Data"),
		Text:    form.Get("Message.Body.Text.Data"),
		HTML:    form.Get("Message.Body.Html.Data"),
	}
	version := versionOf(r)
	s.mu.Lock()
	st := s.storeOf(version)
	st.emails = append(st.emails, email)
	s.sent++
	messageID := fmt.Sprintf("fakeaws-%s-%d", version, s.sent)
	s.mu.Unlock()

	writeXML(w, http.StatusOK, sendEmailResponse{
		Xmlns:     "http://ses.amazonaws.com/doc/2010-12-01/",
		MessageID: messageID,
		RequestID: messageID,
	})
}

// members は、Query の形の一覧(<名前>.member.1、<名前>.member.2 …)を、番号の順に読む。
func members(form url.Values, name string) []string {
	var values []string
	for i := 1; ; i++ {
		key := name + ".member." + strconv.Itoa(i)
		if !form.Has(key) {
			return values
		}
		values = append(values, form.Get(key))
	}
}

type sendEmailResponse struct {
	XMLName   xml.Name `xml:"SendEmailResponse"`
	Xmlns     string   `xml:"xmlns,attr"`
	MessageID string   `xml:"SendEmailResult>MessageId"`
	RequestID string   `xml:"ResponseMetadata>RequestId"`
}

type queryErrorResponse struct {
	XMLName   xml.Name `xml:"ErrorResponse"`
	Type      string   `xml:"Error>Type"`
	Code      string   `xml:"Error>Code"`
	Message   string   `xml:"Error>Message"`
	RequestID string   `xml:"RequestId"`
}

func writeQueryError(w http.ResponseWriter, code, message string) {
	writeXML(w, http.StatusBadRequest, queryErrorResponse{Type: "Sender", Code: code, Message: message, RequestID: "fakeaws"})
}

// secretsManager は、Secrets Manager の GetSecretValue を受ける。
func (s *Server) secretsManager(w http.ResponseWriter, r *http.Request, target string) {
	if target != "secretsmanager.GetSecretValue" {
		s.reject(w, r, target)
		return
	}
	var req struct {
		SecretID string `json:"SecretId"`
	}
	data, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxQuerySize))
	if err == nil {
		err = json.Unmarshal(data, &req)
	}
	if err != nil {
		writeJSONError(w, "InvalidRequestException", "要求の本文を読めません: "+err.Error())
		return
	}
	s.mu.Lock()
	value, ok := s.storeOf(versionOf(r)).secrets[req.SecretID]
	s.mu.Unlock()
	if !ok {
		writeJSONError(w, "ResourceNotFoundException", "Secrets Manager can't find the specified secret.")
		return
	}
	w.Header().Set("Content-Type", "application/x-amz-json-1.1")
	if err := json.NewEncoder(w).Encode(map[string]any{
		"ARN":           fmt.Sprintf("arn:aws:secretsmanager:%s:%s:secret:%s", region, accountID, req.SecretID),
		"Name":          req.SecretID,
		"SecretString":  value,
		"VersionId":     "fakeaws",
		"VersionStages": []string{"AWSCURRENT"},
		"CreatedDate":   0,
	}); err != nil {
		log.Printf("fakeaws: 応答を書けません: %v", err)
	}
}

func writeJSONError(w http.ResponseWriter, errorType, message string) {
	w.Header().Set("Content-Type", "application/x-amz-json-1.1")
	w.Header().Set("X-Amzn-Errortype", errorType)
	w.WriteHeader(http.StatusBadRequest)
	if err := json.NewEncoder(w).Encode(map[string]string{"__type": errorType, "message": message}); err != nil {
		log.Printf("fakeaws: 応答を書けません: %v", err)
	}
}
