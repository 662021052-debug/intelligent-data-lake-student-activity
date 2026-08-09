"""add activity.is_hidden (ซ่อนแทนการลบเมื่อมีผู้เข้าร่วมแล้ว)

Revision ID: a6b7c8d9e0f1
Revises: f5a6b7c8d9e0
Create Date: 2026-08-09 10:00:00.000000

เพิ่มคอลัมน์ทีละขั้นเหมือน migration ก่อนหน้า: เพิ่มแบบ nullable ก่อน →
backfill ให้ทุกแถวเป็น false (กิจกรรมเดิมยังไม่มีอันไหนถูกซ่อน) → ค่อยบังคับ NOT NULL
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

from app.gold import GOLD_VIEW_NAMES


# revision identifiers, used by Alembic.
revision: str = 'a6b7c8d9e0f1'
down_revision: Union[str, None] = 'f5a6b7c8d9e0'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_INDEX = 'ix_activity_is_hidden'


def _drop_gold_views() -> None:
    """gold_* เป็น VIEW ที่อ่านตาราง activity อยู่

    บน SQLite `batch_alter_table` สร้างตารางใหม่แล้ว RENAME ทับของเดิม ซึ่ง SQLite
    จะตรวจ view ทุกตัวตอน rename แล้วล้มด้วย "no such table: main.activity"
    จึงต้องทิ้ง view ก่อน — ไม่เสียหาย เพราะ `init_gold_layer()` สร้างใหม่ทุกครั้ง
    ที่แอปบูต (และเรียกซ้ำได้จาก POST /gold/refresh)
    """
    for name in GOLD_VIEW_NAMES:
        op.execute(f'DROP VIEW IF EXISTS {name}')


def upgrade() -> None:
    _drop_gold_views()
    op.add_column('activity', sa.Column('is_hidden', sa.Boolean(), nullable=True))
    # `false` แทน `0` เพราะบน Postgres คอลัมน์เป็น boolean แท้ (SQLite รับทั้งสองแบบ)
    op.execute(sa.text('UPDATE activity SET is_hidden = false WHERE is_hidden IS NULL'))

    # batch_alter_table เพื่อให้ SQLite (ที่ ALTER COLUMN ไม่ได้) ใช้ได้ด้วย
    with op.batch_alter_table('activity') as batch:
        batch.alter_column('is_hidden', existing_type=sa.Boolean(), nullable=False)
    op.create_index(_INDEX, 'activity', ['is_hidden'])


def downgrade() -> None:
    _drop_gold_views()
    op.drop_index(_INDEX, table_name='activity')
    with op.batch_alter_table('activity') as batch:
        batch.drop_column('is_hidden')
