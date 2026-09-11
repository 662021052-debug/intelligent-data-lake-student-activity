"""เฟส 3: นำเข้านิสิตจริงจากไฟล์ Excel

คุม: ทุกแถวได้ทั้ง student + บัญชีที่ล็อกอินได้จริง · รุ่น/ชุดเกณฑ์/ชั้นปีถอดจากรหัสถูก ·
ไฟล์ผิดแม้แถวเดียวต้องไม่เขียนอะไรเลย · รันซ้ำไม่สร้างของซ้ำและไม่รีเซ็ตรหัสผ่าน
"""

from datetime import date

import openpyxl
import pytest
from sqlmodel import select

from app.auth import hash_password, verify_password
from app.models import (
    CriteriaSet,
    HourCategory,
    HourSubcategory,
    ImportedCompletion,
    ProgramType,
    Student,
    User,
    UserRole,
)
from load_students import (
    UNKNOWN_MAJOR,
    ImportAborted,
    current_academic_year,
    load,
    read_rows,
    year_level_for,
)
from seed_criteria import populate as seed_criteria

HEADER = ("รหัสนิสิต", "ชื่อ - สกุล", "คณะ", "สถานะ")
PASSWORD = "default-for-test"
ACADEMIC_YEAR = 2569


def _xlsx(tmp_path, rows, header=HEADER, name="students.xlsx"):
    workbook = openpyxl.Workbook()
    sheet = workbook.active
    sheet.append(header)
    for row in rows:
        sheet.append(row)
    path = tmp_path / name
    workbook.save(path)
    return path


def _criteria_id(session, code):
    return session.exec(select(CriteriaSet).where(CriteriaSet.code == code)).one().id


def _load(session, path, **kwargs):
    report = load(
        session,
        read_rows(path),
        password=kwargs.pop("password", PASSWORD),
        academic_year=kwargs.pop("academic_year", ACADEMIC_YEAR),
    )
    session.commit()
    return report


@pytest.fixture
def criteria(session):
    # ชุด legacy แปลงจากหมวดชั่วโมงเดิมในฐาน — ไม่มีหมวดเลยก็จะไม่มีชุด legacy ให้ผูก
    category = HourCategory(name="พัฒนาทักษะชีวิต", required_hours=12)
    session.add(category)
    session.commit()
    session.refresh(category)
    session.add(
        HourSubcategory(category_id=category.id, name="กิจกรรมเสริมสร้างคุณค่าแห่งตน", required_hours=12)
    )
    session.commit()
    seed_criteria(session)
    session.commit()


@pytest.fixture
def sample(tmp_path):
    return _xlsx(
        tmp_path,
        [
            ("6920510001", "นางสาวทดสอบ หนึ่ง", "คณะวิศวกรรมศาสตร์", "ผ่าน"),
            ("6820510002", "นายทดสอบ สอง", "คณะนิติศาสตร์", "ผ่าน"),
            ("6920510003", "นายทดสอบ สาม", "คณะศึกษาศาสตร์", "ไม่ผ่าน"),
        ],
    )


def test_every_row_becomes_a_student_with_derived_fields(session, criteria, sample):
    report = _load(session, sample)

    assert report.students_created == 3
    students = {s.student_id: s for s in session.exec(select(Student)).all()}
    assert set(students) == {"6920510001", "6820510002", "6920510003"}

    first = students["6920510001"]
    assert first.full_name == "นางสาวทดสอบ หนึ่ง"
    assert first.faculty == "คณะวิศวกรรมศาสตร์"
    assert first.cohort == 2569
    assert first.program_type == ProgramType.regular
    assert first.criteria_set_id == _criteria_id(session, "2567-regular")
    assert first.major == UNKNOWN_MAJOR
    assert first.year_level == 1
    assert students["6820510002"].year_level == 2


def test_status_column_is_kept_for_later_phases(session, criteria, sample):
    _load(session, sample)

    students = {s.student_id: s for s in session.exec(select(Student)).all()}
    assert students["6920510001"].imported_completion == ImportedCompletion.passed
    assert students["6920510003"].imported_completion == ImportedCompletion.failed


def test_old_cohorts_land_on_the_legacy_criteria_set(session, criteria, tmp_path):
    """ไฟล์จริงมีแต่ 68/69 แต่กฎต้องทั่วไป — รุ่น ≤ 2566 ต้องได้ชุดเกณฑ์เก่า."""
    path = _xlsx(
        tmp_path,
        [
            ("6620510001", "นายรุ่น หกหก", "คณะวิศวกรรมศาสตร์", "ผ่าน"),
            ("6720510001", "นายรุ่น หกเจ็ด", "คณะวิศวกรรมศาสตร์", "ผ่าน"),
        ],
    )
    _load(session, path)

    students = {s.student_id: s for s in session.exec(select(Student)).all()}
    assert students["6620510001"].criteria_set_id == _criteria_id(session, "legacy-2566")
    assert students["6720510001"].criteria_set_id == _criteria_id(session, "2567-regular")
    assert students["6620510001"].year_level == 4


def test_every_student_gets_a_linked_student_account(session, criteria, sample):
    _load(session, sample)

    for student in session.exec(select(Student)).all():
        user = session.exec(select(User).where(User.username == student.student_id)).one()
        assert user.role == UserRole.student
        assert user.student_id == student.id
        assert verify_password(PASSWORD, user.hashed_password)


def test_imported_student_can_log_in_with_the_default_password(client, session, criteria, sample):
    _load(session, sample)

    response = client.post(
        "/auth/login", data={"username": "6920510001", "password": PASSWORD}
    )
    assert response.status_code == 200, response.text


def test_import_does_not_expose_the_file_status_through_the_api(client, session, criteria, sample):
    """สถานะในไฟล์ไม่ใช่ผลที่ระบบคำนวณ — ถ้าหลุดออก API จะสับสนว่าอันไหนจริง."""
    _load(session, sample)

    response = client.get("/students", params={"search": "6920510001"})
    assert response.status_code == 200, response.text
    item = response.json()["items"][0]
    assert "imported_completion" not in item


def test_bad_rows_abort_the_whole_import(session, criteria, tmp_path):
    path = _xlsx(
        tmp_path,
        [
            ("6920510001", "นายดี หนึ่ง", "คณะวิศวกรรมศาสตร์", "ผ่าน"),
            ("69205X0002", "นายรหัส ผิด", "คณะวิศวกรรมศาสตร์", "ผ่าน"),
            ("6920510001", "นายรหัส ซ้ำ", "คณะวิศวกรรมศาสตร์", "ผ่าน"),
            ("6920510004", "นายสถานะ แปลก", "คณะวิศวกรรมศาสตร์", "รอตรวจ"),
        ],
    )
    with pytest.raises(ImportAborted) as excinfo:
        read_rows(path)

    message = str(excinfo.value)
    assert "3 แถว" in message
    assert "แถว 3" in message and "แถว 4" in message and "แถว 5" in message
    assert session.exec(select(Student)).all() == []


def test_missing_criteria_set_aborts_before_writing(session, sample):
    """ไม่มีชุดเกณฑ์ = นิสิตจะเข้าไปแบบไม่มีเกณฑ์ให้วัด ต้องหยุดแทนการเงียบ."""
    with pytest.raises(ImportAborted, match="seed_criteria"):
        load(session, read_rows(sample), password=PASSWORD, academic_year=ACADEMIC_YEAR)
    session.rollback()
    assert session.exec(select(Student)).all() == []


def test_username_owned_by_someone_else_aborts(session, criteria, sample):
    session.add(User(username="6920510001", hashed_password=hash_password("x"), role=UserRole.staff))
    session.commit()

    with pytest.raises(ImportAborted, match="6920510001"):
        load(session, read_rows(sample), password=PASSWORD, academic_year=ACADEMIC_YEAR)
    session.rollback()
    assert session.exec(select(Student)).all() == []


def test_rerun_is_idempotent_and_keeps_changed_passwords(session, criteria, sample):
    _load(session, sample)
    user = session.exec(select(User).where(User.username == "6920510001")).one()
    user.hashed_password = hash_password("changed-by-student")
    session.add(user)
    session.commit()

    report = _load(session, sample, password="another-default")

    assert report.students_created == 0
    assert report.users_created == 0
    assert report.users_existing == 3
    assert len(session.exec(select(Student)).all()) == 3
    # นับเฉพาะบัญชีที่ผูกนิสิต — conftest มีบัญชี "student" ลอย ๆ อยู่แล้วหนึ่งบัญชี
    assert len(session.exec(select(User).where(User.student_id.is_not(None))).all()) == 3
    session.refresh(user)
    assert verify_password("changed-by-student", user.hashed_password)


def test_rerun_updates_names_from_the_file_but_not_admin_choices(session, criteria, sample, tmp_path):
    _load(session, sample)
    student = session.exec(select(Student).where(Student.student_id == "6920510001")).one()
    legacy_id = _criteria_id(session, "legacy-2566")
    student.criteria_set_id = legacy_id  # ผู้ดูแลย้ายชุดเกณฑ์ให้เอง
    session.add(student)
    session.commit()

    renamed = _xlsx(
        tmp_path,
        [("6920510001", "นางสาวทดสอบ เปลี่ยนนามสกุล", "คณะวิศวกรรมศาสตร์", "ไม่ผ่าน")],
        name="renamed.xlsx",
    )
    report = _load(session, renamed)

    session.refresh(student)
    assert report.students_updated == 1
    assert student.full_name == "นางสาวทดสอบ เปลี่ยนนามสกุล"
    assert student.imported_completion == ImportedCompletion.failed
    assert student.criteria_set_id == legacy_id
    # นิสิตอีกสองคนไม่อยู่ในไฟล์รอบนี้ ต้องไม่ถูกลบ
    assert report.not_in_file == 2


def test_header_spacing_and_numeric_ids_are_tolerated(session, criteria, tmp_path):
    """Excel ชอบเก็บรหัสเป็นตัวเลข และหัวคอลัมน์มักพิมพ์เว้นวรรคไม่ตรงกัน."""
    path = _xlsx(
        tmp_path,
        [("  นายเว้น   วรรค  ", 6920510009, "คณะนิติศาสตร์", " ผ่าน ")],
        header=("ชื่อ-สกุล", "รหัสนิสิต", "คณะ", "สถานะ"),
    )
    _load(session, path)

    student = session.exec(select(Student)).one()
    assert student.student_id == "6920510009"
    assert student.full_name == "นายเว้น วรรค"


def test_missing_column_is_reported_by_name(tmp_path):
    path = _xlsx(tmp_path, [("6920510001", "นายไม่มี คณะ", "ผ่าน")], header=("รหัสนิสิต", "ชื่อ - สกุล", "สถานะ"))
    with pytest.raises(ImportAborted, match="คณะ"):
        read_rows(path)


@pytest.mark.parametrize(
    ("today", "expected"),
    [(date(2026, 9, 11), 2569), (date(2026, 6, 1), 2569), (date(2026, 5, 31), 2568)],
)
def test_academic_year_starts_in_june(today, expected):
    assert current_academic_year(today) == expected


def test_year_level_never_drops_below_one():
    assert year_level_for(2569, 2569) == 1
    assert year_level_for(2566, 2569) == 4
    # นำเข้ารุ่นใหม่ก่อนเปิดภาค (ปีการศึกษายังเป็นปีก่อน) ต้องไม่ได้ปี 0
    assert year_level_for(2569, 2568) == 1
