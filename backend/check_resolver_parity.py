"""ตรวจว่าตัวแมป "รุ่น → ชุดเกณฑ์" ตัวใหม่ให้ผลตรงกับชุดที่นิสิตถืออยู่จริงทุกคน

เฟส 1 ของ PROMPT_CriteriaSet_Management.md เปลี่ยนกติกาจาก hardcode (``cohort >= 2567``)
มาเป็นอ่าน ``criteria_set.effective_from_cohort`` จากฐาน การแตะตรงนี้กระทบการคำนวณ
ความครบเกณฑ์ของนิสิตทุกคน จึงต้องพิสูจน์ก่อนว่า **ไม่มีใครเปลี่ยนชุด**

รันบนฐานจริง:
    docker compose exec backend python check_resolver_parity.py
"""

from __future__ import annotations

import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

from sqlmodel import Session, select

from app.criteria import cohort_from_student_id, resolve_criteria_set_id
from app.database import engine
from app.models import CriteriaSet, Student


def main() -> int:
    with Session(engine) as session:
        code_by_id = {cs.id: cs.code for cs in session.exec(select(CriteriaSet)).all()}
        students = session.exec(select(Student).order_by(Student.student_id)).all()

        print(f"นิสิตทั้งหมด {len(students)} คน · ชุดเกณฑ์ในฐาน {len(code_by_id)} ชุด")
        print()

        by_pair: dict[tuple, int] = {}
        mismatches: list[str] = []
        unresolved: list[str] = []

        for student in students:
            stored = student.criteria_set_id
            # เรียกแบบเดียวกับที่ router ใช้ตอนสร้าง/แก้นิสิต
            computed = resolve_criteria_set_id(
                session, student.student_id, student.program_type, student.cohort
            )
            cohort = student.cohort or cohort_from_student_id(student.student_id)
            key = (cohort, code_by_id.get(stored, "(ไม่มีชุด)"), code_by_id.get(computed, "(ไม่มีชุด)"))
            by_pair[key] = by_pair.get(key, 0) + 1

            if computed is None:
                unresolved.append(f"{student.student_id} (รุ่น {cohort})")
            elif computed != stored:
                mismatches.append(
                    f"{student.student_id} (รุ่น {cohort}): "
                    f"ในฐาน {code_by_id.get(stored)} แต่ตัวแมปใหม่ให้ {code_by_id.get(computed)}"
                )

        print(f"{'รุ่น':<8}{'ชุดในฐาน':<16}{'ตัวแมปใหม่':<16}{'จำนวน':>8}   ผล")
        for (cohort, stored_code, computed_code), count in sorted(
            by_pair.items(), key=lambda item: (item[0][0] or 0, item[0][1])
        ):
            verdict = "ตรงกัน" if stored_code == computed_code else "*** ไม่ตรง ***"
            print(f"{cohort or '-':<8}{stored_code:<16}{computed_code:<16}{count:>8}   {verdict}")

        print()
        if unresolved:
            print(f"แมปไม่ได้เลย {len(unresolved)} คน:")
            for line in unresolved[:10]:
                print(f"  - {line}")
        if mismatches:
            print(f"ไม่ตรง {len(mismatches)} คน:")
            for line in mismatches[:20]:
                print(f"  - {line}")
            return 1

        print(f"ผ่าน — นิสิตทั้ง {len(students)} คนแมปเข้าชุดเดิมเป๊ะ ไม่มีใครย้ายชุด")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
