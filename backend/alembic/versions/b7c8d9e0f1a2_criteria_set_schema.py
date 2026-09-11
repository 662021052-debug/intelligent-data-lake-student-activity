"""เกณฑ์กิจกรรมแบบมีเวอร์ชัน: criteria_set / talent / learning_unit / requirement / activity_requirement

Revision ID: b7c8d9e0f1a2
Revises: a6b7c8d9e0f1
Create Date: 2026-09-09 21:30:00.000000

โครงเดิม hourcategory(5)/hoursubcategory(13) เก็บ required_hours ชุดเดียวใช้ร่วมทุกปี
จึงรองรับเกณฑ์ที่ต่างกันตามรุ่น/กลุ่มนิสิตไม่ได้ (ดู DB_Redesign_ActivityCriteria.md §1-3)

migration นี้ "เพิ่มของใหม่" อย่างเดียว ยังไม่ถอดของเดิมทิ้ง — hourcategory/
hoursubcategory และ activity.subcategory_id ยังอยู่ครบ เพราะ gold views, การนำเข้า
แผนกิจกรรม และแชตบอตยังอ่านอยู่ (จะย้ายไปใช้ requirement ในเฟสถัดไปตามแผน)

ตามด้วยขั้นตอนเดิมของโปรเจกต์: DROP gold views ก่อนแตะตาราง เพราะ batch_alter_table
บน SQLite สร้างตารางใหม่แล้ว rename ทับ ซึ่งจะล้มถ้ายังมี view ค้างอยู่
(`init_gold_layer()` สร้าง view ใหม่ให้ทุกครั้งที่แอปบูต)
"""
from typing import Sequence, Union

import sqlalchemy as sa
import sqlmodel
from alembic import op

from app.gold import GOLD_VIEW_NAMES


# revision identifiers, used by Alembic.
revision: str = 'b7c8d9e0f1a2'
down_revision: Union[str, None] = 'a6b7c8d9e0f1'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _drop_gold_views() -> None:
    for name in GOLD_VIEW_NAMES:
        op.execute(f'DROP VIEW IF EXISTS {name}')


def upgrade() -> None:
    _drop_gold_views()

    op.create_table(
        'criteria_set',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('code', sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.Column('academic_year', sa.Integer(), nullable=False),
        sa.Column(
            'program_type',
            sa.Enum('regular', 'continuing', name='programtype'),
            nullable=False,
        ),
        sa.Column('name', sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.Column('total_required_hours', sa.Float(), nullable=False),
        sa.Column(
            'counting_rule',
            sa.Enum('total_per_unit', 'min_per_requirement', name='countingrule'),
            nullable=False,
        ),
        sa.Column('is_active', sa.Boolean(), nullable=False),
        sa.Column('effective_from', sa.Date(), nullable=True),
        sa.Column('effective_to', sa.Date(), nullable=True),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_criteria_set_code', 'criteria_set', ['code'], unique=True)

    op.create_table(
        'talent',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('criteria_set_id', sa.Integer(), nullable=False),
        sa.Column('code', sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.Column('name', sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.Column('plo', sqlmodel.sql.sqltypes.AutoString(), nullable=True),
        sa.Column('sort_order', sa.Integer(), nullable=False),
        sa.ForeignKeyConstraint(['criteria_set_id'], ['criteria_set.id']),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_talent_criteria_set_id', 'talent', ['criteria_set_id'])

    op.create_table(
        'learning_unit',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('code', sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.Column('name', sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_learning_unit_code', 'learning_unit', ['code'], unique=True)

    op.create_table(
        'requirement',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('criteria_set_id', sa.Integer(), nullable=False),
        sa.Column('talent_id', sa.Integer(), nullable=True),
        sa.Column('learning_unit_id', sa.Integer(), nullable=False),
        sa.Column('name', sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.Column('is_mandatory', sa.Boolean(), nullable=False),
        sa.Column('required_hours', sa.Float(), nullable=False),
        sa.Column('min_activities', sa.Integer(), nullable=True),
        sa.Column('rule_note', sqlmodel.sql.sqltypes.AutoString(), nullable=True),
        sa.Column('organizer', sqlmodel.sql.sqltypes.AutoString(), nullable=True),
        sa.ForeignKeyConstraint(['criteria_set_id'], ['criteria_set.id']),
        sa.ForeignKeyConstraint(['talent_id'], ['talent.id']),
        sa.ForeignKeyConstraint(['learning_unit_id'], ['learning_unit.id']),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_requirement_criteria_set_id', 'requirement', ['criteria_set_id'])
    op.create_index('ix_requirement_talent_id', 'requirement', ['talent_id'])
    op.create_index('ix_requirement_learning_unit_id', 'requirement', ['learning_unit_id'])

    # กิจกรรมหนึ่งงานนับให้ได้หลายรายการเกณฑ์ — PK คู่กันเองกันการผูกซ้ำ
    op.create_table(
        'activity_requirement',
        sa.Column('activity_id', sa.Integer(), nullable=False),
        sa.Column('requirement_id', sa.Integer(), nullable=False),
        sa.ForeignKeyConstraint(['activity_id'], ['activity.id']),
        sa.ForeignKeyConstraint(['requirement_id'], ['requirement.id']),
        sa.PrimaryKeyConstraint('activity_id', 'requirement_id'),
    )

    # --- student: รุ่น + กลุ่มหลักสูตร + ชุดเกณฑ์ที่ต้องทำให้ครบ ---
    op.add_column('student', sa.Column('cohort', sa.Integer(), nullable=True))
    op.add_column(
        'student',
        sa.Column(
            'program_type',
            sa.Enum('regular', 'continuing', name='programtype'),
            nullable=True,
        ),
    )
    op.add_column('student', sa.Column('criteria_set_id', sa.Integer(), nullable=True))
    # นิสิตเดิมทุกคนเป็นหลักสูตรปกติ (ยังไม่มีแหล่งข้อมูลของกลุ่มต่อเนื่อง)
    op.execute(sa.text("UPDATE student SET program_type = 'regular' WHERE program_type IS NULL"))
    with op.batch_alter_table('student') as batch:
        batch.alter_column(
            'program_type',
            existing_type=sa.Enum('regular', 'continuing', name='programtype'),
            nullable=False,
        )
        batch.create_foreign_key(
            'fk_student_criteria_set_id', 'criteria_set', ['criteria_set_id'], ['id']
        )
    op.create_index('ix_student_criteria_set_id', 'student', ['criteria_set_id'])

    # --- participation: snapshot หน่วยการเรียนรู้/ชื่อเกณฑ์ ณ เวลาอนุมัติ ---
    op.add_column('participation', sa.Column('learning_unit_id', sa.Integer(), nullable=True))
    op.add_column(
        'participation',
        sa.Column('requirement_name', sqlmodel.sql.sqltypes.AutoString(), nullable=True),
    )
    with op.batch_alter_table('participation') as batch:
        batch.create_foreign_key(
            'fk_participation_learning_unit_id', 'learning_unit', ['learning_unit_id'], ['id']
        )
    op.create_index('ix_participation_learning_unit_id', 'participation', ['learning_unit_id'])

    # --- activity.subcategory_id: ยังอยู่ แต่ไม่ใช่ทางเดียวในการจัดหมวดอีกต่อไป ---
    # (คอลัมน์เป็น nullable อยู่แล้วในตาราง — ฝั่ง API เพิ่งเลิกบังคับ)


def downgrade() -> None:
    _drop_gold_views()

    op.drop_index('ix_participation_learning_unit_id', table_name='participation')
    with op.batch_alter_table('participation') as batch:
        batch.drop_constraint('fk_participation_learning_unit_id', type_='foreignkey')
        batch.drop_column('requirement_name')
        batch.drop_column('learning_unit_id')

    op.drop_index('ix_student_criteria_set_id', table_name='student')
    with op.batch_alter_table('student') as batch:
        batch.drop_constraint('fk_student_criteria_set_id', type_='foreignkey')
        batch.drop_column('criteria_set_id')
        batch.drop_column('program_type')
        batch.drop_column('cohort')

    op.drop_table('activity_requirement')
    op.drop_index('ix_requirement_learning_unit_id', table_name='requirement')
    op.drop_index('ix_requirement_talent_id', table_name='requirement')
    op.drop_index('ix_requirement_criteria_set_id', table_name='requirement')
    op.drop_table('requirement')
    op.drop_index('ix_learning_unit_code', table_name='learning_unit')
    op.drop_table('learning_unit')
    op.drop_index('ix_talent_criteria_set_id', table_name='talent')
    op.drop_table('talent')
    op.drop_index('ix_criteria_set_code', table_name='criteria_set')
    op.drop_table('criteria_set')

    # Postgres สร้าง ENUM type แยกจากตาราง ต้องเก็บกวาดเอง (SQLite ไม่มี type นี้)
    bind = op.get_bind()
    if bind.dialect.name == 'postgresql':
        sa.Enum(name='countingrule').drop(bind, checkfirst=True)
        sa.Enum(name='programtype').drop(bind, checkfirst=True)
