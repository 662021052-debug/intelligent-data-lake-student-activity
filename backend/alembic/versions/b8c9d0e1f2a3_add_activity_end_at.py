"""activity.end_at: เวลาสิ้นสุดกิจกรรม (กรอกเมื่อสร้าง/แก้ ไม่บังคับ)

Revision ID: b8c9d0e1f2a3
Revises: d5e6f7a8b9c0
Create Date: 2026-09-21 10:00:00.000000

* timestamp ไม่มีโซน nullable — เก็บเป็น "เวลาไทยแบบไม่มีโซน" เหมือน start_at
  (ดู app/timeutil.py) ไม่ผ่าน UTC
* ข้อมูลประกอบเท่านั้น: ชั่วโมงยังมาจาก activity.hours และช่วงเช็กอินยังคำนวณจาก
  start_at + hours เหมือนเดิม
* nullable ไม่ backfill — กิจกรรมเดิมไม่มีเวลาสิ้นสุด (NULL = ไม่ได้ระบุ) ตรงกับความจริง

ADD COLUMN ล้วน ไม่มี FK จึงไม่ใช้ batch_alter_table ตอน upgrade และไม่ต้อง DROP gold views
(downgrade DROP COLUMN ผ่าน batch บน SQLite จึงทิ้ง views ก่อนตามแนวเดิม)
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

from app.gold import GOLD_VIEW_NAMES


# revision identifiers, used by Alembic.
revision: str = 'b8c9d0e1f2a3'
down_revision: Union[str, None] = 'd5e6f7a8b9c0'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('activity', sa.Column('end_at', sa.DateTime(), nullable=True))


def downgrade() -> None:
    for name in GOLD_VIEW_NAMES:
        op.execute(f'DROP VIEW IF EXISTS {name}')
    with op.batch_alter_table('activity') as batch:
        batch.drop_column('end_at')
