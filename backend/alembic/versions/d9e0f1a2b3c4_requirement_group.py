"""requirement_group: กลุ่มรายการเกณฑ์ที่ใช้เป้าชั่วโมงร่วมกัน (กฎ Social รวม ≥ 16)

Revision ID: d9e0f1a2b3c4
Revises: c8d9e0f1a2b3
Create Date: 2026-09-12 10:00:00.000000

เดิมกฎ "สองด้านของ Social รวมกัน ≥ 16 ชม." มีแค่ในข้อความ rule_note ระบบตรวจเองไม่ได้
ตารางนี้ทำให้กฎเป็นโครงสร้าง: รายการที่มี group_id ถูกตรวจที่ยอดรวมของกลุ่ม
(ข้อมูลกลุ่มจริงใส่โดย seed_criteria.py ที่รันตอนคอนเทนเนอร์บูต — migration แตะแค่ schema)

DROP gold views ก่อนตามแนวเดิมของโปรเจกต์ เพราะการเพิ่ม FK บน SQLite ต้องผ่าน
batch_alter_table (สร้างตารางใหม่แล้ว rename ทับ) ซึ่งล้มถ้ายังมี view ค้างอยู่
"""
from typing import Sequence, Union

import sqlalchemy as sa
import sqlmodel
from alembic import op

from app.gold import GOLD_VIEW_NAMES


# revision identifiers, used by Alembic.
revision: str = 'd9e0f1a2b3c4'
down_revision: Union[str, None] = 'c8d9e0f1a2b3'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _drop_gold_views() -> None:
    for name in GOLD_VIEW_NAMES:
        op.execute(f'DROP VIEW IF EXISTS {name}')


def upgrade() -> None:
    _drop_gold_views()

    op.create_table(
        'requirement_group',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('criteria_set_id', sa.Integer(), nullable=False),
        sa.Column('code', sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.Column('name', sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.Column('required_hours', sa.Float(), nullable=False),
        sa.Column('rule_note', sqlmodel.sql.sqltypes.AutoString(), nullable=True),
        sa.ForeignKeyConstraint(['criteria_set_id'], ['criteria_set.id']),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_requirement_group_criteria_set_id', 'requirement_group', ['criteria_set_id'])

    op.add_column('requirement', sa.Column('group_id', sa.Integer(), nullable=True))
    with op.batch_alter_table('requirement') as batch:
        batch.create_foreign_key(
            'fk_requirement_group_id', 'requirement_group', ['group_id'], ['id']
        )
    op.create_index('ix_requirement_group_id', 'requirement', ['group_id'])


def downgrade() -> None:
    _drop_gold_views()

    op.drop_index('ix_requirement_group_id', table_name='requirement')
    with op.batch_alter_table('requirement') as batch:
        batch.drop_constraint('fk_requirement_group_id', type_='foreignkey')
        batch.drop_column('group_id')

    op.drop_index('ix_requirement_group_criteria_set_id', table_name='requirement_group')
    op.drop_table('requirement_group')
