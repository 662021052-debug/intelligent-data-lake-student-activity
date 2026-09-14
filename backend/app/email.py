"""ช่องทางส่งอีเมลแจ้งเตือน (ข้อ 6.4).

โครงเดียวกับ ``storage.py`` / ``ocr.py`` / ``llm.py`` คือซ่อนตัวส่งจริงไว้หลัง
interface เล็ก ๆ (:class:`EmailSender`) แล้วให้เทสต์สลับ :class:`StubEmailSender`
เข้ามาแทน — เทสต์จึงตรวจ "ส่งถึงใคร ด้วยข้อความอะไร" ได้โดยไม่ต้องมีเซิร์ฟเวอร์
SMTP และไม่มีทางยิงอีเมลจริงใส่นิสิตระหว่างรันเทสต์

ค่าเริ่มต้นของ ``EMAIL_BACKEND`` คือ ``stub`` โดยตั้งใจ (เหมือน ``LLM_BACKEND``):
ระบบที่ยังไม่ได้ตั้งค่า SMTP ต้องบูตและเรียก endpoint ได้ตามปกติ แค่ไม่มีอีเมล
ออกไปจริง ผู้ดูแลต้องตั้ง ``EMAIL_BACKEND=smtp`` เองเมื่อพร้อมส่ง
"""
from __future__ import annotations

import logging
import smtplib
import socket
import ssl
from dataclasses import dataclass, field
from email.message import EmailMessage as MimeMessage
from typing import Optional, Protocol, runtime_checkable

from app.config import settings

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class EmailMessage:
    """อีเมลหนึ่งฉบับ — เป็นข้อความล้วน (plain text) ทั้งหมด

    ไม่ทำ HTML เพราะเนื้อหาที่ต้องส่งเป็นรายการสั้น ๆ และข้อความล้วนอ่านได้ทุก
    ไคลเอนต์ ไม่ต้องกังวลเรื่อง escape ชื่อ-สกุลหรือชื่อกิจกรรมที่มีอักขระพิเศษ
    """

    to: str
    subject: str
    body: str


@runtime_checkable
class EmailSender(Protocol):
    def send(self, message: EmailMessage) -> None:
        """ส่งหนึ่งฉบับ — โยน exception เมื่อส่งไม่สำเร็จ"""
        ...


class SmtpEmailSender:
    """ตัวส่งจริงผ่าน SMTP (smtplib เป็น stdlib จึงไม่มี dependency เพิ่ม)

    เปิดการเชื่อมต่อใหม่ต่อหนึ่งฉบับ เพื่อให้ฉบับที่ล้มไม่ทำให้ทั้งชุดล้มตาม
    (การแจ้งเตือนทีละร้อยฉบับ ถ้าใช้คอนเนกชันร่วมกันแล้วหลุดกลางทาง จะแยกไม่ออก
    ว่าใครได้รับแล้วบ้าง)
    """

    def __init__(
        self,
        host: str,
        port: int,
        username: str,
        password: str,
        sender: str,
        use_tls: bool = True,
        timeout: int = 30,
    ) -> None:
        self._host = host
        self._port = port
        self._username = username
        self._password = password
        self._sender = sender
        self._use_tls = use_tls
        self._timeout = timeout

    def send(self, message: EmailMessage) -> None:
        mime = MimeMessage()
        mime["From"] = self._sender
        mime["To"] = message.to
        mime["Subject"] = message.subject
        # set_content เลือก charset ให้เอง (utf-8 สำหรับภาษาไทย) และเข้ารหัสหัวข้อ
        # แบบ RFC 2047 ให้ด้วย — หัวข้อภาษาไทยจึงไม่กลายเป็นตัวขยะที่ปลายทาง
        mime.set_content(message.body)

        with smtplib.SMTP(self._host, self._port, timeout=self._timeout) as smtp:
            if self._use_tls:
                smtp.starttls()
            if self._username:
                smtp.login(self._username, self._password)
            smtp.send_message(mime)


@dataclass
class StubEmailSender:
    """ตัวส่งปลอมสำหรับเทสต์และการรันแบบยังไม่ตั้งค่า SMTP

    เก็บทุกฉบับไว้ใน :attr:`sent` แทนการส่งออกไปจริง เทสต์จึงยืนยันผู้รับและ
    เนื้อความได้ตรง ๆ ส่วนตอนรันจริงจะได้ log ไว้ดูว่า "ถ้าเปิดใช้จริงจะส่งอะไร"
    """

    sent: list[EmailMessage] = field(default_factory=list)

    def send(self, message: EmailMessage) -> None:
        self.sent.append(message)
        logger.info("(stub) ไม่ได้ส่งจริง — ถึง %s หัวข้อ %s", message.to, message.subject)

    def clear(self) -> None:
        self.sent.clear()


_sender: Optional[EmailSender] = None


def _build_sender() -> EmailSender:
    # ไม่มี host = ตั้งค่าไม่ครบ ให้ตกกลับไปที่ stub แทนที่จะพังตอนส่ง — แบบเดียว
    # กับ llm.py ที่ไม่มี key แล้วใช้ StubLlm
    if settings.email_backend == "smtp" and settings.smtp_host:
        return SmtpEmailSender(
            host=settings.smtp_host,
            port=settings.smtp_port,
            username=settings.smtp_user,
            password=settings.smtp_password,
            sender=settings.smtp_from,
            use_tls=settings.smtp_use_tls,
        )
    return StubEmailSender()


def get_email_sender() -> EmailSender:
    """FastAPI dependency คืนตัวส่งอีเมลที่ใช้ร่วมกันทั้งโปรเซส"""
    global _sender
    if _sender is None:
        _sender = _build_sender()
    return _sender


def email_backend_name(sender: EmailSender) -> str:
    """"smtp" เมื่อส่งออกจริง นอกนั้น "stub" — ตัวส่งตกเป็น stub ได้แบบเงียบ ๆ
    (เช่น ลืมส่ง env เข้าคอนเทนเนอร์) จึงต้องบอกให้ชัดว่าตอนนี้ใช้ตัวไหน"""
    return "smtp" if isinstance(sender, SmtpEmailSender) else "stub"


def _server_reply(exc: Exception) -> str:
    raw = getattr(exc, "smtp_error", b"")
    text = raw.decode("utf-8", "replace") if isinstance(raw, bytes) else str(raw)
    return " ".join(text.split())


def explain_email_error(exc: Exception) -> tuple[str, str]:
    """(ชนิด, เหตุผลภาษาไทย) ของการส่งที่ล้ม — ใช้ตอบกลับผู้ดูแลตรง ๆ

    ข้อความมาจากชนิด exception และคำตอบของเซิร์ฟเวอร์เท่านั้น ไม่มีรหัสผ่านหรือค่า config
    ลับปนออกไป (smtplib ไม่ใส่รหัสผ่านไว้ใน exception อยู่แล้ว)
    """
    reply = _server_reply(exc)
    suffix = f" · เซิร์ฟเวอร์ตอบ: {reply}" if reply else ""
    # ลำดับสำคัญ: คลาสลูกต้องมาก่อนคลาสแม่ (SMTPException / OSError)
    if isinstance(exc, smtplib.SMTPAuthenticationError):
        return (
            "auth_failed",
            "SMTP ไม่รับการ login (SMTP_USER/รหัสผ่านไม่ถูก) — Gmail ต้องใช้ App Password 16 ตัว"
            " ของบัญชีที่เปิด 2-Step Verification ไม่ใช่รหัสผ่านปกติของบัญชี" + suffix,
        )
    if isinstance(exc, smtplib.SMTPRecipientsRefused):
        return ("recipient_refused", "เซิร์ฟเวอร์ปฏิเสธที่อยู่ผู้รับ")
    if isinstance(exc, smtplib.SMTPSenderRefused):
        return ("sender_refused", "เซิร์ฟเวอร์ปฏิเสธที่อยู่ผู้ส่ง (SMTP_FROM)" + suffix)
    if isinstance(exc, smtplib.SMTPNotSupportedError):
        return (
            "tls_not_supported",
            "เซิร์ฟเวอร์ไม่รองรับ STARTTLS/AUTH — ตรวจ SMTP_PORT กับ SMTP_USE_TLS (Gmail: 587 + TLS)",
        )
    if isinstance(exc, (smtplib.SMTPConnectError, smtplib.SMTPServerDisconnected)):
        return ("connection_failed", f"ต่อเซิร์ฟเวอร์ SMTP ไม่ติดหรือหลุดกลางทาง ({exc})")
    if isinstance(exc, smtplib.SMTPException):
        return ("smtp_error", f"{type(exc).__name__}: {exc}")
    if isinstance(exc, ssl.SSLError):
        return ("tls_failed", f"เปิด TLS ไม่สำเร็จ ({exc})")
    if isinstance(exc, socket.gaierror):
        return ("dns_failed", "หา SMTP_HOST ไม่เจอ (DNS) — ตรวจชื่อ host หรือเน็ตของคอนเทนเนอร์")
    if isinstance(exc, TimeoutError):
        return ("timeout", "ต่อ SMTP หมดเวลา — พอร์ตอาจถูกไฟร์วอลล์/ผู้ให้บริการเน็ตบล็อก")
    if isinstance(exc, ConnectionRefusedError):
        return ("connection_refused", "เซิร์ฟเวอร์ไม่รับการเชื่อมต่อ — ตรวจ SMTP_HOST/SMTP_PORT")
    if isinstance(exc, OSError):
        return ("network_error", f"{type(exc).__name__}: {exc}")
    return ("unknown", f"{type(exc).__name__}: {exc}")
