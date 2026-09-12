"""เฟส 5 ของการรื้อ DB: สร้างการเข้าร่วมจำลองตามสถานะ ผ่าน/ไม่ผ่าน ในไฟล์นำเข้า

อ่าน ``student.imported_completion`` (เฟส 3) แล้วลงการเข้าร่วมในกิจกรรมรอบที่จัดไปแล้ว
ของชุดเกณฑ์นิสิต (เฟส 4):

- **ผ่าน**: ครบทุกรายการเกณฑ์ — บังคับครบทุกตัว · เลือกครบชั่วโมงทุกรายการ · สองด้านของ
  Social รวมกันครบ 16 ชม. → 60 ชม. พอดีสำหรับ 2567-regular
- **ไม่ผ่าน**: ครบทุกรายการ ยกเว้น 1–2 รายการที่สุ่มให้ขาด (บังคับหรือเลือกก็ได้) — ได้ชั่วโมง
  ไม่ถึงเกณฑ์ของรายการนั้นจริง ผลจึงตกเกณฑ์ตรงกับไฟล์

การเข้าร่วมทุกแถวเป็น ``approved`` ผ่าน ``app.approval.requirement_snapshot`` ตัวเดียวกับ
ที่เจ้าหน้าที่/OCR ใช้ตอนอนุมัติจริง: ชั่วโมงคัดจาก ``activity.hours`` + snapshot หน่วย/รายการเกณฑ์

**Social สองด้านต้องกระจายให้สมดุล** — เฟส 4 เตรียมที่นั่งแต่ละด้านไว้ราวครึ่งหนึ่งของที่ต้องใช้
นิสิตที่ผ่านจึงหมุนกันไปทีละคน: ด้านนวัตกรรมล้วน 16 · ด้านผู้ประกอบการล้วน 16 · ด้านละ 8

แต่ละคนไม่ลงสองกิจกรรมที่เวลาทับกัน (เฟส 4 วางหลายรายการไว้วันเวลาเดียวกันเป็นรอบคู่ขนาน)
เว้นแต่รอบที่เหลือบังคับ — นับไว้ในรายงานเป็น "เวลาชน"

**ทั้งหมดหรือไม่เลย**: วางแผนทุกคนในหน่วยความจำก่อน ถ้าที่นั่งไม่พอให้ใครสักคนครบตามสถานะ
จะหยุดโดยไม่เขียนอะไร · **รันซ้ำได้**: ข้ามนิสิตที่มีการเข้าร่วมในกิจกรรมเหล่านี้อยู่แล้ว
การสุ่มใช้ seed คงที่ ผลเหมือนเดิมทุกครั้งบนข้อมูลเดียวกัน

รัน:
    python seed_participations.py
    python seed_participations.py --dry-run
"""

from __future__ import annotations

import argparse
import random
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from datetime import date, datetime, time, timedelta
from typing import Optional

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

from sqlmodel import Session, func, select

from app.approval import requirement_snapshot
from app.database import create_db_and_tables, engine
from app.models import (
    Activity,
    ActivityRequirement,
    ApprovalStatus,
    CriteriaSet,
    EvidenceStatus,
    ImportedCompletion,
    Participation,
    Requirement,
    RequirementGroup,
    Student,
    StudentStatus,
)
from app.timeutil import today_th

DEFAULT_SEED = 2569


class SeedAborted(Exception):
    """ข้อมูลไม่พร้อม — ไม่ได้เขียนอะไรลงฐาน."""


@dataclass
class Slot:
    """กิจกรรมรอบที่จัดไปแล้วหนึ่งรอบ ในมุมของการจองที่นั่ง."""

    activity_id: int
    start_at: datetime
    hours: float
    remaining: int

    @property
    def end_at(self) -> datetime:
        # สคีมาไม่มีเวลาจบ — ประมาณจากชั่วโมงที่ให้ แบบเดียวกับ checkin_window
        return self.start_at + timedelta(hours=self.hours)


@dataclass(frozen=True)
class Unit:
    """สิ่งที่นิสิตต้องทำให้ครบหนึ่งอย่าง — รายการเกณฑ์เดียว หรือกลุ่มที่แชร์เป้าชั่วโมง."""

    label: str
    requirement_ids: tuple[int, ...]
    target_hours: float
    is_mandatory: bool

    @property
    def is_group(self) -> bool:
        return len(self.requirement_ids) > 1

    def patterns(self) -> list[dict[int, float]]:
        """วิธีแบ่งชั่วโมงระหว่างสมาชิกของกลุ่ม: ทำด้านเดียวครบ (ทีละด้าน) หรือเฉลี่ยทุกด้าน."""
        if not self.is_group:
            return [{self.requirement_ids[0]: self.target_hours}]
        singles = [{rid: self.target_hours} for rid in self.requirement_ids]
        share = self.target_hours / len(self.requirement_ids)
        return singles + [{rid: share for rid in self.requirement_ids}]


@dataclass
class CriteriaPlan:
    """ทุกอย่างที่ต้องรู้ของชุดเกณฑ์หนึ่ง ก่อนลงการเข้าร่วมให้นิสิตในชุดนั้น."""

    criteria_set: CriteriaSet
    units: list[Unit]
    pools: dict[int, list[Slot]]                       # requirement_id → รอบที่จัดไปแล้ว
    snapshots: dict[int, tuple[Optional[int], Optional[str]]]  # activity_id → snapshot
    requirement_names: dict[int, str]
    pattern_cursor: Counter = field(default_factory=Counter)


@dataclass
class Report:
    passed: int = 0
    failed: int = 0
    skipped_no_status: int = 0
    skipped_existing: int = 0
    skipped_no_activities: int = 0
    participations: int = 0
    clashes: int = 0
    hours_of_passed: Counter = field(default_factory=Counter)
    hours_of_failed: Counter = field(default_factory=Counter)
    short_units: Counter = field(default_factory=Counter)
    social_patterns: Counter = field(default_factory=Counter)
    seats: dict[str, tuple[int, int]] = field(default_factory=dict)  # รายการ → (ใช้, ทั้งหมด)
    warnings: list[str] = field(default_factory=list)


def _units_for(
    requirements: list[Requirement], groups: dict[int, RequirementGroup]
) -> list[Unit]:
    """รายการที่ต้องทำให้ครบ — รายการในกลุ่มแชร์เป้าชั่วโมง (requirement_group) รวมเป็นหน่วยเดียว."""
    grouped: dict[int, list[Requirement]] = defaultdict(list)
    units: list[Unit] = []
    for requirement in sorted(requirements, key=lambda r: r.id):
        if requirement.group_id in groups:
            grouped[requirement.group_id].append(requirement)
        else:
            units.append(
                Unit(
                    requirement.name,
                    (requirement.id,),
                    requirement.required_hours,
                    requirement.is_mandatory,
                )
            )
    for group_id, members in grouped.items():
        group = groups[group_id]
        units.append(
            Unit(
                group.name,
                tuple(m.id for m in members),
                group.required_hours,
                any(m.is_mandatory for m in members),
            )
        )
    # รายการที่ใช้หลายรอบต่อคนที่นั่งตึงกว่า — ลงก่อนตอนเวลายังว่างเยอะ จะได้ไม่ต้องยอมให้เวลาชน
    units.sort(key=lambda u: -u.target_hours)
    return units


def _build_plan(
    session: Session, criteria_set: CriteriaSet, today_start: datetime, report: Report
) -> Optional[CriteriaPlan]:
    requirements = session.exec(
        select(Requirement).where(Requirement.criteria_set_id == criteria_set.id)
    ).all()
    if not requirements:
        return None
    requirement_ids = {r.id for r in requirements}

    activities = session.exec(
        select(Activity)
        .join(ActivityRequirement, ActivityRequirement.activity_id == Activity.id)
        .where(ActivityRequirement.requirement_id.in_(requirement_ids))
        .where(Activity.approval_status == ApprovalStatus.approved)
        .where(Activity.is_hidden == False)  # noqa: E712
        .where(Activity.start_at < today_start)
        .distinct()
    ).all()
    if not activities:
        return None
    activity_ids = [a.id for a in activities]

    links: dict[int, list[Requirement]] = defaultdict(list)
    for link, requirement in session.exec(
        select(ActivityRequirement, Requirement)
        .join(Requirement, Requirement.id == ActivityRequirement.requirement_id)
        .where(ActivityRequirement.activity_id.in_(activity_ids))
    ).all():
        links[link.activity_id].append(requirement)

    taken = dict(
        session.exec(
            select(Participation.activity_id, func.count())
            .where(Participation.activity_id.in_(activity_ids))
            .group_by(Participation.activity_id)
        ).all()
    )

    pools: dict[int, list[Slot]] = defaultdict(list)
    ambiguous = 0
    for activity in activities:
        own = [r for r in links[activity.id] if r.id in requirement_ids]
        if len(own) != 1:
            # ผูกหลายรายการในชุดเดียวกัน = ยังไม่มีข้อตกลงว่าชั่วโมงนับเข้ารายการไหน (เฟส 6)
            ambiguous += 1
            continue
        pools[own[0].id].append(
            Slot(
                activity.id,
                activity.start_at,
                activity.hours,
                max(0, activity.max_participants - taken.get(activity.id, 0)),
            )
        )
    if ambiguous:
        report.warnings.append(
            f"[{criteria_set.code}] ข้ามกิจกรรม {ambiguous} รายการที่ผูกหลายรายการเกณฑ์ในชุดเดียวกัน"
        )

    groups = {
        g.id: g
        for g in session.exec(
            select(RequirementGroup).where(RequirementGroup.criteria_set_id == criteria_set.id)
        ).all()
    }
    return CriteriaPlan(
        criteria_set=criteria_set,
        units=_units_for(requirements, groups),
        pools=pools,
        snapshots={
            a.id: requirement_snapshot(links[a.id], criteria_set.id) for a in activities
        },
        requirement_names={r.id: r.name for r in requirements},
    )


class _StudentBooking:
    """การจองของนิสิตหนึ่งคน — กันลงกิจกรรมซ้ำ และกันสองกิจกรรมที่เวลาทับกัน."""

    def __init__(self, enrolled_from: Optional[datetime]):
        self.enrolled_from = enrolled_from
        self.booked: dict[int, Slot] = {}
        self.clashes = 0

    def _overlaps(self, slot: Slot) -> bool:
        return any(
            other.start_at < slot.end_at and slot.start_at < other.end_at
            for other in self.booked.values()
        )

    def pick(self, pool: list[Slot], hours: float) -> list[Slot]:
        """เลือกรอบจากรายการเกณฑ์หนึ่งให้ได้ ≥ hours — รอบที่ที่นั่งเหลือมากก่อน ให้เต็มพร้อม ๆ กัน

        รอบแรกเลือกเฉพาะที่ไม่ทับเวลาที่จองไว้ ถ้ายังไม่ครบค่อยยอมให้ทับ (นับเป็น clash)
        ดีกว่าให้นิสิตที่ "ผ่าน" ในไฟล์ออกมาไม่ผ่านเพราะตารางเวลาของข้อมูลจำลอง
        """
        candidates = sorted(pool, key=lambda s: (-s.remaining, s.start_at, s.activity_id))
        chosen: list[Slot] = []
        got = 0.0
        for allow_clash in (False, True):
            for slot in candidates:
                if got >= hours:
                    break
                if slot.remaining <= 0 or slot.activity_id in self.booked:
                    continue
                if self.enrolled_from and slot.start_at < self.enrolled_from:
                    continue
                if self._overlaps(slot):
                    if not allow_clash:
                        continue
                    self.clashes += 1
                chosen.append(slot)
                self.booked[slot.activity_id] = slot
                slot.remaining -= 1
                got += slot.hours
        return chosen

    def release(self, slot: Slot) -> None:
        slot.remaining += 1
        self.booked.pop(slot.activity_id, None)


def _enrolled_from(cohort: Optional[int]) -> Optional[datetime]:
    """วันเปิดปีการศึกษาแรกของรุ่น — ไม่มีใครเข้าร่วมกิจกรรมก่อนเข้าเรียน."""
    if cohort is None:
        return None
    return datetime.combine(date(cohort - 543, 6, 1), time.min)


def _plan_student(
    student: Student,
    plan: CriteriaPlan,
    rng: random.Random,
    report: Report,
) -> list[tuple[Slot, int]]:
    """รอบที่นิสิตคนนี้เข้าร่วม คู่กับรายการเกณฑ์ที่นับให้ — โยน SeedAborted ถ้าที่นั่งไม่พอ."""
    passed = student.imported_completion == ImportedCompletion.passed
    booking = _StudentBooking(_enrolled_from(student.cohort))
    short = set()
    if not passed:
        # รายการที่เป้าเป็น 0 ทำให้ขาดไม่ได้ — ต้องสุ่มจากรายการที่ขาดแล้วตกเกณฑ์จริงเท่านั้น
        candidates = [unit for unit in plan.units if unit.target_hours > 0]
        count = min(len(candidates), rng.choice((1, 2)))
        short = {unit.label for unit in rng.sample(candidates, count)}

    picked: list[tuple[Slot, int]] = []
    for unit in plan.units:
        patterns = unit.patterns()
        if unit.is_group and passed:
            # หมุนตามลำดับให้แต่ละแบบได้คนเท่า ๆ กัน — ที่นั่งแต่ละด้านมีแค่ราวครึ่ง
            index = plan.pattern_cursor[unit.label] % len(patterns)
            plan.pattern_cursor[unit.label] += 1
        else:
            index = rng.randrange(len(patterns))
        if unit.is_group and passed:
            report.social_patterns[_pattern_label(patterns[index], plan)] += 1

        unit_slots: list[tuple[Slot, int]] = []
        for requirement_id, hours in patterns[index].items():
            slots = booking.pick(plan.pools.get(requirement_id, []), hours)
            if sum(s.hours for s in slots) < hours:
                raise SeedAborted(
                    f"ที่นั่งรอบที่จัดไปแล้วของ «{plan.requirement_names[requirement_id]}» ไม่พอ "
                    f"(นิสิต {student.student_id} ต้องการ {hours:g} ชม.) — รัน "
                    "python seed_activities_2567.py เพื่อเพิ่มรอบ แล้วรันใหม่"
                )
            unit_slots.extend((slot, requirement_id) for slot in slots)

        if unit.label in short:
            # ตัดรอบทิ้งแบบสุ่มอย่างน้อยหนึ่งรอบ แล้วตัดต่อจนต่ำกว่าเป้าจริง (กันรอบที่ชั่วโมงเกิน)
            rng.shuffle(unit_slots)
            drop = rng.randint(1, len(unit_slots))
            while drop < len(unit_slots) and (
                sum(s.hours for s, _ in unit_slots[drop:]) >= unit.target_hours
            ):
                drop += 1
            for slot, _ in unit_slots[:drop]:
                booking.release(slot)
            unit_slots = unit_slots[drop:]
            report.short_units[unit.label] += 1
        picked.extend(unit_slots)

    report.clashes += booking.clashes
    return picked


def _pattern_label(pattern: dict[int, float], plan: CriteriaPlan) -> str:
    if len(pattern) == 1:
        (requirement_id,) = pattern
        return f"{plan.requirement_names[requirement_id]} ล้วน"
    return "แบ่งเท่ากันทุกด้าน"


def _verify(student: Student, plan: CriteriaPlan, earned: dict[int, float]) -> bool:
    """ครบเกณฑ์ไหม ตามกติกา min_per_requirement + กลุ่มแชร์เป้า — กันบั๊กของสคริปต์เอง."""
    for unit in plan.units:
        if sum(earned.get(rid, 0) for rid in unit.requirement_ids) < unit.target_hours:
            return False
    return True


def populate(session: Session, *, today: date, seed: int = DEFAULT_SEED) -> Report:
    """วางแผนแล้วใส่การเข้าร่วมลง session ที่ให้มา โดยยังไม่ commit."""
    report = Report()
    rng = random.Random(seed)
    today_start = datetime.combine(today, time.min)

    students = session.exec(
        select(Student)
        .where(Student.status == StudentStatus.active)
        .order_by(Student.id)
    ).all()
    report.skipped_no_status = sum(1 for s in students if s.imported_completion is None)
    students = [s for s in students if s.imported_completion is not None]
    if not students:
        raise SeedAborted("ไม่มีนิสิตที่มีสถานะ ผ่าน/ไม่ผ่าน จากไฟล์ — รัน python load_students.py ก่อน")

    plans: dict[int, Optional[CriteriaPlan]] = {}
    for criteria_set_id in sorted({s.criteria_set_id for s in students if s.criteria_set_id}):
        criteria_set = session.get(CriteriaSet, criteria_set_id)
        plans[criteria_set_id] = _build_plan(session, criteria_set, today_start, report)

    pool_activity_ids = {
        slot.activity_id
        for plan in plans.values()
        if plan
        for pool in plan.pools.values()
        for slot in pool
    }
    already = set(
        session.exec(
            select(Participation.student_id)
            .where(Participation.activity_id.in_(pool_activity_ids))
            .distinct()
        ).all()
    ) if pool_activity_ids else set()

    # ลำดับสุ่ม (แต่คงที่ตาม seed) — ที่นั่งตึงช่วงท้าย คนที่ถูกลงทีหลังจะไม่ใช่รหัสท้าย ๆ เสมอ
    rng.shuffle(students)
    no_plan_sets: Counter = Counter()
    rows: list[Participation] = []
    for student in students:
        plan = plans.get(student.criteria_set_id)
        if plan is None:
            report.skipped_no_activities += 1
            no_plan_sets[student.criteria_set_id] += 1
            continue
        if student.id in already:
            report.skipped_existing += 1
            continue

        picked = _plan_student(student, plan, rng, report)
        earned: dict[int, float] = defaultdict(float)
        for slot, requirement_id in picked:
            earned[requirement_id] += slot.hours
            unit_id, requirement_name = plan.snapshots[slot.activity_id]
            rows.append(
                Participation(
                    student_id=student.id,
                    activity_id=slot.activity_id,
                    # มาถึงก่อนเริ่มงานไม่กี่นาที — แบบเดียวกับ seed.py ที่ใช้ start_at เป็นเวลาเช็กอิน
                    check_in_time=slot.start_at - timedelta(minutes=rng.randint(0, 20)),
                    hours_earned=slot.hours,
                    evidence_status=EvidenceStatus.approved,
                    learning_unit_id=unit_id,
                    requirement_name=requirement_name,
                )
            )

        passed = student.imported_completion == ImportedCompletion.passed
        if _verify(student, plan, earned) != passed:
            raise SeedAborted(
                f"บั๊ก: ผลของนิสิต {student.student_id} ไม่ตรงสถานะ "
                f"{student.imported_completion.value} — ไม่ได้เขียนอะไรลงฐาน"
            )
        total = sum(earned.values())
        if passed:
            report.passed += 1
            report.hours_of_passed[total] += 1
        else:
            report.failed += 1
            report.hours_of_failed[total] += 1

    for criteria_set_id, count in no_plan_sets.items():
        code = session.get(CriteriaSet, criteria_set_id).code if criteria_set_id else "(ไม่มีชุดเกณฑ์)"
        report.warnings.append(
            f"ข้ามนิสิต {count} คนในชุด {code} — ไม่มีกิจกรรมรอบที่จัดไปแล้วให้ลง"
        )

    for plan in plans.values():
        if plan is None:
            continue
        for requirement_id, pool in plan.pools.items():
            # ที่นั่งทั้งหมดของกิจกรรมเอาจาก Activity ตรง ๆ ไม่ต้องย้อนคำนวณจาก remaining
            capacity = sum(
                session.get(Activity, slot.activity_id).max_participants for slot in pool
            )
            used = capacity - sum(slot.remaining for slot in pool)
            report.seats[plan.requirement_names[requirement_id]] = (used, capacity)

    session.add_all(rows)
    session.flush()
    report.participations = len(rows)
    return report


def _print_report(report: Report) -> None:
    print(
        f"นิสิต: ผ่าน {report.passed} · ไม่ผ่าน {report.failed} · ข้าม (ไม่มีสถานะ) "
        f"{report.skipped_no_status} · ข้าม (มีการเข้าร่วมอยู่แล้ว) {report.skipped_existing} · "
        f"ข้าม (ไม่มีกิจกรรม) {report.skipped_no_activities}"
    )
    print(f"การเข้าร่วมที่สร้าง: {report.participations:,} แถว · เวลาชน {report.clashes}")
    print(
        "ชั่วโมงรวมของคนที่ผ่าน: "
        + ", ".join(f"{h:g} ชม.={n}" for h, n in sorted(report.hours_of_passed.items()))
    )
    if report.hours_of_failed:
        print(
            "ชั่วโมงรวมของคนที่ไม่ผ่าน: "
            + ", ".join(f"{h:g} ชม.={n}" for h, n in sorted(report.hours_of_failed.items()))
        )
        print("รายการที่ถูกสุ่มให้ขาด: " + ", ".join(f"{k}={v}" for k, v in report.short_units.items()))
    if report.social_patterns:
        print(
            "Social ของคนที่ผ่าน: "
            + ", ".join(f"{k}={v}" for k, v in sorted(report.social_patterns.items()))
        )
    print("\nที่นั่งรอบที่จัดไปแล้ว (ใช้/ทั้งหมด):")
    for name, (used, capacity) in report.seats.items():
        print(f"  {used:>5,}/{capacity:<5,} {name}")
    for line in report.warnings:
        print(f"  ! {line}")


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="สร้างการเข้าร่วมจำลองตามสถานะในไฟล์ (เฟส 5)")
    parser.add_argument("--dry-run", action="store_true", help="วางแผนและนับอย่างเดียว ไม่เขียนจริง")
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED, help="seed ของการสุ่ม")
    args = parser.parse_args(argv)

    create_db_and_tables()
    with Session(engine) as session:
        try:
            report = populate(session, today=today_th(), seed=args.seed)
        except SeedAborted as exc:
            session.rollback()
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
