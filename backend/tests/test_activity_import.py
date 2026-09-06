"""นำเข้าแผนการจัดกิจกรรมทั้งภาคเรียนจาก Excel/CSV (ข้อ 6.7)

หัวใจของฟีเจอร์นี้คือ "แถวเดียวผิดต้องไม่ล้มทั้งไฟล์" เทสต์ส่วนใหญ่จึงยิงไฟล์ที่มี
ทั้งแถวดีและแถวเสียปนกัน แล้วยืนยันว่าแถวดีถูกสร้างจริงและแถวเสียถูกรายงานกลับ
พร้อมเลขแถวที่ตรงกับไฟล์
"""

import csv
import io
from datetime import datetime, timedelta

import pytest

from app.activity_import import (
    ImportFileError,
    build_template_xlsx,
    parse_spreadsheet,
    validate_rows,
)
from app.models import Activity, ApprovalStatus, HourCategory, HourSubcategory
from app.timeutil import today_th

HEADERS = ["ชื่อ", "ประเภท", "หมวดย่อย", "วันเวลา", "ชั่วโมง", "สถานที่", "จำนวนรับ", "บังคับ"]


def future_at(days: int = 30, hour: int = 9) -> str:
    day = datetime.now() + timedelta(days=days)
    return f"{day:%Y-%m-%d} {hour:02d}:00"


def csv_bytes(rows: list[list], headers: list[str] = HEADERS) -> bytes:
    buffer = io.StringIO()
    writer = csv.writer(buffer)
    writer.writerow(headers)
    writer.writerows(rows)
    return buffer.getvalue().encode("utf-8")


def xlsx_bytes(rows: list[list], headers: list[str] = HEADERS) -> bytes:
    openpyxl = pytest.importorskip("openpyxl")
    workbook = openpyxl.Workbook()
    sheet = workbook.active
    sheet.append(headers)
    for row in rows:
        sheet.append(row)
    buffer = io.BytesIO()
    workbook.save(buffer)
    return buffer.getvalue()


def good_row(name="อบรมการใช้ห้องสมุด", subcategory="กิจกรรมบูรณาการ 1", **overrides) -> list:
    row = [name, "อบรม", subcategory, future_at(), 3, "ห้องประชุม 1", 80, "ไม่ใช่"]
    for index, value in overrides.items():
        row[int(index)] = value
    return row


@pytest.fixture(name="hour_tree")
def hour_tree_fixture(session):
    """หมวดชั่วโมงชุดเล็ก ๆ ให้ไฟล์นำเข้าอ้างถึงได้ (มีชื่อหมวดย่อยซ้ำข้ามหมวดด้วย)"""
    first = HourCategory(name="พัฒนาทักษะชีวิต", required_hours=12)
    second = HourCategory(name="ใฝ่เรียนรู้ตลอดชีวิต", required_hours=20)
    session.add(first)
    session.add(second)
    session.commit()
    session.refresh(first)
    session.refresh(second)

    subs = [
        HourSubcategory(category_id=first.id, name="กิจกรรมบูรณาการ 1", required_hours=4),
        HourSubcategory(category_id=first.id, name="กิจกรรมซ้ำชื่อ", required_hours=4),
        HourSubcategory(category_id=second.id, name="กิจกรรมซ้ำชื่อ", required_hours=2),
    ]
    for sub in subs:
        session.add(sub)
    session.commit()
    for sub in subs:
        session.refresh(sub)
    return {"categories": [first, second], "subs": subs}


def upload(client, content: bytes, filename="plan.csv", token=None):
    headers = {"Authorization": f"Bearer {token}"} if token else None
    return client.post(
        "/activities/import",
        files={"file": (filename, content, "text/csv")},
        headers=headers,
    )


# ---------------------------- ทางที่ไปได้ดี ----------------------------
def test_import_csv_creates_activities(client, hour_tree):
    response = upload(client, csv_bytes([good_row(), good_row(name="ค่ายอาสาพัฒนาชุมชน")]))
    assert response.status_code == 200, response.text

    body = response.json()
    assert body["total_rows"] == 2
    assert body["created_count"] == 2
    assert body["error_count"] == 0
    # เลขแถวต้องเป็นเลขแถวจริงในไฟล์ (หัวตารางคือแถว 1)
    assert [item["row"] for item in body["created"]] == [2, 3]

    listed = client.get("/activities", params={"limit": 50}).json()
    assert {a["name"] for a in listed["items"]} == {"อบรมการใช้ห้องสมุด", "ค่ายอาสาพัฒนาชุมชน"}


def test_import_xlsx_works_too(client, hour_tree):
    response = upload(client, xlsx_bytes([good_row()]), filename="plan.xlsx")
    assert response.status_code == 200, response.text
    assert response.json()["created_count"] == 1


def test_staff_import_is_pending(client, session, tokens, hour_tree):
    """staff นำเข้า = ต้องรอ admin ตรวจ เหมือนตอน staff สร้างกิจกรรมทีละอัน"""
    response = upload(client, csv_bytes([good_row()]), token=tokens["staff"])
    assert response.status_code == 200, response.text

    activity = session.get(Activity, response.json()["created"][0]["id"])
    assert activity.approval_status == ApprovalStatus.pending
    assert activity.approved_by is None
    assert activity.approved_at is None


def test_admin_import_is_approved(client, session, tokens, hour_tree):
    """admin นำเข้า = อนุมัติเอง จึงอนุมัติให้ทันที (กฎเดียวกับ POST /activities)"""
    response = upload(client, csv_bytes([good_row()]), token=tokens["admin"])
    assert response.status_code == 200, response.text

    activity = session.get(Activity, response.json()["created"][0]["id"])
    assert activity.approval_status == ApprovalStatus.approved
    assert activity.approved_by is not None
    assert activity.approved_at is not None


def test_import_matches_the_status_of_creating_one_by_one(client, tokens, hour_tree):
    """สองทางที่กิจกรรมเกิดได้ต้องให้สถานะเดียวกันเสมอ ไม่งั้นกฎจะเพี้ยนจากกัน"""
    for role in ("staff", "admin"):
        headers = {"Authorization": f"Bearer {tokens[role]}"}
        single = client.post(
            "/activities",
            json={
                "name": f"สร้างทีละอันโดย {role}",
                "activity_type": "อบรม",
                "subcategory_id": hour_tree["subs"][0].id,
                "is_required": False,
                "max_participants": 50,
                "start_at": future_at(days=40).replace(" ", "T"),
                "location": "ห้อง SC101",
                "hours": 3,
            },
            headers=headers,
        )
        assert single.status_code == 201, single.text

        imported = upload(client, csv_bytes([good_row(name=f"นำเข้าโดย {role}")]), token=tokens[role])
        assert imported.status_code == 200, imported.text
        imported_activity = client.get(
            f"/activities/{imported.json()['created'][0]['id']}", headers=headers
        ).json()

        assert imported_activity["approval_status"] == single.json()["approval_status"], role


def test_imported_activity_keeps_every_field(client, session, hour_tree):
    row = good_row(name="กิจกรรมครบทุกช่อง")
    row[7] = "ใช่"
    response = upload(client, csv_bytes([row]))
    assert response.status_code == 200, response.text

    activity = session.get(Activity, response.json()["created"][0]["id"])
    assert activity.activity_type == "อบรม"
    assert activity.hours == 3
    assert activity.max_participants == 80
    assert activity.location == "ห้องประชุม 1"
    assert activity.is_required is True
    assert activity.subcategory_id == hour_tree["subs"][0].id
    assert activity.created_by is not None


def test_subcategory_can_be_given_as_full_path_or_id(client, hour_tree):
    duplicated = hour_tree["subs"][1]
    rows = [
        good_row(name="ระบุด้วยชื่อเต็ม", subcategory="พัฒนาทักษะชีวิต › กิจกรรมซ้ำชื่อ"),
        good_row(name="ระบุด้วย id", subcategory=str(duplicated.id)),
        good_row(name="ระบุด้วยเครื่องหมายมากกว่า", subcategory="ใฝ่เรียนรู้ตลอดชีวิต > กิจกรรมซ้ำชื่อ"),
    ]
    body = upload(client, csv_bytes(rows)).json()
    assert body["created_count"] == 3, body["errors"]


def test_extra_spaces_and_case_in_subcategory_are_tolerated(client, hour_tree):
    body = upload(client, csv_bytes([good_row(subcategory="  กิจกรรมบูรณาการ 1  ")])).json()
    assert body["created_count"] == 1, body["errors"]


def test_buddhist_year_is_converted(client, session, hour_tree):
    """ไฟล์ที่เจ้าหน้าที่ไทยพิมพ์เองมักเป็น พ.ศ. — ต้องไม่กลายเป็นกิจกรรมปี 2569"""
    day = datetime.now() + timedelta(days=20)
    body = upload(client, csv_bytes([good_row(**{"3": f"{day.year + 543}-{day.month:02d}-{day.day:02d} 13:00"})])).json()
    assert body["created_count"] == 1, body["errors"]

    activity = session.get(Activity, body["created"][0]["id"])
    assert activity.start_at.year == day.year


def test_missing_is_required_column_defaults_to_false(client, hour_tree):
    headers = HEADERS[:-1]
    row = good_row()[:-1]
    body = upload(client, csv_bytes([row], headers=headers)).json()
    assert body["created_count"] == 1, body["errors"]


def test_title_row_above_the_header_is_tolerated(client, hour_tree):
    """ไฟล์ที่คนทำเองมักมีบรรทัดชื่อเรื่องอยู่เหนือหัวตาราง"""
    buffer = io.StringIO()
    writer = csv.writer(buffer)
    writer.writerow(["แผนกิจกรรมภาคเรียนที่ 2"])
    writer.writerow(HEADERS)
    writer.writerow(good_row())
    body = upload(client, buffer.getvalue().encode("utf-8")).json()
    assert body["created_count"] == 1, body["errors"]
    assert body["created"][0]["row"] == 3


# ---------------------------- แถวที่ผิด ----------------------------
def test_bad_row_does_not_stop_the_good_ones(client, hour_tree):
    rows = [
        good_row(name="แถวดี 1"),
        good_row(name="แถวเสีย", **{"4": "-2"}),  # ชั่วโมงติดลบ
        good_row(name="แถวดี 2"),
    ]
    body = upload(client, csv_bytes(rows)).json()

    assert body["total_rows"] == 3
    assert body["created_count"] == 2
    assert body["error_count"] == 1
    assert body["errors"][0]["row"] == 3
    assert "ชั่วโมง" in body["errors"][0]["message"]
    assert {item["name"] for item in body["created"]} == {"แถวดี 1", "แถวดี 2"}


def test_backdated_row_is_rejected(client, hour_tree):
    past = (datetime.now() - timedelta(days=3)).strftime("%Y-%m-%d %H:%M")
    body = upload(client, csv_bytes([good_row(**{"3": past})])).json()
    assert body["created_count"] == 0
    assert "อดีต" in body["errors"][0]["message"]


def test_unknown_subcategory_is_rejected(client, hour_tree):
    body = upload(client, csv_bytes([good_row(subcategory="หมวดที่ไม่มีจริง")])).json()
    assert body["created_count"] == 0
    assert "ไม่พบหมวดย่อย" in body["errors"][0]["message"]


def test_ambiguous_subcategory_name_asks_for_the_full_path(client, hour_tree):
    body = upload(client, csv_bytes([good_row(subcategory="กิจกรรมซ้ำชื่อ")])).json()
    assert body["created_count"] == 0
    assert "มากกว่าหนึ่งหมวด" in body["errors"][0]["message"]


def test_row_with_several_problems_reports_all_of_them(client, hour_tree):
    row = ["", "อบรม", "หมวดที่ไม่มีจริง", "ไม่ใช่วันที่", 0, "", "abc", "อาจจะ"]
    body = upload(client, csv_bytes([row])).json()

    message = body["errors"][0]["message"]
    for expected in ["ชื่อกิจกรรม", "หมวดย่อย", "วันเวลา", "ชั่วโมง", "สถานที่", "จำนวนรับ", "บังคับ"]:
        assert expected in message, message


def test_duplicate_rows_inside_the_file_are_rejected(client, hour_tree):
    row = good_row()
    body = upload(client, csv_bytes([row, list(row)])).json()
    assert body["created_count"] == 1
    assert "ซ้ำ" in body["errors"][0]["message"]


def test_reuploading_the_same_file_does_not_duplicate_activities(client, hour_tree):
    content = csv_bytes([good_row()])
    assert upload(client, content).json()["created_count"] == 1

    second = upload(client, content).json()
    assert second["created_count"] == 0
    assert "ซ้ำ" in second["errors"][0]["message"]


def test_blank_rows_are_skipped_not_reported(client, hour_tree):
    body = upload(client, csv_bytes([good_row(), ["", "", "", "", "", "", "", ""]])).json()
    assert body["total_rows"] == 1
    assert body["error_count"] == 0


# ---------------------------- ไฟล์ที่ใช้ไม่ได้ทั้งไฟล์ ----------------------------
def test_unsupported_extension(client, hour_tree):
    response = upload(client, b"whatever", filename="plan.txt")
    assert response.status_code == 400
    assert ".xlsx" in response.json()["detail"]


def test_empty_file(client, hour_tree):
    response = upload(client, b"")
    assert response.status_code == 400


def test_file_without_the_required_headers(client, hour_tree):
    response = upload(client, csv_bytes([["a", "b"]], headers=["ชื่อ", "ประเภท"]))
    assert response.status_code == 400
    assert "หัวตาราง" in response.json()["detail"]


def test_header_present_but_a_column_is_missing(client, hour_tree):
    headers = ["ชื่อ", "ประเภท", "หมวดย่อย", "วันเวลา", "ชั่วโมง"]
    response = upload(client, csv_bytes([["a", "b", "c", future_at(), 2]], headers=headers))
    assert response.status_code == 400
    assert "สถานที่" in response.json()["detail"]


def test_file_with_headers_but_no_data(client, hour_tree):
    response = upload(client, csv_bytes([]))
    assert response.status_code == 400
    assert "ไม่มีข้อมูล" in response.json()["detail"]


# ---------------------------- สิทธิ์ ----------------------------
def test_student_cannot_import(client, tokens, hour_tree):
    response = upload(client, csv_bytes([good_row()]), token=tokens["student"])
    assert response.status_code == 403


def test_student_cannot_download_the_template(client, tokens):
    response = client.get(
        "/activities/import/template.xlsx",
        headers={"Authorization": f"Bearer {tokens['student']}"},
    )
    assert response.status_code == 403


# ---------------------------- ไฟล์ต้นแบบ ----------------------------
def test_template_download(client, hour_tree):
    response = client.get("/activities/import/template.xlsx")
    assert response.status_code == 200
    assert response.headers["content-type"].startswith(
        "application/vnd.openxmlformats-officedocument.spreadsheetml"
    )
    assert "filename*=UTF-8''" in response.headers["content-disposition"]
    assert response.content[:2] == b"PK"  # xlsx = zip


def test_template_lists_the_real_subcategories():
    openpyxl = pytest.importorskip("openpyxl")
    content = build_template_xlsx(["หมวด ก › ย่อย 1", "หมวด ข › ย่อย 2"])
    workbook = openpyxl.load_workbook(io.BytesIO(content))

    assert workbook.active.cell(row=1, column=1).value == "ชื่อ"
    listed = [row[0] for row in workbook["หมวดย่อยที่ใช้ได้"].iter_rows(values_only=True)]
    assert "หมวด ก › ย่อย 1" in listed


def test_template_round_trips_through_the_importer(client, hour_tree):
    """ไฟล์ต้นแบบต้องนำเข้ากลับได้จริง — แถวตัวอย่างในนั้นต้องผ่านทุกกฎ"""
    template = client.get("/activities/import/template.xlsx")
    body = upload(client, template.content, filename="template.xlsx").json()
    assert body["created_count"] == 1, body["errors"]


# ---------------------------- ชั้น parse/validate ล้วน ----------------------------
def test_parse_spreadsheet_rejects_unknown_extension():
    with pytest.raises(ImportFileError):
        parse_spreadsheet("plan.pdf", b"x")


def test_validate_rows_is_pure_and_reports_row_numbers():
    rows = parse_spreadsheet("plan.csv", csv_bytes([good_row(), good_row(name="", )]))
    outcome = validate_rows(
        rows,
        subcategory_index={"กิจกรรมบูรณาการ1": [7]},
        today=today_th(),
    )
    assert [d.row_number for d in outcome.drafts] == [2]
    assert outcome.drafts[0].subcategory_id == 7
    assert [i.row_number for i in outcome.issues] == [3]


def test_cp874_csv_is_decoded(client, hour_tree):
    """Excel ไทยบน Windows บันทึก CSV เป็น cp874 ไม่ใช่ UTF-8"""
    content = csv_bytes([good_row(name="กิจกรรมภาษาไทย")]).decode("utf-8").encode("cp874")
    body = upload(client, content).json()
    assert body["created_count"] == 1, body["errors"]
    assert body["created"][0]["name"] == "กิจกรรมภาษาไทย"
