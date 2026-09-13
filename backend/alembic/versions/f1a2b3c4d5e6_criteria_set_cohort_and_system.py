"""criteria_set: effective_from_cohort + is_system — แมปรุ่น→ชุดแบบ data-driven

Revision ID: f1a2b3c4d5e6
Revises: e0f1a2b3c4d5
Create Date: 2026-09-13 14:00:00.000000

เดิมการแมป "นิสิตรหัส NN ใช้เกณฑ์ชุดไหน" ฝังอยู่ในโค้ด (``cohort >= 2567``) การเพิ่ม
ชุดของรุ่นถัดไปจึงต้องแก้โปรแกรมทุกครั้ง สองคอลัมน์นี้ย้ายกติกานั้นลงมาเป็นข้อมูล:

* ``effective_from_cohort`` — ปีรุ่นแรกที่ชุดนั้นเริ่มใช้ ระบบเลือกชุดที่ค่านี้สูงสุด
  ที่ยังไม่เกินรุ่นของนิสิต เพิ่มแถวของรุ่น 2570 แล้วนิสิตรหัส 70 ขึ้นไปจะย้ายไปเอง
* ``is_system`` — แยก "เกณฑ์ทางการที่ seed ไว้" ออกจาก "ชุดที่ผู้ดูแลสร้างเอง"
  ตัว seed จะเขียนทับได้เฉพาะชุดระบบ ของที่คนทำเองจึงไม่หายตอนคอนเทนเนอร์บูต

backfill: ทุกแถวที่มีอยู่ ณ ตอนนี้มาจาก ``seed_criteria.py`` ทั้งหมด (ยังไม่มี API ให้
สร้างเอง) จึงเป็นชุดระบบทุกแถว · legacy ได้ 0 = ครอบรุ่นเก่าทั้งหมด ส่วนชุดอื่นใช้
``academic_year`` ของตัวเอง ซึ่งตรงกับกติกาเดิม (ชุด 2567 เริ่มที่รุ่น 2567) เป๊ะ
จึงไม่มีนิสิตคนไหนเปลี่ยนชุดเพราะ migration นี้

เป็น ADD COLUMN ล้วน ไม่ใช้ batch_alter_table จึงไม่ต้อง DROP gold views ก่อน
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

from app.gold import GOLD_VIEW_NAMES


# revision identifiers, used by Alembic.
revision: str = 'f1a2b3c4d5e6'
down_revision: Union[str, None] = 'e0f1a2b3c4d5'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

LEGACY_CODE = 'legacy-2566'


def upgrade() -> None:
    # server_default จำเป็นตอน ADD COLUMN NOT NULL บนตารางที่มีแถวอยู่แล้ว
    op.add_column(
        'criteria_set',
        sa.Column('effective_from_cohort', sa.Integer(), nullable=False, server_default='0'),
    )
    op.add_column(
        'criteria_set',
        sa.Column('is_system', sa.Boolean(), nullable=False, server_default=sa.false()),
    )
    op.create_index(
        'ix_criteria_set_effective_from_cohort', 'criteria_set', ['effective_from_cohort']
    )

    # backfill — ดูเหตุผลใน docstring
    op.execute(
        f"UPDATE criteria_set SET effective_from_cohort = academic_year "
        f"WHERE code <> '{LEGACY_CODE}'"
    )
    op.execute(
        f"UPDATE criteria_set SET effective_from_cohort = 0 WHERE code = '{LEGACY_CODE}'"
    )
    op.execute("UPDATE criteria_set SET is_system = true")


def downgrade() -> None:
    # DROP COLUMN บน SQLite ต้องผ่าน batch (สร้างตารางใหม่แล้ว rename ทับ) ซึ่งล้มถ้ายังมี
    # gold view ค้างอยู่ — init_gold_layer() สร้างกลับให้ตอนแอปบูต
    for name in GOLD_VIEW_NAMES:
        op.execute(f'DROP VIEW IF EXISTS {name}')
    op.drop_index('ix_criteria_set_effective_from_cohort', table_name='criteria_set')
    with op.batch_alter_table('criteria_set') as batch:
        batch.drop_column('is_system')
        batch.drop_column('effective_from_cohort')
