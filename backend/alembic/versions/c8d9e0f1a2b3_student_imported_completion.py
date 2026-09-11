"""student.imported_completion: สถานะ ผ่าน/ไม่ผ่าน ตามไฟล์รายชื่อนิสิตที่นำเข้า

Revision ID: c8d9e0f1a2b3
Revises: b7c8d9e0f1a2
Create Date: 2026-09-11 12:00:00.000000

เก็บไว้ใช้สร้างการเข้าร่วมจำลองให้ผลตรงกับของจริง แล้วเทียบกับ completion ที่ระบบ
คำนวณเองในภายหลัง — nullable เพราะนิสิตที่สร้างผ่านหน้าจอไม่มีไฟล์ต้นทาง

เป็น ADD COLUMN ล้วน ไม่ใช้ batch_alter_table จึงไม่ต้อง DROP gold views ก่อน
(SQLite เพิ่มคอลัมน์ได้ตรง ๆ โดยไม่สร้างตารางใหม่)
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

_ENUM = sa.Enum('passed', 'failed', name='importedcompletion')


def upgrade() -> None:
    # add_column ไม่สร้าง ENUM type ให้เองบน Postgres (create_table ทำให้ แต่ add_column ไม่)
    bind = op.get_bind()
    if bind.dialect.name == 'postgresql':
        _ENUM.create(bind, checkfirst=True)
    op.add_column('student', sa.Column('imported_completion', _ENUM, nullable=True))


def downgrade() -> None:
    # DROP COLUMN บน SQLite ต้องผ่าน batch (สร้างตารางใหม่แล้ว rename ทับ) ซึ่งล้มถ้ายังมี
    # gold view ค้างอยู่ — init_gold_layer() สร้างกลับให้ตอนแอปบูต
    for name in GOLD_VIEW_NAMES:
        op.execute(f'DROP VIEW IF EXISTS {name}')
    with op.batch_alter_table('student') as batch:
        batch.drop_column('imported_completion')

    bind = op.get_bind()
    if bind.dialect.name == 'postgresql':
        _ENUM.drop(bind, checkfirst=True)
