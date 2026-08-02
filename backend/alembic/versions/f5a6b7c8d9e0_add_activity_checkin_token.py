"""add activity.checkin_token (QR เช็กอินหน้างาน)

Revision ID: f5a6b7c8d9e0
Revises: e4f5a6b7c8d9
Create Date: 2026-08-02 10:00:00.000000

เพิ่มคอลัมน์ทีละขั้นเพราะกิจกรรมเดิมยังไม่มี token: เพิ่มแบบ nullable ก่อน →
backfill uuid ให้ทุกแถว → ค่อยบังคับ NOT NULL + unique index
"""
import uuid
from typing import Sequence, Union

import sqlalchemy as sa
import sqlmodel
from alembic import op

from app.gold import GOLD_VIEW_NAMES


# revision identifiers, used by Alembic.
revision: str = 'f5a6b7c8d9e0'
down_revision: Union[str, None] = 'e4f5a6b7c8d9'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_INDEX = 'ix_activity_checkin_token'


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
    op.add_column(
        'activity',
        sa.Column('checkin_token', sqlmodel.sql.sqltypes.AutoString(), nullable=True),
    )

    conn = op.get_bind()
    activity_ids = [row[0] for row in conn.execute(sa.text('SELECT id FROM activity'))]
    for activity_id in activity_ids:
        conn.execute(
            sa.text('UPDATE activity SET checkin_token = :token WHERE id = :id'),
            {'token': uuid.uuid4().hex, 'id': activity_id},
        )

    # batch_alter_table เพื่อให้ SQLite (ที่ ALTER COLUMN ไม่ได้) ใช้ได้ด้วย
    with op.batch_alter_table('activity') as batch:
        batch.alter_column(
            'checkin_token',
            existing_type=sqlmodel.sql.sqltypes.AutoString(),
            nullable=False,
        )
    op.create_index(_INDEX, 'activity', ['checkin_token'], unique=True)


def downgrade() -> None:
    _drop_gold_views()
    op.drop_index(_INDEX, table_name='activity')
    with op.batch_alter_table('activity') as batch:
        batch.drop_column('checkin_token')
