"""POST /notifications/test-email — ส่งอีเมลทดสอบ 1 ฉบับ (admin)

ไม่มีการต่อ SMTP จริง: ใช้ตัวส่งที่เป็นคลาสลูกของ SmtpEmailSender (ระบบจึงนับว่า "ส่งจริง")
แต่ override send ให้บันทึกหรือโยน exception แบบที่ smtplib โยนจริง
"""

import smtplib
import socket

import pytest

from app.email import SmtpEmailSender, StubEmailSender, explain_email_error, get_email_sender
from app.main import app

SECRET = "abcd efgh ijkl mnop"


class FakeSmtp(SmtpEmailSender):
    def __init__(self, error=None):
        super().__init__(
            host="smtp.example.com", port=587, username="bot@example.com",
            password=SECRET, sender="bot@example.com",
        )
        self.error = error
        self.sent = []

    def send(self, message):
        if self.error is not None:
            raise self.error
        self.sent.append(message)


@pytest.fixture
def use_sender(client):
    def _use(sender):
        app.dependency_overrides[get_email_sender] = lambda: sender
        return sender

    yield _use
    app.dependency_overrides.pop(get_email_sender, None)


def _admin(tokens):
    return {"Authorization": f"Bearer {tokens['admin']}"}


def test_success_sends_one_message(client, tokens, use_sender):
    sender = use_sender(FakeSmtp())
    resp = client.post("/notifications/test-email", params={"to": "someone@gmail.com"}, headers=_admin(tokens))

    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["ok"] is True and body["backend"] == "smtp" and body["error_type"] is None
    assert len(sender.sent) == 1
    assert sender.sent[0].to == "someone@gmail.com"
    assert "ทดสอบ" in sender.sent[0].subject


def test_auth_failure_explains_cause_without_leaking_password(client, tokens, use_sender):
    error = smtplib.SMTPAuthenticationError(
        535, b"5.7.8 Username and Password not accepted. For more information, go to BadCredentials"
    )
    use_sender(FakeSmtp(error))
    resp = client.post("/notifications/test-email", params={"to": "someone@gmail.com"}, headers=_admin(tokens))

    assert resp.status_code == 502
    body = resp.json()
    assert body["ok"] is False and body["error_type"] == "auth_failed"
    assert "App Password" in body["reason"] and "BadCredentials" in body["reason"]
    assert SECRET not in resp.text


def test_connection_refused_is_reported(client, tokens, use_sender):
    use_sender(FakeSmtp(ConnectionRefusedError(111, "Connection refused")))
    resp = client.post("/notifications/test-email", params={"to": "a@b.co"}, headers=_admin(tokens))
    assert resp.status_code == 502
    assert resp.json()["error_type"] == "connection_refused"


def test_stub_sender_is_not_a_success(client, tokens, use_sender):
    stub = use_sender(StubEmailSender())
    resp = client.post("/notifications/test-email", params={"to": "a@b.co"}, headers=_admin(tokens))

    assert resp.status_code == 503
    body = resp.json()
    assert body["ok"] is False and body["backend"] == "stub" and body["error_type"] == "not_configured"
    assert stub.sent == [], "stub ต้องไม่ถูกนับว่าส่งสำเร็จ"


def test_invalid_address_rejected_before_sending(client, tokens, use_sender):
    sender = use_sender(FakeSmtp())
    resp = client.post("/notifications/test-email", params={"to": "not-an-email"}, headers=_admin(tokens))
    assert resp.status_code == 422
    assert sender.sent == []


@pytest.mark.parametrize("role", ["staff", "student"])
def test_admin_only(client, tokens, use_sender, role):
    sender = use_sender(FakeSmtp())
    resp = client.post(
        "/notifications/test-email", params={"to": "a@b.co"},
        headers={"Authorization": f"Bearer {tokens[role]}"},
    )
    assert resp.status_code == 403
    assert sender.sent == []


@pytest.mark.parametrize(
    ("error", "kind"),
    [
        (socket.gaierror(-2, "Name or service not known"), "dns_failed"),
        (TimeoutError("timed out"), "timeout"),
        (smtplib.SMTPServerDisconnected("Connection unexpectedly closed"), "connection_failed"),
        (smtplib.SMTPSenderRefused(553, b"not allowed", "x@y.z"), "sender_refused"),
        (ValueError("boom"), "unknown"),
    ],
)
def test_explain_email_error_kinds(error, kind):
    assert explain_email_error(error)[0] == kind
