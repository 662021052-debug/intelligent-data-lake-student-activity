"""เฟส 3: โหลดรายชื่อนิสิตจากไฟล์ Excel

สิ่งที่ต้องคุม: ทุกแถวที่ถูกต้องกลายเป็นนิสิต + บัญชีที่ล็อกอินได้ · รุ่น/ชุดเกณฑ์ถอดจากรหัส
ตามกฎ ≥2567 / ≤2566 · สถานะในไฟล์ถูกเก็บไว้ · แถวเสียไม่ขวางแถวดี · และรันซ้ำไม่เกิด
ของซ้ำหรือรีเซ็ตรหัสผ่านที่นิสิตเปลี่ยนไปแล้ว
"""

from datetime import date

import pytest
from openpyxl import Workbook
from sqlmodel import select

from app.auth import hash_password, verify_password
from app.criteria import LEGACY_CRITERIA_CODE, academic_year_of, year_level_for
from app.models import CountingRule, CriteriaSet, ProgramType, Student, User, UserRole
from load_students import (
    UNKNOWN_MAJOR,
    RosterError,
    RosterRow,
    load,
    parse_rows,
    read_roster,
)

HEADER = ("รหัสนิสิต", "ชื่อ - สกุล", "คณะ", "สถานะ")
# ปีการศึกษา 2569 (ก.ย. 2026) — รุ่น 69 เป็นปี 1, รุ่น 68 เป็นปี 2
TODAY = date(2026, 9, 11)


@pytest.fixture(name="password_hash", scope="module")
def password_hash_fixture():
    # bcrypt ช้า — hash ครั้งเดียวใช้ทั้งไฟล์ เหมือนที่ loader ทำจริง
    return hash_password("student123")


@pytest.fixture(name="criteria_sets")
def criteria_sets_fixture(session):
    sets = {}
    for code, year, rule in (
        ("2567-regular", 2567, CountingRule.min_per_requirement),
        (LEGACY_CRITERIA_CODE, 2566, CountingRule.total_per_unit),
    ):
        criteria_set = CriteriaSet(
            code=code,
            academic_year=year,
            program_type=ProgramType.regular,
            name=code,
            total_required_hours=60,
            counting_rule=rule,
        )
        session.add(criteria_set)
        sets[code] = criteria_set
    session.commit()
    return {code: cs.id for code, cs in sets.items()}


def _row(student_id, name="นางสาวทดสอบ ระบบ", faculty="คณะวิศวกรรมศาสตร์", passed=True, n=2):
    return RosterRow(n, student_id, name, faculty, passed)


def _students(session):
    return {s.student_id: s for s in session.exec(select(Student)).all()}


def _linked_student_users(session):
    # conftest มีบัญชี role=student ชื่อ "student" ที่ไม่ผูกนิสิตอยู่แล้ว — ไม่นับตัวนั้น
    return session.exec(
        select(User).where(User.role == UserRole.student, User.student_id.is_not(None))
    ).all()


# ---------- ชั้นปีจากรุ่น ----------


def test_academic_year_starts_in_june():
    assert academic_year_of(date(2026, 6, 1)) == 2569
    assert academic_year_of(date(2026, 9, 11)) == 2569
    # ม.ค.–พ.ค. ยังเป็นปีการศึกษาที่เริ่มเมื่อ มิ.ย. ปีก่อน
    assert academic_year_of(date(2027, 5, 31)) == 2569


def test_year_level_counts_from_cohort_and_never_drops_below_one():
    assert year_level_for(2569, 2569) == 1
    assert year_level_for(2568, 2569) == 2
    assert year_level_for(2562, 2569) == 8  # เรียนเกิน 4 ปีมีจริง ไม่ตัดด้านบน
    assert year_level_for(2570, 2569) == 1  # รุ่นล่วงหน้าไม่กลายเป็นปี 0
    assert year_level_for(None, 2569) is None


# ---------- อ่านไฟล์ ----------


def test_parse_matches_real_header_and_normalizes_cells():
    rows, problems = parse_rows(
        [
            HEADER,
            ("6920000001", " นายหนึ่ง ทดสอบ ", "คณะนิติศาสตร์", "ผ่าน"),
            # Excel เก็บรหัสเป็นตัวเลขได้ — ต้องไม่กลายเป็น "6820000002.0"
            (6820000002.0, "นางสาวสอง ทดสอบ", "คณะศึกษาศาสตร์", "ไม่ผ่าน"),
            (None, None, None, None),  # แถวว่างท้ายชีต
        ]
    )
    assert problems == []
    assert [(r.student_id, r.full_name, r.passed) for r in rows] == [
        ("6920000001", "นายหนึ่ง ทดสอบ", True),
        ("6820000002", "นางสาวสอง ทดสอบ", False),
    ]
    assert rows[0].row_number == 2


def test_parse_skips_bad_rows_without_blocking_good_ones():
    rows, problems = parse_rows(
        [
            HEADER,
            ("692000001", "เก้าหลัก", "คณะ", "ผ่าน"),
            ("69200000AB", "มีตัวอักษร", "คณะ", "ผ่าน"),
            ("6920000003", "", "คณะ", "ผ่าน"),
            ("6920000004", "คนดี", "คณะ", "ผ่าน"),
            ("6920000004", "ซ้ำ", "คณะ", "ผ่าน"),
            ("6920000005", "สถานะแปลก", "คณะ", "รอตรวจ"),
        ]
    )
    assert [r.student_id for r in rows] == ["6920000004", "6920000005"]
    # สถานะที่ไม่รู้จักยังโหลดคนนั้นเข้ามา แค่ไม่มีสถานะ
    assert rows[1].passed is None
    assert len(problems) == 5
    assert any("แถว 2" in p and "10 หลัก" in p for p in problems)
    assert any("ซ้ำกับแถว 5" in p for p in problems)


def test_parse_rejects_file_with_wrong_header():
    with pytest.raises(RosterError, match="สถานะ"):
        parse_rows([("รหัสนิสิต", "ชื่อ-สกุล", "คณะ"), ("6920000001", "ก", "ข")])
    with pytest.raises(RosterError):
        parse_rows([])


def test_read_roster_reads_an_actual_xlsx(tmp_path):
    workbook = Workbook()
    sheet = workbook.active
    sheet.append(HEADER)
    sheet.append(["6920000001", "นายหนึ่ง ทดสอบ", "คณะนิติศาสตร์", "ผ่าน"])
    path = tmp_path / "roster.xlsx"
    workbook.save(path)

    rows, problems = read_roster(path)
    assert problems == []
    assert rows == [RosterRow(2, "6920000001", "นายหนึ่ง ทดสอบ", "คณะนิติศาสตร์", True)]

    with pytest.raises(RosterError, match="ไม่พบไฟล์"):
        read_roster(tmp_path / "missing.xlsx")


# ---------- เขียนลงฐาน ----------


def test_load_creates_students_with_criteria_set_by_cohort(session, criteria_sets, password_hash):
    report = load(
        session,
        [
            _row("6920000001", passed=True),
            _row("6820000002", passed=False),
            # กฎต้องทั่วไป ไม่ใช่เฉพาะรุ่นในไฟล์นี้: เข้า ≤2566 → legacy
            _row("6620000003", passed=None),
        ],
        hashed_password=password_hash,
        today=TODAY,
    )
    session.commit()

    students = _students(session)
    first, second, legacy = students["6920000001"], students["6820000002"], students["6620000003"]

    assert (first.cohort, first.year_level) == (2569, 1)
    assert (second.cohort, second.year_level) == (2568, 2)
    assert (legacy.cohort, legacy.year_level) == (2566, 4)
    assert first.criteria_set_id == criteria_sets["2567-regular"]
    assert second.criteria_set_id == criteria_sets["2567-regular"]
    assert legacy.criteria_set_id == criteria_sets[LEGACY_CRITERIA_CODE]

    assert all(s.program_type == ProgramType.regular for s in students.values())
    assert all(s.major == UNKNOWN_MAJOR for s in students.values())
    assert (first.source_passed, second.source_passed, legacy.source_passed) == (True, False, None)
    assert first.full_name == "นางสาวทดสอบ ระบบ" and first.faculty == "คณะวิศวกรรมศาสตร์"

    assert report.students_created == 3
    assert report.by_criteria_set == {"2567-regular": 2, LEGACY_CRITERIA_CODE: 1}
    assert report.by_status == {"ผ่าน": 1, "ไม่ผ่าน": 1, "ไม่ทราบ": 1}


def test_every_student_gets_a_linked_login(session, criteria_sets, password_hash):
    load(
        session,
        [_row("6920000001"), _row("6920000002")],
        hashed_password=password_hash,
        today=TODAY,
    )
    session.commit()

    students = _students(session)
    for student_id, student in students.items():
        user = session.exec(select(User).where(User.username == student_id)).one()
        assert user.role == UserRole.student
        assert user.student_id == student.id
        assert verify_password("student123", user.hashed_password)


def test_login_works_through_the_api(client, session, criteria_sets, password_hash):
    load(session, [_row("6920000001")], hashed_password=password_hash, today=TODAY)
    session.commit()

    response = client.post(
        "/auth/login", data={"username": "6920000001", "password": "student123"}
    )
    assert response.status_code == 200, response.text


def test_rerun_is_idempotent_and_keeps_changed_passwords(session, criteria_sets, password_hash):
    rows = [_row("6920000001"), _row("6920000002")]
    load(session, rows, hashed_password=password_hash, today=TODAY)
    session.commit()

    # นิสิตเปลี่ยนรหัสผ่านเองแล้ว — การนำเข้ารอบใหม่ต้องไม่รีเซ็ตกลับ
    user = session.exec(select(User).where(User.username == "6920000001")).one()
    user.hashed_password = hash_password("changed-by-student")
    session.add(user)
    session.commit()

    report = load(session, rows, hashed_password=password_hash, today=TODAY)
    session.commit()

    assert report.students_created == 0
    assert report.students_unchanged == 2
    assert report.users_created == 0
    assert len(_students(session)) == 2
    assert len(_linked_student_users(session)) == 2
    user = session.exec(select(User).where(User.username == "6920000001")).one()
    assert verify_password("changed-by-student", user.hashed_password)


def test_rerun_takes_file_fields_but_keeps_manual_criteria_set(
    session, criteria_sets, password_hash
):
    load(session, [_row("6920000001")], hashed_password=password_hash, today=TODAY)
    session.commit()

    # ผู้ดูแลย้ายนิสิตไปชุดเกณฑ์อื่นด้วยมือ
    student = _students(session)["6920000001"]
    student.criteria_set_id = criteria_sets[LEGACY_CRITERIA_CODE]
    session.add(student)
    session.commit()

    report = load(
        session,
        [_row("6920000001", name="นางสาวทดสอบ เปลี่ยนนามสกุล", passed=False)],
        hashed_password=password_hash,
        today=TODAY,
    )
    session.commit()

    student = _students(session)["6920000001"]
    assert report.students_updated == 1
    assert student.full_name == "นางสาวทดสอบ เปลี่ยนนามสกุล"
    assert student.source_passed is False
    assert student.criteria_set_id == criteria_sets[LEGACY_CRITERIA_CODE]


def test_username_clash_skips_the_account_but_still_loads_the_student(
    session, criteria_sets, password_hash
):
    session.add(User(username="6920000001", hashed_password="x", role=UserRole.staff))
    session.commit()

    report = load(session, [_row("6920000001")], hashed_password=password_hash, today=TODAY)
    session.commit()

    assert "6920000001" in _students(session)
    assert report.users_created == 0
    assert any("6920000001" in w and "staff" in w for w in report.warnings)
    staff = session.exec(select(User).where(User.username == "6920000001")).one()
    assert staff.role == UserRole.staff and staff.student_id is None


def test_missing_criteria_set_stops_before_writing_anything(session, password_hash):
    with pytest.raises(RosterError, match="seed_criteria.py"):
        load(session, [_row("6920000001")], hashed_password=password_hash, today=TODAY)
    session.rollback()

    assert _students(session) == {}
    assert _linked_student_users(session) == []
