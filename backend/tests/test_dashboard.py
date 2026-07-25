"""Phase 11 — Executive Dashboard API tests.

A small deterministic dataset (total requirement = 10 hours) lets us assert
exact KPI numbers, and every endpoint is checked for admin-only access.
"""

from datetime import datetime

from sqlmodel import select

from app.gold import create_gold_layer
from app.models import (
    Activity,
    ApprovalStatus,
    EvidenceStatus,
    HourCategory,
    HourSubcategory,
    Participation,
    Student,
    StudentStatus,
    User,
)

AUG = datetime(2026, 8, 1, 9, 0, 0)   # month 8 -> semester 1
DEC = datetime(2026, 12, 1, 9, 0, 0)  # month 12 -> semester 2


def _admin_headers(tokens):
    return {"Authorization": f"Bearer {tokens['admin']}"}


def _staff_id(session):
    return session.exec(select(User).where(User.username == "staff")).first().id


def _student(session, code, name, faculty, year):
    s = Student(
        student_id=code,
        full_name=name,
        faculty=faculty,
        major="สาขาทดสอบ",
        year_level=year,
        status=StudentStatus.active,
    )
    session.add(s)
    session.commit()
    session.refresh(s)
    return s


def _activity(session, sub_id, owner, start_at=AUG, max_participants=100, hours=10, name="กิจกรรม"):
    a = Activity(
        name=name,
        activity_type="วิชาการ",
        is_required=False,
        max_participants=max_participants,
        start_at=start_at,
        location="ห้อง",
        hours=hours,
        subcategory_id=sub_id,
        created_by=owner,
        approval_status=ApprovalStatus.approved,
        approved_by=owner,
        approved_at=datetime.utcnow(),
    )
    session.add(a)
    session.commit()
    session.refresh(a)
    return a


def _join(session, student_id, activity_id, hours, status=EvidenceStatus.approved):
    session.add(
        Participation(
            student_id=student_id,
            activity_id=activity_id,
            evidence_status=status,
            hours_earned=hours,
        )
    )
    session.commit()


def _build_scenario(session):
    """Requirement total = 10 hours. Returns nothing; sets up a fixed world."""
    cat = HourCategory(name="หมวดเดียว", required_hours=10)
    session.add(cat)
    session.commit()
    session.refresh(cat)
    sub = HourSubcategory(category_id=cat.id, name="ย่อยเดียว", required_hours=10)
    session.add(sub)
    session.commit()
    session.refresh(sub)

    staff = _staff_id(session)
    act1 = _activity(session, sub.id, staff, start_at=AUG, max_participants=100, name="Aug")
    act2 = _activity(session, sub.id, staff, start_at=DEC, max_participants=10, name="Dec")

    a = _student(session, "70001", "เอ", "วิศวกรรมศาสตร์", 2)
    b = _student(session, "70002", "บี", "วิศวกรรมศาสตร์", 2)
    c = _student(session, "70003", "ซี", "วิทยาศาสตร์", 1)

    _join(session, a.id, act1.id, 10)  # A: 10h approved -> passed
    _join(session, b.id, act1.id, 4)   # B: 4h approved  -> 40% at risk
    _join(session, c.id, act2.id, 0)   # C: 0h (participant of act2) -> 0% at risk
    _join(session, a.id, act1.id, 5, status=EvidenceStatus.pending)  # ignored (not approved)

    create_gold_layer(session)
    return {"cat": cat, "act1": act1, "act2": act2, "a": a, "b": b, "c": c}


# --------------------------- access control ---------------------------
DASHBOARD_ENDPOINTS = [
    "/dashboard/overview",
    "/dashboard/by-category",
    "/dashboard/at-risk",
    "/dashboard/low-participation",
    "/dashboard/by-faculty",
    "/dashboard/trend",
]


def test_dashboard_requires_admin(client, session, tokens):
    create_gold_layer(session)  # views must exist for the admin 200 checks
    student_headers = {"Authorization": f"Bearer {tokens['student']}"}
    for ep in DASHBOARD_ENDPOINTS:
        assert client.get(ep).status_code == 403, ep  # default client = staff
        assert client.get(ep, headers=student_headers).status_code == 403, ep
        assert client.get(ep, headers=_admin_headers(tokens)).status_code == 200, ep


# --------------------------- overview ---------------------------
def test_overview_numbers(client, session, tokens):
    _build_scenario(session)
    body = client.get("/dashboard/overview", headers=_admin_headers(tokens)).json()

    assert body["required_hours_total"] == 10
    assert body["total_students"] == 3
    assert body["passed_count"] == 1                 # only A reaches 10
    assert body["passed_percent"] == round(1 / 3 * 100, 2)
    assert body["avg_hours"] == round((10 + 4 + 0) / 3, 2)
    assert body["activity_count"] == 2               # two approved activities


def test_overview_semester_filter(client, session, tokens):
    _build_scenario(session)
    h = _admin_headers(tokens)

    sem1 = client.get("/dashboard/overview?semester=1", headers=h).json()
    assert sem1["activity_count"] == 1               # only the August activity
    assert sem1["passed_count"] == 1                 # A's 10h are in semester 1

    sem2 = client.get("/dashboard/overview?semester=2", headers=h).json()
    assert sem2["activity_count"] == 1               # only the December activity
    assert sem2["passed_count"] == 0                 # no one earned hours in sem 2


def test_overview_faculty_filter(client, session, tokens):
    _build_scenario(session)
    body = client.get(
        "/dashboard/overview?faculty=วิศวกรรมศาสตร์", headers=_admin_headers(tokens)
    ).json()
    assert body["total_students"] == 2               # A and B only
    assert body["passed_count"] == 1


# --------------------------- by-category ---------------------------
def test_by_category(client, session, tokens):
    _build_scenario(session)
    body = client.get("/dashboard/by-category", headers=_admin_headers(tokens)).json()
    assert len(body) == 1
    row = body[0]
    assert row["required_hours"] == 10
    # total approved hours in the category = 10 + 4 + 0 = 14, over 3 students
    assert row["avg_earned_hours"] == round(14 / 3, 2)


# --------------------------- at-risk ---------------------------
def test_at_risk_default_threshold(client, session, tokens):
    _build_scenario(session)
    body = client.get("/dashboard/at-risk", headers=_admin_headers(tokens)).json()
    # A (100%) excluded; B (40%) and C (0%) are at risk, most-at-risk first
    codes = [s["student_code"] for s in body]
    assert codes == ["70003", "70002"]
    assert body[0]["earned_hours"] == 0
    assert body[0]["missing_hours"] == 10
    assert body[1]["percent"] == 40


def test_at_risk_custom_threshold(client, session, tokens):
    _build_scenario(session)
    # threshold 100 -> everyone below 100% counts (A excluded only if == 100)
    body = client.get("/dashboard/at-risk?threshold=100", headers=_admin_headers(tokens)).json()
    codes = {s["student_code"] for s in body}
    assert codes == {"70002", "70003"}  # A is exactly 100%, not < 100


# --------------------------- low-participation ---------------------------
def test_low_participation(client, session, tokens):
    _build_scenario(session)
    body = client.get("/dashboard/low-participation", headers=_admin_headers(tokens)).json()
    assert len(body) == 2
    # act1: 2 participants / 100 = 2%; act2: 1 / 10 = 10% -> act1 first
    assert body[0]["name"] == "Aug"
    assert body[0]["participant_count"] == 2
    assert body[0]["fill_percent"] == 2
    assert body[1]["name"] == "Dec"
    assert body[1]["fill_percent"] == 10


# --------------------------- by-faculty ---------------------------
def test_by_faculty(client, session, tokens):
    _build_scenario(session)
    body = client.get("/dashboard/by-faculty", headers=_admin_headers(tokens)).json()
    by_key = {(r["faculty"], r["year_level"]): r for r in body}

    eng = by_key[("วิศวกรรมศาสตร์", 2)]
    assert eng["total_students"] == 2
    assert eng["passed_count"] == 1
    assert eng["passed_percent"] == 50

    sci = by_key[("วิทยาศาสตร์", 1)]
    assert sci["total_students"] == 1
    assert sci["passed_count"] == 0


# --------------------------- trend ---------------------------
def test_trend(client, session, tokens):
    _build_scenario(session)
    body = client.get("/dashboard/trend", headers=_admin_headers(tokens)).json()
    periods = {p["period"]: p["count"] for p in body}
    assert periods == {"2026-08": 2, "2026-12": 1}
    # ordered chronologically
    assert [p["period"] for p in body] == ["2026-08", "2026-12"]


# --------------------------- div-by-zero guard (#1) ---------------------------
def _category_with_sub(session, cat_required=10, sub_required=10):
    cat = HourCategory(name="หมวด", required_hours=cat_required)
    session.add(cat)
    session.commit()
    session.refresh(cat)
    sub = HourSubcategory(category_id=cat.id, name="ย่อย", required_hours=sub_required)
    session.add(sub)
    session.commit()
    session.refresh(sub)
    return cat, sub


def test_low_participation_survives_zero_capacity(client, session, tokens):
    """A 0-capacity activity must not divide-by-zero (NULLIF guard) — this would
    500 on Postgres without the guard."""
    _, sub = _category_with_sub(session)
    _activity(session, sub.id, _staff_id(session), max_participants=0, name="ZeroCap")
    create_gold_layer(session)

    resp = client.get("/dashboard/low-participation", headers=_admin_headers(tokens))
    assert resp.status_code == 200
    row = next(r for r in resp.json() if r["name"] == "ZeroCap")
    assert row["fill_percent"] == 0


def test_create_activity_rejects_zero_capacity(client, session, tokens):
    """The API layer rejects a non-positive capacity (422) as well."""
    _, sub = _category_with_sub(session)
    payload = {
        "name": "ห้ามศูนย์", "activity_type": "วิชาการ", "is_required": False,
        "max_participants": 0, "start_at": AUG.isoformat(), "location": "ห้อง",
        "hours": 2, "subcategory_id": sub.id,
    }
    resp = client.post("/activities", json=payload, headers=_admin_headers(tokens))
    assert resp.status_code == 422


# --------------------------- by-category uncategorized (#2) ---------------------------
def test_by_category_includes_uncategorized_and_matches_overview(client, session, tokens):
    """Approved hours on an activity with no subcategory land in the "ไม่ระบุหมวด"
    bucket, so the per-category averages sum to /overview's avg_hours."""
    _, sub = _category_with_sub(session, cat_required=10, sub_required=10)
    staff = _staff_id(session)
    cat_act = _activity(session, sub.id, staff, hours=4, name="มีหมวด")
    uncat_act = _activity(session, None, staff, hours=6, name="ไม่มีหมวด")  # subcategory_id NULL

    student = _student(session, "70020", "เอ", "วิศวกรรมศาสตร์", 2)
    _join(session, student.id, cat_act.id, 4)
    _join(session, student.id, uncat_act.id, 6)
    create_gold_layer(session)

    h = _admin_headers(tokens)
    overview = client.get("/dashboard/overview", headers=h).json()
    by_category = client.get("/dashboard/by-category", headers=h).json()

    assert any(r["category_key"] is None and r["category_name"] == "ไม่ระบุหมวด" for r in by_category)
    total_avg = round(sum(r["avg_earned_hours"] for r in by_category), 2)
    assert total_avg == overview["avg_hours"]  # every approved hour counted once
    assert overview["avg_hours"] == 10
