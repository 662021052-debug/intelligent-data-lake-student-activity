/// ป้ายชื่อสถานะหลักฐาน — สีของสถานะอยู่ที่ `widgets/status_chip.dart` ที่เดียว
String evidenceLabel(String status) {
  switch (status) {
    case 'approved':
      return 'อนุมัติ';
    case 'rejected':
      return 'ไม่อนุมัติ';
    default:
      return 'รอตรวจสอบ';
  }
}
