"""raw_file.evidence_kind: ประเภทหลักฐานที่นิสิตเลือกตอนอัปโหลด (Evidence Kind เฟส 1)

Revision ID: c4d5e6f7a8b9
Revises: b3c4d5e6f7a8
Create Date: 2026-09-16 10:00:00.000000

enum evidencekind: certificate / photo / other
* certificate → เข้า OCR auto-approve ตามเกณฑ์เดิม
* photo / other → needs_review เสมอ (OCR ยืนยันตัวตนคนในภาพถ่ายไม่ได้)

nullable + backfill แถวเดิมทั้งหมดเป็น certificate — ไฟล์เก่าคงพฤติกรรมเดิม คำตัดสินในอดีตไม่เปลี่ยน
(ตอนประมวลผล null ก็ถือเป็น certificate อีกชั้น)

ADD COLUMN ล้วน ไม่มี FK จึงไม่ใช้ batch_alter_table ตอน upgrade และไม่ต้อง DROP gold views
(downgrade DROP COLUMN ผ่าน batch บน SQLite จึงทิ้ง views ก่อนตามแนวเดิม)
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

from app.gold import GOLD_VIEW_NAMES


# revision identifiers, used by Alembic.
revision: str = 'c4d5e6f7a8b9'
down_revision: Union[str, None] = 'b3c4d5e6f7a8'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_ENUM = sa.Enum('certificate', 'photo', 'other', name='evidencekind')


def upgrade() -> None:
    # add_column ไม่สร้าง ENUM type ให้เองบน Postgres (create_table ทำให้ แต่ add_column ไม่)
    bind = op.get_bind()
    if bind.dialect.name == 'postgresql':
        _ENUM.create(bind, checkfirst=True)

    op.add_column('raw_file', sa.Column('evidence_kind', _ENUM, nullable=True))
    op.execute("UPDATE raw_file SET evidence_kind = 'certificate' WHERE evidence_kind IS NULL")


def downgrade() -> None:
    for name in GOLD_VIEW_NAMES:
        op.execute(f'DROP VIEW IF EXISTS {name}')
    with op.batch_alter_table('raw_file') as batch:
        batch.drop_column('evidence_kind')

    bind = op.get_bind()
    if bind.dialect.name == 'postgresql':
        _ENUM.drop(bind, checkfirst=True)
