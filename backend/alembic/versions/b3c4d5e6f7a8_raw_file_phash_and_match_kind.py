"""raw_file.phash + silver_evidence_ocr.match_kind (OCR เฟส 3A.1)

Revision ID: b3c4d5e6f7a8
Revises: a2b3c4d5e6f7
Create Date: 2026-09-15 18:00:00.000000

* raw_file.phash — perceptual hash ของไฟล์ภาพ (hex 64 ตัว = 256 บิต) คำนวณตอนอัปโหลด
  ใช้จับภาพ "เกือบเหมือน" (บีบอัด/ย่อใหม่) ที่ checksum จับไม่ได้ — 256 บิตไม่ใช่ 64 เพราะ
  เกียรติบัตรเทมเพลตเดียวกันคนละคนชนกันที่ 64 บิต
* silver_evidence_ocr.match_kind (enum matchkind: exact / near) — ซ้ำแบบเป๊ะหรือคล้าย
  สเปกให้รวมไว้ใน migration นี้ได้ (ตั้งค่าจริงในเฟส 3A.2) จะได้ไม่ต้อง backup/migrate อีกรอบ

nullable ทั้งคู่ แถวเดิมเป็น NULL (ไม่ backfill) · ไม่ต้องสร้าง index ให้ phash เพราะการเทียบ
Hamming distance ใช้ index แบบธรรมดาไม่ได้อยู่แล้ว

เป็น ADD COLUMN ล้วน ไม่มี FK จึงไม่ใช้ batch_alter_table และไม่ต้อง DROP gold views ตอน upgrade
(downgrade ต้อง DROP COLUMN ผ่าน batch บน SQLite จึงทิ้ง views ก่อนตามแนวเดิม)
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

from app.gold import GOLD_VIEW_NAMES


# revision identifiers, used by Alembic.
revision: str = 'b3c4d5e6f7a8'
down_revision: Union[str, None] = 'a2b3c4d5e6f7'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_MATCH_KIND = sa.Enum('exact', 'near', name='matchkind')


def upgrade() -> None:
    # add_column ไม่สร้าง ENUM type ให้เองบน Postgres (create_table ทำให้ แต่ add_column ไม่)
    bind = op.get_bind()
    if bind.dialect.name == 'postgresql':
        _MATCH_KIND.create(bind, checkfirst=True)

    op.add_column('raw_file', sa.Column('phash', sa.String(length=64), nullable=True))
    op.add_column('silver_evidence_ocr', sa.Column('match_kind', _MATCH_KIND, nullable=True))


def downgrade() -> None:
    for name in GOLD_VIEW_NAMES:
        op.execute(f'DROP VIEW IF EXISTS {name}')
    with op.batch_alter_table('silver_evidence_ocr') as batch:
        batch.drop_column('match_kind')
    with op.batch_alter_table('raw_file') as batch:
        batch.drop_column('phash')

    bind = op.get_bind()
    if bind.dialect.name == 'postgresql':
        _MATCH_KIND.drop(bind, checkfirst=True)
