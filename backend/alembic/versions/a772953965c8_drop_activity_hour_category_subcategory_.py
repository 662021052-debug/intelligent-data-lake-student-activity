"""drop activity hour_category, subcategory_id is single source

Revision ID: a772953965c8
Revises: 9edffc436b9a
Create Date: 2026-07-20 17:03:57.565910

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
import sqlmodel


# revision identifiers, used by Alembic.
revision: str = 'a772953965c8'
down_revision: Union[str, None] = '9edffc436b9a'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# hour_category was free text unrelated to the real HourCategory/HourSubcategory
# taxonomy, so there is no exact mapping. This is only a best-effort backfill for
# rows that were never given a subcategory_id, using the old value as a loose hint.
_FALLBACK_SUBCATEGORY_BY_HOUR_CATEGORY = {
    "จิตอาสา": "กิจกรรม TSU DO D : สร้างสรรค์สร้างสำนึกรับผิดชอบต่อสังคม",
}
_DEFAULT_FALLBACK_SUBCATEGORY = "กิจกรรมบูรณาการ 5"


def upgrade() -> None:
    bind = op.get_bind()

    activity = sa.table(
        "activity",
        sa.column("id", sa.Integer),
        sa.column("hour_category", sa.String),
        sa.column("subcategory_id", sa.Integer),
    )
    hoursubcategory = sa.table(
        "hoursubcategory",
        sa.column("id", sa.Integer),
        sa.column("name", sa.String),
    )

    # Best-effort backfill before the column is dropped: only rows that were never
    # classified via subcategory_id are touched. If the target HourSubcategory row
    # doesn't exist yet (fresh DB, seed not run), the row is left NULL rather than
    # guessing an arbitrary category.
    name_to_id = dict(
        bind.execute(sa.select(hoursubcategory.c.name, hoursubcategory.c.id)).all()
    )

    unmapped = bind.execute(
        sa.select(activity.c.id, activity.c.hour_category).where(activity.c.subcategory_id.is_(None))
    ).all()

    for row in unmapped:
        target_name = _FALLBACK_SUBCATEGORY_BY_HOUR_CATEGORY.get(
            row.hour_category, _DEFAULT_FALLBACK_SUBCATEGORY
        )
        target_id = name_to_id.get(target_name)
        if target_id is None:
            continue
        bind.execute(
            activity.update().where(activity.c.id == row.id).values(subcategory_id=target_id)
        )

    with op.batch_alter_table("activity", schema=None) as batch_op:
        batch_op.drop_column("hour_category")


def downgrade() -> None:
    # Historical hour_category values are unrecoverable (that's the point of this
    # migration), so the column is restored as nullable rather than replaying the
    # original NOT NULL constraint with fabricated data.
    with op.batch_alter_table("activity", schema=None) as batch_op:
        batch_op.add_column(
            sa.Column("hour_category", sqlmodel.sql.sqltypes.AutoString(), nullable=True)
        )
