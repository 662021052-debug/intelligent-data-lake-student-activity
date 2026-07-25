"""add silver_evidence_ocr table (Silver layer OCR results)

Revision ID: d3e4f5a6b7c8
Revises: c2d3e4f5a6b7
Create Date: 2026-07-23 10:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
import sqlmodel


# revision identifiers, used by Alembic.
revision: str = 'd3e4f5a6b7c8'
down_revision: Union[str, None] = 'c2d3e4f5a6b7'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'silver_evidence_ocr',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('raw_file_id', sa.Integer(), nullable=False),
        sa.Column('participation_id', sa.Integer(), nullable=True),
        sa.Column('extracted_text', sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.Column('ocr_confidence', sa.Float(), nullable=False),
        sa.Column('match_score', sa.Float(), nullable=False),
        sa.Column(
            'decision',
            sa.Enum('auto_approved', 'needs_review', 'flagged', name='ocrdecision'),
            nullable=False,
        ),
        sa.Column('is_duplicate', sa.Boolean(), nullable=False),
        sa.Column('processed_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['participation_id'], ['participation.id'], ),
        sa.ForeignKeyConstraint(['raw_file_id'], ['raw_file.id'], ),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(
        op.f('ix_silver_evidence_ocr_raw_file_id'),
        'silver_evidence_ocr', ['raw_file_id'], unique=False,
    )
    op.create_index(
        op.f('ix_silver_evidence_ocr_participation_id'),
        'silver_evidence_ocr', ['participation_id'], unique=False,
    )


def downgrade() -> None:
    op.drop_index(op.f('ix_silver_evidence_ocr_participation_id'), table_name='silver_evidence_ocr')
    op.drop_index(op.f('ix_silver_evidence_ocr_raw_file_id'), table_name='silver_evidence_ocr')
    op.drop_table('silver_evidence_ocr')
