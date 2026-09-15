"""silver_evidence_ocr: เก็บว่าไฟล์ซ้ำกับใบไหน และซ้ำแบบไหน (OCR เฟส 1.2)

Revision ID: a2b3c4d5e6f7
Revises: f1a2b3c4d5e6
Create Date: 2026-09-15 15:00:00.000000

เดิมใบ flagged มีแค่ is_duplicate=True เจ้าหน้าที่ไม่รู้ว่าซ้ำกับใคร — เพิ่ม
* duplicate_of_participation_id → participation.id (ON DELETE SET NULL: เป็นแค่ตัวชี้
  ลบใบต้นทางแล้วต้องไม่ขวาง และไม่ลากแถว OCR ของอีกคนหายตามไปด้วย)
* duplicate_reason (enum duplicatereason: cross_student / same_student_reuse /
  matches_rejected) — ตัดสินโดย silver.find_duplicate

nullable ทั้งคู่ แถวเดิมเป็น NULL (ไม่ backfill)

DROP gold views ก่อนตามแนวเดิมของโปรเจกต์ เพราะการเพิ่ม FK บน SQLite ต้องผ่าน
batch_alter_table (สร้างตารางใหม่แล้ว rename ทับ) ซึ่งล้มถ้ายังมี view ค้างอยู่
— init_gold_layer() สร้างกลับให้ตอนแอปบูต
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

from app.gold import GOLD_VIEW_NAMES


# revision identifiers, used by Alembic.
revision: str = 'a2b3c4d5e6f7'
down_revision: Union[str, None] = 'f1a2b3c4d5e6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_TABLE = 'silver_evidence_ocr'
_ENUM = sa.Enum('cross_student', 'same_student_reuse', 'matches_rejected', name='duplicatereason')
_FK = 'fk_silver_evidence_ocr_duplicate_of_participation_id'
_INDEX = 'ix_silver_evidence_ocr_duplicate_of_participation_id'


def _drop_gold_views() -> None:
    for name in GOLD_VIEW_NAMES:
        op.execute(f'DROP VIEW IF EXISTS {name}')


def upgrade() -> None:
    _drop_gold_views()

    # add_column ไม่สร้าง ENUM type ให้เองบน Postgres (create_table ทำให้ แต่ add_column ไม่)
    bind = op.get_bind()
    if bind.dialect.name == 'postgresql':
        _ENUM.create(bind, checkfirst=True)

    op.add_column(_TABLE, sa.Column('duplicate_of_participation_id', sa.Integer(), nullable=True))
    op.add_column(_TABLE, sa.Column('duplicate_reason', _ENUM, nullable=True))
    with op.batch_alter_table(_TABLE) as batch:
        batch.create_foreign_key(
            _FK, 'participation', ['duplicate_of_participation_id'], ['id'], ondelete='SET NULL'
        )
    op.create_index(_INDEX, _TABLE, ['duplicate_of_participation_id'])


def downgrade() -> None:
    _drop_gold_views()

    op.drop_index(_INDEX, table_name=_TABLE)
    with op.batch_alter_table(_TABLE) as batch:
        batch.drop_constraint(_FK, type_='foreignkey')
        batch.drop_column('duplicate_reason')
        batch.drop_column('duplicate_of_participation_id')

    bind = op.get_bind()
    if bind.dialect.name == 'postgresql':
        _ENUM.drop(bind, checkfirst=True)
