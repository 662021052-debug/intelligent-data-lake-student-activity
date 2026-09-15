"""participation.reminder_sent_at: กันอีเมลเตือนกิจกรรมซ้ำ (Email Notifications เฟส 1)

Revision ID: d5e6f7a8b9c0
Revises: c4d5e6f7a8b9
Create Date: 2026-09-15 23:00:00.000000

* ตั้งเมื่อตัวเตือน "พรุ่งนี้มีกิจกรรม" ส่งสำเร็จ หรือเมื่ออีเมลยืนยันการสมัครทำหน้าที่เตือนแทน
  (กิจกรรมจัดภายในวันพรุ่งนี้ตามเวลาไทย)
* ตัวเตือนส่งเฉพาะแถวที่ยังเป็น NULL

nullable ไม่ backfill — แถวเดิมเป็น NULL = ยังไม่เคยถูกเตือน ตรงกับความจริง (scheduler ไม่เคยเปิด)

ADD COLUMN ล้วน ไม่มี FK จึงไม่ใช้ batch_alter_table ตอน upgrade และไม่ต้อง DROP gold views
(downgrade DROP COLUMN ผ่าน batch บน SQLite จึงทิ้ง views ก่อนตามแนวเดิม)
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

from app.gold import GOLD_VIEW_NAMES


# revision identifiers, used by Alembic.
revision: str = 'd5e6f7a8b9c0'
down_revision: Union[str, None] = 'c4d5e6f7a8b9'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('participation', sa.Column('reminder_sent_at', sa.DateTime(), nullable=True))


def downgrade() -> None:
    for name in GOLD_VIEW_NAMES:
        op.execute(f'DROP VIEW IF EXISTS {name}')
    with op.batch_alter_table('participation') as batch:
        batch.drop_column('reminder_sent_at')
