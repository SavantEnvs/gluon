package rfc822

import "testing"

func FuzzParseDec(f *testing.F) {
	f.Add([]byte("From: Sender <sender@pm.me>\r\nTo: Receiver <receiver@pm.me>\r\nContent-Transfer-Encoding: base64\r\n\r\nYm9keQ==\r\n"))

	f.Add([]byte("Content-Type: multipart/alternative; boundary=\"------------62DCF50B21CF279F489F0184\"\r\n\r\n\r\n" +
		"--------------62DCF50B21CF279F489F0184\r\nContent-Type: text/plain; charset=utf-8; format=flowed\r\n" +
		"Content-Transfer-Encoding: 7bit\r\n\r\n*this */is**/_html_\r\n**\r\n\r\n--------------62DCF50B21CF279F489F0184\r\n" +
		"Content-Type: text/html; charset=utf-8\r\nContent-Transfer-Encoding: 7bit\r\n<foo></foo>\r\n--------------62DCF50B21CF279F489F0184--\r\n"))

	f.Fuzz(func(t *testing.T, inputData []byte) {
		_, _ = Parse(inputData).DecodedBody()
	})
}
