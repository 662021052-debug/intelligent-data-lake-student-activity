"""student.email: อีเมลรายคนสำหรับแจ้งเตือน — เว้นว่างได้

Revision ID: e0f1a2b3c4d5
Revises: d9e0f1a2b3c4
Create Date: 2026-09-13 10:00:00.000000

เดิมระบบ "เดา" อีเมลจากรหัสนิสิต (<รหัส>@tsu.ac.th) ทั้งที่ไม่รู้ว่าที่อยู่นั้นมีจริงไหม
รายงานผลส่งจึงบอกว่าส่งสำเร็จทั้งที่อาจเด้งกลับหมด คอลัมน์นี้เก็บที่อยู่จริงที่ผู้ดูแล
กรอกเอง — **ไม่ backfill ของเดิม** เพราะจะได้ค่าที่เดาเอาไว้เหมือนเดิม ไม่ต่างจากปัญหาเดิม
นิสิตที่ยังไม่มีอีเมลคือ NULL และการแจ้งเตือนจะข้ามคนกลุ่มนี้แล้วรายงานจำนวนกลับมา

เป็น ADD COLUMN ล้วน ไม่ใช้ batch_alter_table จึงไม่ต้อง DROP gold views ก่อน
(SQLite เพิ่มคอลัมน์ได้ตรง ๆ โดยไม่สร้างตารางใหม่)
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

from app.gold import GOLD_VIEW_NAMES


# revision identifiers, used by Alembic.
revision: str = 'e0f1a2b3c4d5'
down_revision: Union[str, None] = 'd9e0f1a2b3c4'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('student', sa.Column('email', sa.String(length=255), nullable=True))


def downgrade() -> None:
    # DROP COLUMN บน SQLite ต้องผ่าน batch (สร้างตารางใหม่แล้ว rename ทับ) ซึ่งล้มถ้ายังมี
    # gold view ค้างอยู่ — init_gold_layer() สร้างกลับให้ตอนแอปบูต
    for name in GOLD_VIEW_NAMES:
        op.execute(f'DROP VIEW IF EXISTS {name}')
    with op.batch_alter_table('student') as batch:
        batch.drop_column('email')
