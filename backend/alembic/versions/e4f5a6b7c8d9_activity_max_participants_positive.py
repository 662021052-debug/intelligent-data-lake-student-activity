"""enforce activity.max_participants > 0 (CHECK constraint)

Revision ID: e4f5a6b7c8d9
Revises: d3e4f5a6b7c8
Create Date: 2026-07-23 12:00:00.000000

A 0 (or negative) capacity is meaningless and divides-by-zero in the dashboard
low-participation fill-rate query on Postgres. Guard it at the DB level too.
"""
from typing import Sequence, Union

from alembic import op


# revision identifiers, used by Alembic.
revision: str = 'e4f5a6b7c8d9'
down_revision: Union[str, None] = 'd3e4f5a6b7c8'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_CONSTRAINT = 'ck_activity_max_participants_positive'


def upgrade() -> None:
    # batch_alter_table so this also works on SQLite (recreates the table);
    # on Postgres it becomes a plain ALTER TABLE ... ADD CONSTRAINT.
    with op.batch_alter_table('activity') as batch:
        batch.create_check_constraint(_CONSTRAINT, 'max_participants > 0')


def downgrade() -> None:
    with op.batch_alter_table('activity') as batch:
        batch.drop_constraint(_CONSTRAINT, type_='check')
