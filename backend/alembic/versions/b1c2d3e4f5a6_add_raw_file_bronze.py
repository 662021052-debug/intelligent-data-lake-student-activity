"""add raw_file table (Bronze layer metadata / data lineage)

Revision ID: b1c2d3e4f5a6
Revises: a772953965c8
Create Date: 2026-07-21 09:30:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
import sqlmodel


# revision identifiers, used by Alembic.
revision: str = 'b1c2d3e4f5a6'
down_revision: Union[str, None] = 'a772953965c8'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'raw_file',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('bucket', sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.Column('object_key', sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.Column('original_filename', sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.Column('content_type', sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.Column('size_bytes', sa.Integer(), nullable=False),
        sa.Column('checksum', sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.Column('source_system', sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.Column('uploaded_by', sa.Integer(), nullable=True),
        sa.Column('ingested_at', sa.DateTime(), nullable=False),
        sa.Column('participation_id', sa.Integer(), nullable=True),
        sa.ForeignKeyConstraint(['participation_id'], ['participation.id'], ),
        sa.ForeignKeyConstraint(['uploaded_by'], ['user.id'], ),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(op.f('ix_raw_file_checksum'), 'raw_file', ['checksum'], unique=False)
    op.create_index(
        op.f('ix_raw_file_participation_id'), 'raw_file', ['participation_id'], unique=False
    )


def downgrade() -> None:
    op.drop_index(op.f('ix_raw_file_participation_id'), table_name='raw_file')
    op.drop_index(op.f('ix_raw_file_checksum'), table_name='raw_file')
    op.drop_table('raw_file')
