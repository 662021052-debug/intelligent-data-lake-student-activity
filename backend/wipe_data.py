"""ล้างข้อมูลปฏิบัติการทิ้งทั้งหมด เพื่อเริ่มจากศูนย์ก่อนโหลดชุดข้อมูลจริง

ลบ: นิสิต · บัญชีของนิสิต · กิจกรรม · การเข้าร่วม · หลักฐาน (แถว Bronze/Silver +
ไฟล์ในที่เก็บ) · การผูกกิจกรรมกับรายการเกณฑ์

**ไม่ลบ**:
- บัญชี staff/admin — ถ้าลบหมดจะเข้าระบบไม่ได้อีกเลย และ `seed.py` (ที่คอนเทนเนอร์
  รันตอนบูต) จะเห็นฐานว่างแล้วยัดข้อมูลเดโม 100 คนกลับเข้ามาทับของจริง
- hourcategory/hoursubcategory — เฟสถัดไปใช้เป็นต้นทางแปลงเป็นชุดเกณฑ์ legacy
- ชุดเกณฑ์ (criteria_set/talent/learning_unit/requirement) — ยังไม่มีข้อมูล และ
  เป็น "นิยาม" ไม่ใช่ข้อมูลปฏิบัติการ

ใช้:
    python wipe_data.py --dry-run     # นับอย่างเดียว ไม่ลบ
    python wipe_data.py --yes         # ลบจริง
"""

from __future__ import annotations

import argparse
import sys

from sqlalchemy import text
from sqlmodel import Session, select

from app.database import engine
from app.models import (
    Activity,
    ActivityRequirement,
    Participation,
    RawFile,
    SilverEvidenceOcr,
    Student,
    User,
    UserRole,
)
from app.storage import get_storage

# ลบจากปลายทางเข้าหาต้นทาง (ลูกก่อนแม่) FK จึงไม่ค้างระหว่างทาง
_TABLES_IN_ORDER = [
    ("silver_evidence_ocr", SilverEvidenceOcr),
    ("raw_file", RawFile),
    ("participation", Participation),
    ("activity_requirement", ActivityRequirement),
    ("activity", Activity),
]


def _count(session: Session, model) -> int:
    return len(session.exec(select(model)).all())


def _delete_storage_objects(raw_files: list[RawFile], dry_run: bool) -> int:
    """ลบไฟล์หลักฐานในที่เก็บ ตามที่แถว Bronze ชี้ไว้

    ถ้าเหลือไว้จะกลายเป็นไฟล์กำพร้าที่ไม่มีแถวชี้ถึง และ checksum เดิมยังลอยอยู่
    ทำให้หลักฐานชุดใหม่ที่ไฟล์เหมือนกันถูกตีเป็น "ซ้ำ" ทั้งที่เป็นข้อมูลคนละรอบ

    ที่เก็บล่มไม่ควรทำให้การล้างฐานล้มทั้งงาน — รายงานจำนวนที่ลบไม่สำเร็จแทน
    """
    if dry_run:
        return len(raw_files)

    storage = get_storage()
    failed = 0
    for row in raw_files:
        try:
            storage.remove_object(row.bucket, row.object_key)
        except Exception as exc:
            failed += 1
            if failed == 1:
                print(f"ลบไฟล์ในที่เก็บไม่สำเร็จ ({exc}) — ไฟล์ที่เหลือจะเป็นไฟล์กำพร้า")
    return len(raw_files) - failed


def wipe(dry_run: bool = False) -> None:
    with Session(engine) as session:
        counts = {name: _count(session, model) for name, model in _TABLES_IN_ORDER}
        student_users = session.exec(
            select(User).where(User.role == UserRole.student)
        ).all()
        students = session.exec(select(Student)).all()
        counts["user (role=student)"] = len(student_users)
        counts["student"] = len(students)

        raw_files = session.exec(select(RawFile)).all()
        counts["ไฟล์ในที่เก็บ"] = _delete_storage_objects(raw_files, dry_run)

        if dry_run:
            print("dry-run — ไม่ได้ลบอะไร จำนวนที่จะถูกลบ:")
        else:
            # flush ทีละชั้น — ถ้าปล่อยให้ SQLAlchemy จัดลำดับเอง มันจะลบ student
            # ก่อน user ที่ชี้มาหา แล้วชน FK ทันทีบน Postgres
            for _, model in _TABLES_IN_ORDER:
                for row in session.exec(select(model)).all():
                    session.delete(row)
                session.flush()
            for row in student_users:
                session.delete(row)
            session.flush()
            for row in students:
                session.delete(row)
            session.commit()

            # Postgres: คืนลำดับ id ให้เริ่มที่ 1 ใหม่ ข้อมูลชุดใหม่จะได้อ่านง่าย
            if session.get_bind().dialect.name == "postgresql":
                for table in ("participation", "activity", "student", "raw_file"):
                    session.execute(
                        text(f'ALTER SEQUENCE IF EXISTS {table}_id_seq RESTART WITH 1')
                    )
                session.commit()
            print("ล้างข้อมูลเรียบร้อย — จำนวนที่ลบไป:")

        for name, n in counts.items():
            print(f"  {name}: {n}")

        remaining = session.exec(select(User)).all()
        print(f"บัญชีที่เหลือไว้ (staff/admin): {len(remaining)}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--yes", action="store_true", help="ยืนยันการลบจริง")
    parser.add_argument("--dry-run", action="store_true", help="นับอย่างเดียว ไม่ลบ")
    args = parser.parse_args()

    if not args.yes and not args.dry_run:
        print("ต้องใส่ --yes เพื่อยืนยัน (หรือ --dry-run เพื่อดูก่อน)")
        sys.exit(2)

    wipe(dry_run=args.dry_run)
