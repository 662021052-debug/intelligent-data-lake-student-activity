"""เฟส 4 ของการรื้อ DB: สร้างกิจกรรมจำลองของชุดเกณฑ์ 2567 แล้วผูกรายการเกณฑ์

สร้างกิจกรรมที่อนุมัติแล้วครอบทุกรายการเกณฑ์ของ ``2567-regular`` ในปีการศึกษาปัจจุบัน
แต่ละกิจกรรมผูก ``activity_requirement`` ไปที่รายการเกณฑ์เดียว — ชั่วโมงของกิจกรรมจึง
นับเข้ารายการไหนได้ชัดเจน ไม่ต้องตัดสินว่าจะแบ่งหรือนับซ้ำ

- **รอบที่จัดไปแล้ว** (ต้นปีการศึกษา → เมื่อวาน): ที่นั่งรวมต้องพอให้นิสิตทุกคนในชุด 2567
  ทำรายการนั้นครบชั่วโมง เพราะเฟส 5 จะสร้างการเข้าร่วมย้อนหลังลงรอบเหล่านี้ นิสิตเกือบ
  ทั้งหมดเป็นรุ่น 2569 ที่เพิ่งเข้าเดือนมิถุนายน รอบย้อนหลังจึงต้องอยู่ในปีการศึกษานี้เท่านั้น
  จำนวนรอบคำนวณจากจำนวนนิสิตจริง (+ เผื่อ 10%) ไม่ได้ตั้งตายตัว
- **รอบที่ยังไม่ถึง** (อีกไม่กี่วัน → ปลายภาค 2): รายการละ 1–2 รอบ ไว้โชว์ในหน้าสมัคร

ชั่วโมงต่อรอบหารชั่วโมงของรายการเกณฑ์ลงตัวเสมอ (เช่น TSU Good 10 ชม. = รอบละ 5 ชม. × 2)
เฟส 5 จึงสร้างการเข้าร่วมให้ได้ 60 ชม. พอดี ไม่เกินไม่ขาด

**รันซ้ำได้**: นับกิจกรรมที่ผูกรายการเกณฑ์นั้นในปีการศึกษาเดียวกันที่มีอยู่แล้ว (รวมที่เจ้าหน้าที่
สร้างเองผ่านหน้าจอ) แล้วสร้างเฉพาะส่วนที่ขาด — ไม่ย้ายวันหรือลบกิจกรรมเดิม เพราะอาจมี
การเข้าร่วมผูกอยู่แล้ว

รัน:
    python seed_activities_2567.py
    python seed_activities_2567.py --dry-run
"""

from __future__ import annotations

import argparse
import math
import sys
from dataclasses import dataclass, field
from datetime import date, datetime, time, timedelta
from typing import Optional

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

from sqlmodel import Session, func, select

from app.criteria import CRITERIA_2567_FROM_COHORT
from app.database import create_db_and_tables, engine
from app.models import (
    Activity,
    ActivityRequirement,
    ApprovalStatus,
    CriteriaSet,
    ProgramType,
    Requirement,
    Student,
    StudentStatus,
    User,
    UserRole,
)
from app.timeutil import academic_year_for, today_th

CRITERIA_CODE = f"{CRITERIA_2567_FROM_COHORT}-{ProgramType.regular.value}"

# ต้องตรงกับ `_activityTypes` ใน frontend/lib/screens/activities_screen.dart —
# ประเภทที่ไม่อยู่ในรายการจะกรองจากหน้าจอไม่เจอ และฟอร์มแก้ไขจะไม่มีตัวเลือกให้
ACTIVITY_TYPES = ("จิตอาสา", "กีฬา", "วิชาการ", "ศิลปวัฒนธรรม", "อบรม/สัมมนา")

# เผื่อที่นั่งรอบย้อนหลังไว้ 10% — เฟส 5 จะได้ไม่ต้องยัดทุกรอบจนเต็มพอดี
HEADROOM = 1.1
# รอบที่ "กำลังจะถึง" เริ่มหลังวันนี้อย่างน้อยเท่านี้ ให้นิสิตมีเวลาสมัคร
UPCOMING_LEAD_DAYS = 3
# ปลายภาคเรียนที่ 2 (เดือน, วัน) ของปี ค.ศ. ถัดไป — ภาคฤดูร้อนไม่จัดกิจกรรมพัฒนานิสิต
SEMESTER_2_END = (3, 20)


class SeedAborted(Exception):
    """ฐานยังไม่พร้อม — ไม่ได้เขียนอะไรลงฐาน."""


@dataclass(frozen=True)
class Theme:
    name: str
    activity_type: str
    location: str


@dataclass(frozen=True)
class Plan:
    """แผนกิจกรรมของรายการเกณฑ์หนึ่งรายการ."""

    requirement: str        # ชื่อรายการเกณฑ์ใน seed_criteria.REQUIREMENTS_2567_REGULAR
    hours: float            # ชั่วโมงต่อรอบ — ต้องหาร required_hours ของรายการลงตัว
    capacity: int           # ที่นั่งต่อรอบ
    themes: tuple[Theme, ...]  # ชื่อกิจกรรมที่หมุนเวียนกันไปในแต่ละรอบ
    upcoming: int = 2
    # สัดส่วนของนิสิตที่รายการนี้ต้องรองรับ — สองด้านของ Social ใช้เป้า 16 ชม. ร่วมกัน
    # นิสิตแต่ละคนจึงใช้ที่นั่งของสองด้านรวมกันเท่ากับด้านเดียว แบ่งกันคนละครึ่ง
    demand_share: float = 1.0
    # ช่วงของหน้าต่าง "จัดไปแล้ว" ที่รอบของรายการนี้ไปอยู่ (0 = ต้นปีการศึกษา, 1 = เมื่อวาน)
    # ปฐมนิเทศต้องมาก่อนทุกอย่าง กิจกรรมบังคับอื่นอยู่ต้นภาค ที่เหลือกระจายทั้งภาค
    window: tuple[float, float] = (0.1, 1.0)


PLANS: list[Plan] = [
    # --- Talent 1 · TSU Glocal Talent ---
    Plan(
        "กิจกรรมปฐมนิเทศนิสิต",
        hours=4,
        capacity=2500,
        themes=(Theme("ปฐมนิเทศนิสิตใหม่", "อบรม/สัมมนา", "หอประชุมใหญ่"),),
        upcoming=0,  # จัดครั้งเดียวต้นปีการศึกษา
        window=(0.0, 0.03),
    ),
    Plan(
        "กิจกรรมเกี่ยวกับการใช้ชีวิตในมหาวิทยาลัย",
        hours=4,
        capacity=1200,
        themes=(
            Theme("TSU Life ใช้ชีวิตในมหาวิทยาลัยอย่างมีวินัย", "อบรม/สัมมนา", "หอประชุมใหญ่"),
            Theme("รู้ทันกฎระเบียบและวินัยนิสิต", "อบรม/สัมมนา", "ศูนย์ประชุมนานาชาติ"),
        ),
        upcoming=1,
        window=(0.03, 0.25),
    ),
    Plan(
        "การคิด วิจารณญาณ และการแก้ปัญหา",
        hours=3,
        capacity=400,
        themes=(
            Theme("เวิร์กช็อป Design Thinking แก้โจทย์จริง", "วิชาการ", "อาคารเรียนรวม 1"),
            Theme("ฝึกคิดวิเคราะห์ รู้ทันข่าวลวง", "อบรม/สัมมนา", "ห้อง SC101"),
        ),
    ),
    Plan(
        "การบริหารจัดการตนเอง",
        hours=3,
        capacity=400,
        themes=(
            Theme("บริหารเวลาและเป้าหมายชีวิตนิสิต", "อบรม/สัมมนา", "ห้องประชุมคณะ"),
            Theme("เวิร์กช็อปสุขภาพจิตดีมีสุข", "อบรม/สัมมนา", "ศูนย์ประชุมนานาชาติ"),
        ),
    ),
    Plan(
        "การทำงานร่วมกับผู้อื่น",
        hours=3,
        capacity=400,
        themes=(
            Theme("กีฬาสัมพันธ์ละลายพฤติกรรม", "กีฬา", "โรงยิมเนเซียม"),
            Theme("ค่ายทักษะการทำงานเป็นทีม", "อบรม/สัมมนา", "ลานกิจกรรม"),
        ),
    ),
    Plan(
        "ความรู้ ความเข้าใจ และการใช้เทคโนโลยีดิจิทัล",
        hours=3,
        capacity=400,
        themes=(
            Theme("รู้เท่าทันสื่อดิจิทัลและ AI", "วิชาการ", "อาคารเรียนรวม 1"),
            Theme("ความปลอดภัยไซเบอร์สำหรับนิสิต", "วิชาการ", "ห้อง SC101"),
        ),
    ),
    Plan(
        "กลุ่ม TSU Good (จิตอาสา/บำเพ็ญประโยชน์/สิ่งแวดล้อม)",
        hours=5,
        capacity=500,
        themes=(
            Theme("จิตอาสาปลูกป่าชายเลนทะเลสาบสงขลา", "จิตอาสา", "ชุมชนบ้านปากพะยูน"),
            Theme("Big Cleaning Day ชุมชนรอบมหาวิทยาลัย", "จิตอาสา", "ลานกิจกรรม"),
            Theme("จิตอาสาบริจาคโลหิตและดูแลผู้สูงอายุ", "จิตอาสา", "สนามกีฬากลาง"),
        ),
    ),
    # --- Talent 2 · TSU Communication Talent ---
    Plan(
        "ทักษะการใช้ภาษาเพื่อการสื่อสารในชีวิตประจำวัน",
        hours=5,
        capacity=400,
        themes=(
            Theme("English for Everyday Communication", "วิชาการ", "อาคารเรียนรวม 1"),
            Theme("ภาษามลายูเพื่อการสื่อสารในอาเซียน", "ศิลปวัฒนธรรม", "ห้องประชุมคณะ"),
            Theme("TSU English Camp", "วิชาการ", "ศูนย์ประชุมนานาชาติ"),
        ),
    ),
    # --- Talent 3 · TSU Social Innovation/Entrepreneurship ---
    Plan(
        "แนวคิดการเป็นนักนวัตกรรมสังคม/ผู้ประกอบการ",
        hours=4,
        capacity=1200,
        themes=(
            Theme("ปลุกพลังนวัตกรสังคมและผู้ประกอบการรุ่นใหม่", "อบรม/สัมมนา", "หอประชุมใหญ่"),
        ),
        upcoming=1,
        window=(0.05, 0.5),
    ),
    Plan(
        "ด้านการสร้างนวัตกรรมสังคม",
        hours=4,
        capacity=400,
        themes=(
            Theme("เวิร์กช็อปนวัตกรรมเพื่อชุมชน", "วิชาการ", "ชุมชนบ้านปากพะยูน"),
            Theme("Hackathon แก้ปัญหาสังคมท้องถิ่น", "วิชาการ", "อาคารเรียนรวม 1"),
        ),
        demand_share=0.5,
    ),
    Plan(
        "ด้านการเป็นผู้ประกอบการ",
        hours=4,
        capacity=400,
        themes=(
            Theme("ปั้นไอเดียธุรกิจ Startup นิสิต", "วิชาการ", "ศูนย์ประชุมนานาชาติ"),
            Theme("ตลาดนัดผู้ประกอบการรุ่นเยาว์", "วิชาการ", "ลานกิจกรรม"),
        ),
        demand_share=0.5,
    ),
]


@dataclass
class PlanResult:
    requirement: str
    hours: float
    sessions_per_student: int
    seats_needed: int
    past_existing: int = 0
    past_created: int = 0
    past_seats: int = 0
    upcoming_existing: int = 0
    upcoming_created: int = 0


@dataclass
class Report:
    academic_year: int
    students: int
    past_window: Optional[tuple[date, date]] = None
    upcoming_window: Optional[tuple[date, date]] = None
    rows: list[PlanResult] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    @property
    def created(self) -> int:
        return sum(r.past_created + r.upcoming_created for r in self.rows)


def academic_year_bounds(academic_year: int) -> tuple[date, date]:
    """วันแรกและวันสุดท้ายของปีการศึกษา (1 มิ.ย. → 31 พ.ค. ปีถัดไป)."""
    ce_year = academic_year - 543
    return date(ce_year, 6, 1), date(ce_year + 1, 5, 31)


def spread_dates(start: date, end: date, count: int, lo: float = 0.0, hi: float = 1.0) -> list[date]:
    """วัน ``count`` วันกระจายเท่า ๆ กันในช่วง [start, end] (รวมปลาย) โดยเลี่ยงวันอาทิตย์

    ใช้ช่วงย่อย [lo, hi] ของหน้าต่าง — จุดกึ่งกลางของแต่ละช่องแทนการสุ่ม ผลจึงเหมือนเดิม
    ทุกครั้งที่รัน (เทสต์และรีวิวได้)
    """
    span = (end - start).days
    days = []
    for i in range(count):
        fraction = lo + (hi - lo) * (i + 0.5) / count
        day = start + timedelta(days=round(span * fraction))
        if day.weekday() == 6 and span > 0:
            day += timedelta(days=1) if day < end else timedelta(days=-1)
        days.append(day)
    return days


def _next_name(theme: str, academic_year: int, taken: set[str]) -> str:
    number = 1
    while (name := f"{theme} ครั้งที่ {number}/{academic_year}") in taken:
        number += 1
    return name


def _first_user(session: Session, role: UserRole) -> Optional[User]:
    return session.exec(select(User).where(User.role == role).order_by(User.id)).first()


def populate(session: Session, *, today: date, academic_year: Optional[int] = None) -> Report:
    """สร้างกิจกรรมที่ขาดลง session ที่ให้มา โดยยังไม่ commit (เทสต์เรียกด้วยฐานในหน่วยความจำ)."""
    academic_year = academic_year or academic_year_for(today)

    criteria_set = session.exec(
        select(CriteriaSet).where(CriteriaSet.code == CRITERIA_CODE)
    ).first()
    if criteria_set is None:
        raise SeedAborted(f"ยังไม่มีชุดเกณฑ์ {CRITERIA_CODE} ในฐาน — รัน python seed_criteria.py ก่อน")
    requirements = {
        r.name: r
        for r in session.exec(
            select(Requirement).where(Requirement.criteria_set_id == criteria_set.id)
        ).all()
    }
    missing = [plan.requirement for plan in PLANS if plan.requirement not in requirements]
    if missing:
        raise SeedAborted(
            f"ไม่พบรายการเกณฑ์ {', '.join(missing)} ในชุด {CRITERIA_CODE} — รัน python seed_criteria.py ก่อน"
        )

    # staff เป็นเจ้าของ (เห็นในรายการของตัวเองและเปิด QR เช็กอินได้) · admin เป็นผู้อนุมัติ
    # ตรงกับเส้นทางจริงของกิจกรรมที่ staff สร้างแล้วส่งให้ admin อนุมัติ
    approver = _first_user(session, UserRole.admin)
    if approver is None:
        raise SeedAborted("ไม่มีบัญชี admin ไว้เป็นผู้อนุมัติกิจกรรม")
    owner = _first_user(session, UserRole.staff) or approver

    students = session.exec(
        select(func.count())
        .select_from(Student)
        .where(Student.criteria_set_id == criteria_set.id)
        .where(Student.status == StudentStatus.active)
    ).one()
    report = Report(academic_year=academic_year, students=students)

    planned = {plan.requirement for plan in PLANS}
    for name in sorted(set(requirements) - planned):
        report.warnings.append(f"รายการเกณฑ์ «{name}» ไม่มีแผนกิจกรรม — ไม่ได้สร้างกิจกรรมให้")

    year_start, year_end = academic_year_bounds(academic_year)
    semester_2_end = date(year_start.year + 1, *SEMESTER_2_END)
    past_start, past_end = year_start, min(today - timedelta(days=1), semester_2_end)
    upcoming_start = max(today + timedelta(days=UPCOMING_LEAD_DAYS), year_start)
    upcoming_end = semester_2_end
    has_past = past_end >= past_start
    has_upcoming = upcoming_start <= upcoming_end
    if has_past:
        report.past_window = (past_start, past_end)
    else:
        report.warnings.append(
            f"ปีการศึกษา {academic_year} ยังไม่เริ่ม — ไม่ได้สร้างรอบที่จัดไปแล้ว "
            "(เฟส 5 จะไม่มีกิจกรรมให้สร้างการเข้าร่วมย้อนหลัง)"
        )
    if has_upcoming:
        report.upcoming_window = (upcoming_start, upcoming_end)
    else:
        report.warnings.append(
            f"ปีการศึกษา {academic_year} เลยปลายภาค 2 แล้ว — ไม่ได้สร้างรอบที่กำลังจะถึง"
        )

    today_start = datetime.combine(today, time.min)
    year_range = (
        datetime.combine(year_start, time.min),
        datetime.combine(year_end + timedelta(days=1), time.min),
    )
    taken_names = set(session.exec(select(Activity.name)).all())
    now = datetime.utcnow()

    for plan in PLANS:
        requirement = requirements[plan.requirement]
        if requirement.required_hours % plan.hours:
            report.warnings.append(
                f"«{plan.requirement}» ต้องการ {requirement.required_hours:g} ชม. แต่รอบละ "
                f"{plan.hours:g} ชม. หารไม่ลงตัว — เฟส 5 จะได้ชั่วโมงเกินเกณฑ์"
            )
        per_student = math.ceil(requirement.required_hours / plan.hours)
        seats_needed = math.ceil(students * per_student * plan.demand_share * HEADROOM)

        # นับเฉพาะกิจกรรมที่นิสิตใช้ได้จริง — ที่ยังรออนุมัติหรือถูกซ่อนสร้างการเข้าร่วมไม่ได้
        linked = session.exec(
            select(Activity)
            .join(ActivityRequirement, ActivityRequirement.activity_id == Activity.id)
            .where(ActivityRequirement.requirement_id == requirement.id)
            .where(Activity.approval_status == ApprovalStatus.approved)
            .where(Activity.is_hidden == False)  # noqa: E712
            .where(Activity.start_at >= year_range[0])
            .where(Activity.start_at < year_range[1])
        ).all()
        past = [a for a in linked if a.start_at < today_start]
        upcoming = [a for a in linked if a.start_at >= today_start]
        past_seats = sum(a.max_participants for a in past)

        new_past = 0
        if has_past:
            new_past = math.ceil(max(0, seats_needed - past_seats) / plan.capacity)
            # ยังไม่มีนิสิตก็ให้มีอย่างน้อยหนึ่งรอบ — หน้าประวัติ/แดชบอร์ดจะได้ไม่ว่าง
            if not past and new_past == 0:
                new_past = 1
        new_upcoming = max(0, plan.upcoming - len(upcoming)) if has_upcoming else 0

        days = spread_dates(past_start, past_end, new_past, *plan.window) + spread_dates(
            upcoming_start, upcoming_end, new_upcoming
        )
        for index, day in enumerate(days, start=len(linked)):
            theme = plan.themes[index % len(plan.themes)]
            name = _next_name(theme.name, academic_year, taken_names)
            taken_names.add(name)
            # กิจกรรมยาวเริ่มเช้า · กิจกรรม 3 ชม. เป็นช่วงบ่าย — เวลาไทยแบบไม่มีโซนเหมือน start_at อื่น
            start_at = datetime.combine(day, time(9) if plan.hours >= 4 else time(13))
            activity = Activity(
                name=name,
                activity_type=theme.activity_type,
                is_required=requirement.is_mandatory,
                max_participants=plan.capacity,
                start_at=start_at,
                location=theme.location,
                hours=plan.hours,
                created_by=owner.id,
                approval_status=ApprovalStatus.approved,
                approved_by=approver.id,
                approved_at=min(start_at - timedelta(days=7), now),
            )
            session.add(activity)
            session.flush()  # ต้องได้ activity.id ก่อนผูกรายการเกณฑ์
            session.add(ActivityRequirement(activity_id=activity.id, requirement_id=requirement.id))

        report.rows.append(
            PlanResult(
                requirement=plan.requirement,
                hours=plan.hours,
                sessions_per_student=per_student,
                seats_needed=seats_needed,
                past_existing=len(past),
                past_created=new_past,
                past_seats=past_seats + new_past * plan.capacity,
                upcoming_existing=len(upcoming),
                upcoming_created=new_upcoming,
            )
        )

    session.flush()
    return report


def _print_report(report: Report) -> None:
    print(
        f"ปีการศึกษา {report.academic_year} · นิสิตในชุด {CRITERIA_CODE} {report.students} คน "
        f"(เผื่อที่นั่ง {HEADROOM - 1:.0%})"
    )
    if report.past_window:
        print(f"รอบที่จัดไปแล้ว: {report.past_window[0]} → {report.past_window[1]}")
    if report.upcoming_window:
        print(f"รอบที่กำลังจะถึง: {report.upcoming_window[0]} → {report.upcoming_window[1]}")
    print()
    for row in report.rows:
        past_total = row.past_existing + row.past_created
        upcoming_total = row.upcoming_existing + row.upcoming_created
        print(
            f"  {row.requirement}\n"
            f"      รอบละ {row.hours:g} ชม. × {row.sessions_per_student} รอบ/คน · "
            f"จัดไปแล้ว {past_total} รอบ (ใหม่ {row.past_created}) ที่นั่ง {row.past_seats:,}"
            f"/{row.seats_needed:,} · กำลังจะถึง {upcoming_total} รอบ (ใหม่ {row.upcoming_created})"
        )
    print(f"\nสร้างกิจกรรมใหม่ {report.created} รายการ")
    for line in report.warnings:
        print(f"  ! {line}")


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="สร้างกิจกรรมจำลองของชุดเกณฑ์ 2567 (เฟส 4)")
    parser.add_argument("--dry-run", action="store_true", help="บอกว่าจะสร้างอะไร ไม่เขียนจริง")
    parser.add_argument(
        "--academic-year", type=int, help="ปีการศึกษา (พ.ศ.) — ไม่ใส่ = ปีการศึกษาของวันนี้"
    )
    args = parser.parse_args(argv)

    create_db_and_tables()
    with Session(engine) as session:
        try:
            report = populate(session, today=today_th(), academic_year=args.academic_year)
        except SeedAborted as exc:
            print(f"หยุด: {exc}")
            return 1
        if args.dry_run:
            session.rollback()
            print("dry-run — ไม่ได้เขียนอะไรลงฐาน\n")
        else:
            session.commit()

    _print_report(report)
    return 0


if __name__ == "__main__":
    sys.exit(main())
