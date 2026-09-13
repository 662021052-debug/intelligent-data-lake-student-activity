"""รายชื่อคณะที่มีอยู่จริงในระบบ — ใช้เติมช่องเลือกคณะในฟอร์มและตัวกรอง

อ่านจากคอลัมน์ ``student.faculty`` แบบ distinct แทนการมีตาราง "คณะ" แยกต่างหาก
เพราะชื่อคณะที่ระบบใช้จริงคือค่าที่อยู่ในข้อมูลนิสิตอยู่แล้ว (นำเข้ามาจากไฟล์ของ
มหาวิทยาลัย) — ตารางแยกจะกลายเป็นแหล่งความจริงที่สองที่ต้องคอยตามให้ตรงกัน

ผลที่ตามมาคือคณะที่ "ยังไม่มีนิสิตสักคน" จะไม่อยู่ในรายการ ฝั่งฟอร์มจึงต้องยังพิมพ์
ชื่อคณะใหม่ได้เอง (เป็น combobox ไม่ใช่ dropdown ที่เลือกได้เฉพาะในรายการ)
"""

from fastapi import APIRouter, Depends
from sqlmodel import Session, select

from app.auth import get_current_user
from app.database import get_session
from app.models import Student

router = APIRouter(tags=["faculties"], dependencies=[Depends(get_current_user)])


@router.get("/faculties", response_model=list[str])
def list_faculties(session: Session = Depends(get_session)):
    """ชื่อคณะทั้งหมดที่มีนิสิตอยู่ เรียงตามตัวอักษร

    กรองค่าว่าง/ช่องว่างล้วนออก — ข้อมูลนำเข้าที่คณะหลุดมาเป็นค่าว่างไม่ควรกลาย
    เป็นตัวเลือกเปล่า ๆ ในรายการให้ผู้ดูแลกดโดนโดยไม่ตั้งใจ
    """
    rows = session.exec(select(Student.faculty).distinct()).all()
    return sorted({name.strip() for name in rows if name and name.strip()})
