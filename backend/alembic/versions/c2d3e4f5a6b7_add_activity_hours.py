"""add activity.hours (hours granted per activity)

Revision ID: c2d3e4f5a6b7
Revises: b1c2d3e4f5a6
Create Date: 2026-07-21 10:30:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
import sqlmodel


# revision identifiers, used by Alembic.
revision: str = 'c2d3e4f5a6b7'
down_revision: Union[str, None] = 'b1c2d3e4f5a6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_FALLBACK_HOURS = 3.0


def upgrade() -> None:
    op.add_column('activity', sa.Column('hours', sa.Float(), nullable=True))

    # Backfill: an activity grants the hours of its linked subcategory (best available
    # signal); anything without a subcategory gets a sane fallback.
    bind = op.get_bind()
    activity = sa.table(
        "activity",
        sa.column("id", sa.Integer),
        sa.column("hours", sa.Float),
        sa.column("subcategory_id", sa.Integer),
    )
    hoursubcategory = sa.table(
        "hoursubcategory",
        sa.column("id", sa.Integer),
        sa.column("required_hours", sa.Float),
    )
    required_by_sub = dict(
        bind.execute(
            sa.select(hoursubcategory.c.id, hoursubcategory.c.required_hours)
        ).all()
    )
    for row in bind.execute(sa.select(activity.c.id, activity.c.subcategory_id)).all():
        value = required_by_sub.get(row.subcategory_id) or _FALLBACK_HOURS
        bind.execute(activity.update().where(activity.c.id == row.id).values(hours=value))

    with op.batch_alter_table("activity", schema=None) as batch_op:
        batch_op.alter_column("hours", existing_type=sa.Float(), nullable=False)


def downgrade() -> None:
    with op.batch_alter_table("activity", schema=None) as batch_op:
        batch_op.drop_column("hours")
