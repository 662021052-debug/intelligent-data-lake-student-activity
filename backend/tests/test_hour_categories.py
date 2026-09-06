"""admin จัดการหมวดชั่วโมงกิจกรรมเอง (FIX_Activity_NoBackdate_and_HourCategoryAdmin งานที่ 2)

หมวดชั่วโมงเป็น "เกณฑ์" ของทั้งระบบ — dropdown ของฟอร์มกิจกรรม, สรุปชั่วโมงของนิสิต
และกราฟรายหมวดบนแดชบอร์ดอ้างอิงตารางนี้ทั้งหมด เทสต์ชุดนี้จึงเน้น 2 เรื่อง:
เฉพาะ admin เท่านั้นที่แก้ได้ และการลบต้องไม่ทำให้ข้อมูลที่ผูกอยู่กำพร้า
"""

from tests.test_activities import make_activity

CATEGORY = {"name": "พัฒนาทักษะชีวิต", "required_hours": 12}


def auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def make_category(client, tokens, name="พัฒนาทักษะชีวิต", required_hours=12):
    return client.post(
        "/hour-categories",
        json={"name": name, "required_hours": required_hours},
        headers=auth(tokens["admin"]),
    )


def make_subcategory(client, tokens, category_id, name="กิจกรรมบูรณาการ 1", required_hours=4):
    return client.post(
        "/hour-subcategories",
        json={"category_id": category_id, "name": name, "required_hours": required_hours},
        headers=auth(tokens["admin"]),
    )


# ---------- สิทธิ์ ----------
def test_only_admin_can_create_category(client, tokens):
    for role in ("staff", "student"):
        response = client.post("/hour-categories", json=CATEGORY, headers=auth(tokens[role]))
        assert response.status_code == 403, role


def test_only_admin_can_update_or_delete_category(client, tokens):
    category_id = make_category(client, tokens).json()["id"]

    for role in ("staff", "student"):
        assert (
            client.put(
                f"/hour-categories/{category_id}", json=CATEGORY, headers=auth(tokens[role])
            ).status_code
            == 403
        )
        assert (
            client.delete(
                f"/hour-categories/{category_id}", headers=auth(tokens[role])
            ).status_code
            == 403
        )


def test_only_admin_can_manage_subcategories(client, tokens):
    category_id = make_category(client, tokens).json()["id"]
    sub_id = make_subcategory(client, tokens, category_id).json()["id"]
    payload = {"category_id": category_id, "name": "อะไรก็ได้", "required_hours": 2}

    for role in ("staff", "student"):
        assert (
            client.post("/hour-subcategories", json=payload, headers=auth(tokens[role])).status_code
            == 403
        )
        assert (
            client.put(
                f"/hour-subcategories/{sub_id}", json=payload, headers=auth(tokens[role])
            ).status_code
            == 403
        )
        assert (
            client.delete(f"/hour-subcategories/{sub_id}", headers=auth(tokens[role])).status_code
            == 403
        )


def test_everyone_can_still_read_the_list(client, tokens):
    """ฟอร์มกิจกรรมของเจ้าหน้าที่และการ์ดสมัครของนิสิตอ่านรายการนี้ ต้องไม่ถูกล็อกไว้ให้ admin"""
    make_category(client, tokens)
    for role in ("staff", "student"):
        assert client.get("/hour-categories", headers=auth(tokens[role])).status_code == 200


# ---------- สร้าง / แก้ไข ----------
def test_create_category_then_it_appears_in_the_list(client, tokens):
    response = make_category(client, tokens)
    assert response.status_code == 201
    body = response.json()
    assert body["name"] == "พัฒนาทักษะชีวิต"
    assert body["required_hours"] == 12
    assert body["subcategories"] == []

    listed = client.get("/hour-categories", headers=auth(tokens["admin"])).json()
    assert [c["name"] for c in listed] == ["พัฒนาทักษะชีวิต"]


def test_create_subcategory_shows_up_under_its_parent(client, tokens):
    category_id = make_category(client, tokens).json()["id"]

    response = make_subcategory(client, tokens, category_id, name="กิจกรรม ICT 1", required_hours=2)
    assert response.status_code == 201
    assert response.json()["category_id"] == category_id

    listed = client.get("/hour-categories", headers=auth(tokens["admin"])).json()
    assert [s["name"] for s in listed[0]["subcategories"]] == ["กิจกรรม ICT 1"]


def test_update_category(client, tokens):
    category_id = make_category(client, tokens).json()["id"]
    response = client.put(
        f"/hour-categories/{category_id}",
        json={"name": "พัฒนาทักษะชีวิต (ปรับปรุง)", "required_hours": 16},
        headers=auth(tokens["admin"]),
    )
    assert response.status_code == 200
    assert response.json()["name"] == "พัฒนาทักษะชีวิต (ปรับปรุง)"
    assert response.json()["required_hours"] == 16


def test_update_category_keeps_its_subcategories(client, tokens):
    """แก้หมวดใหญ่ต้องไม่ทำให้ลูกหายไปจากผลลัพธ์ (เคยพลาดได้ง่ายเพราะ _to_read รับ list มาเอง)"""
    category_id = make_category(client, tokens).json()["id"]
    make_subcategory(client, tokens, category_id, name="กิจกรรมบูรณาการ 1")

    response = client.put(
        f"/hour-categories/{category_id}",
        json={"name": "ชื่อใหม่", "required_hours": 10},
        headers=auth(tokens["admin"]),
    )
    assert [s["name"] for s in response.json()["subcategories"]] == ["กิจกรรมบูรณาการ 1"]


def test_update_subcategory_can_move_it_to_another_category(client, tokens):
    first = make_category(client, tokens, name="หมวด ก").json()["id"]
    second = make_category(client, tokens, name="หมวด ข").json()["id"]
    sub_id = make_subcategory(client, tokens, first, name="กิจกรรมย่อย").json()["id"]

    response = client.put(
        f"/hour-subcategories/{sub_id}",
        json={"category_id": second, "name": "กิจกรรมย่อย", "required_hours": 6},
        headers=auth(tokens["admin"]),
    )
    assert response.status_code == 200
    assert response.json()["category_id"] == second

    listed = client.get("/hour-categories", headers=auth(tokens["admin"])).json()
    by_name = {c["name"]: c for c in listed}
    assert by_name["หมวด ก"]["subcategories"] == []
    assert [s["name"] for s in by_name["หมวด ข"]["subcategories"]] == ["กิจกรรมย่อย"]


# ---------- ค่าที่รับไม่ได้ ----------
def test_required_hours_must_be_positive(client, tokens):
    assert make_category(client, tokens, required_hours=0).status_code == 422
    assert make_category(client, tokens, required_hours=-4).status_code == 422


def test_name_must_not_be_blank(client, tokens):
    assert make_category(client, tokens, name="").status_code == 422


def test_name_is_trimmed(client, tokens):
    assert make_category(client, tokens, name="  หมวดมีช่องว่าง  ").json()["name"] == (
        "หมวดมีช่องว่าง"
    )


def test_duplicate_category_name_is_rejected(client, tokens):
    make_category(client, tokens, name="หมวดซ้ำ")
    response = make_category(client, tokens, name="หมวดซ้ำ")
    assert response.status_code == 400
    assert "อยู่แล้ว" in response.json()["detail"]


def test_renaming_a_category_to_its_own_name_is_fine(client, tokens):
    """แก้แค่จำนวนชั่วโมงโดยไม่เปลี่ยนชื่อ ต้องไม่ไปชนกฎห้ามชื่อซ้ำของตัวเอง"""
    category_id = make_category(client, tokens, name="หมวดเดิม").json()["id"]
    response = client.put(
        f"/hour-categories/{category_id}",
        json={"name": "หมวดเดิม", "required_hours": 20},
        headers=auth(tokens["admin"]),
    )
    assert response.status_code == 200


def test_duplicate_subcategory_name_only_within_the_same_parent(client, tokens):
    first = make_category(client, tokens, name="หมวด ก").json()["id"]
    second = make_category(client, tokens, name="หมวด ข").json()["id"]
    make_subcategory(client, tokens, first, name="กิจกรรมบูรณาการ")

    assert make_subcategory(client, tokens, first, name="กิจกรรมบูรณาการ").status_code == 400
    # ชื่อเดียวกันแต่คนละหมวดใหญ่ใช้ได้ — ข้อมูลจริงของ มทษ. เป็นแบบนี้
    assert make_subcategory(client, tokens, second, name="กิจกรรมบูรณาการ").status_code == 201


def test_subcategory_needs_an_existing_parent(client, tokens):
    response = make_subcategory(client, tokens, 9999)
    assert response.status_code == 404


def test_unknown_ids_return_404(client, tokens):
    assert (
        client.put(
            "/hour-categories/9999", json=CATEGORY, headers=auth(tokens["admin"])
        ).status_code
        == 404
    )
    assert client.delete("/hour-categories/9999", headers=auth(tokens["admin"])).status_code == 404
    assert (
        client.delete("/hour-subcategories/9999", headers=auth(tokens["admin"])).status_code == 404
    )


def test_extra_fields_are_rejected(client, tokens):
    """กัน id/field แปลกปลอมถูกยัดมาทับ ตามแบบเดียวกับ DTO อื่นในระบบ"""
    response = client.post(
        "/hour-categories",
        json={**CATEGORY, "id": 99},
        headers=auth(tokens["admin"]),
    )
    assert response.status_code == 422


# ---------- ลบแบบปลอดภัย ----------
def test_delete_empty_category(client, tokens):
    category_id = make_category(client, tokens).json()["id"]
    assert (
        client.delete(f"/hour-categories/{category_id}", headers=auth(tokens["admin"])).status_code
        == 204
    )
    assert client.get("/hour-categories", headers=auth(tokens["admin"])).json() == []


def test_cannot_delete_category_that_still_has_subcategories(client, tokens):
    category_id = make_category(client, tokens).json()["id"]
    make_subcategory(client, tokens, category_id)

    response = client.delete(f"/hour-categories/{category_id}", headers=auth(tokens["admin"]))
    assert response.status_code == 400
    assert "หมวดย่อย" in response.json()["detail"]
    # ต้องยังอยู่ครบ ไม่ใช่ลบไปครึ่งทาง
    assert len(client.get("/hour-categories", headers=auth(tokens["admin"])).json()) == 1


def test_delete_unused_subcategory(client, tokens):
    category_id = make_category(client, tokens).json()["id"]
    sub_id = make_subcategory(client, tokens, category_id).json()["id"]

    assert (
        client.delete(f"/hour-subcategories/{sub_id}", headers=auth(tokens["admin"])).status_code
        == 204
    )
    listed = client.get("/hour-categories", headers=auth(tokens["admin"])).json()
    assert listed[0]["subcategories"] == []


def test_cannot_delete_subcategory_used_by_an_activity(client, tokens):
    category_id = make_category(client, tokens).json()["id"]
    sub_id = make_subcategory(client, tokens, category_id).json()["id"]
    activity = make_activity(client)
    assert activity.status_code == 201
    client.put(
        f"/activities/{activity.json()['id']}",
        json={"subcategory_id": sub_id},
        headers=auth(tokens["admin"]),
    )

    response = client.delete(f"/hour-subcategories/{sub_id}", headers=auth(tokens["admin"]))
    assert response.status_code == 400
    assert "กิจกรรม" in response.json()["detail"]


def test_deleting_a_category_leaves_the_other_ones_alone(client, tokens):
    keep = make_category(client, tokens, name="หมวดที่เก็บไว้").json()["id"]
    drop = make_category(client, tokens, name="หมวดที่ลบ").json()["id"]

    assert client.delete(f"/hour-categories/{drop}", headers=auth(tokens["admin"])).status_code == 204
    listed = client.get("/hour-categories", headers=auth(tokens["admin"])).json()
    assert [c["id"] for c in listed] == [keep]
