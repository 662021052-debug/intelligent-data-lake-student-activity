"""student.source_passed: สถานะผ่าน/ไม่ผ่านเกณฑ์ตามไฟล์รายชื่อที่นำเข้า

Revision ID: c8d9e0f1a2b3
Revises: b7c8d9e0f1a2
Create Date: 2026-09-11 12:00:00.000000

ไฟล์รายชื่อนิสิตจริง (load_students.py) มีคอลัมน์ "สถานะ" ที่ต้นทางตัดสินไว้แล้ว
เก็บไว้ข้างนิสิตเพื่อใช้สร้าง participation จำลองให้ตรงสถานะ และตรวจว่า completion
ที่ระบบคำนวณเองตรงกับต้นทางแค่ไหน — nullable เพราะนิสิตที่สร้างผ่านแอปไม่มีค่านี้

ขาขึ้นเป็น ADD COLUMN ธรรมดา ไม่ต้อง batch จึงไม่ต้องถอด gold views
ขาลงต้อง batch บน SQLite จึง DROP gold views ก่อนตาม pattern เดิม
(`init_gold_layer()` สร้าง view ใหม่ให้ตอนแอปบูต)
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

from app.gold import GOLD_VIEW_NAMES


# revision identifiers, used by Alembic.
revision: str = 'c8d9e0f1a2b3'
down_revision: Union[str, None] = 'b7c8d9e0f1a2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('student', sa.Column('source_passed', sa.Boolean(), nullable=True))


def downgrade() -> None:
    for name in GOLD_VIEW_NAMES:
        op.execute(f'DROP VIEW IF EXISTS {name}')
    with op.batch_alter_table('student') as batch:
        batch.drop_column('source_passed')
