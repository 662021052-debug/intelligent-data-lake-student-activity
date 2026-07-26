"""Retrieval-Augmented Generation for the activity-rules chatbot (Phase 16).

Ingests the public TSU activity-hour criteria document into the vector store and
retrieves the most relevant chunks for a student's Thai-language question, then
asks the LLM to answer grounded on those chunks.

Security note: the rules document is *public*, so its text may be sent to the LLM.
Student-specific data (hours, history) is different — it never leaves the backend
and is answered by Text-to-SQL in Phase 17, not by this module.
"""
from __future__ import annotations

from app.llm import LlmClient
from app.vectorstore import RetrievedChunk, StoredChunk, VectorStore

# Logical name of the ingested rules document (one "source" in the vector store).
RULES_SOURCE = "tsu_activity_criteria"

# The public criteria document (TSU activity-hour structure: 5 categories, 60 hours
# minimum, 4-year curriculum). Each blank-line-separated block becomes one chunk, so
# a question about a category retrieves that category's block. This is the text form
# of the "regular.pdf" the proposal refers to.
RULES_DOCUMENT = """\
เกณฑ์กิจกรรมเสริมหลักสูตร มหาวิทยาลัยทักษิณ (หลักสูตร 4 ปี)
นิสิตต้องเข้าร่วมกิจกรรมและสะสมชั่วโมงให้ครบ 60 ชั่วโมงเป็นอย่างน้อย โดยแบ่งเป็น 5 หมวด ตามโครงสร้างด้านล่าง จึงจะถือว่าผ่านเกณฑ์กิจกรรมเพื่อสำเร็จการศึกษา

หมวดที่ 1 พัฒนาทักษะชีวิต จำนวน 12 ชั่วโมง
ประกอบด้วยกิจกรรมย่อย: กิจกรรมเสริมสร้างคุณค่าแห่งตน 8 ชั่วโมง และกิจกรรมบูรณาการ 1 จำนวน 4 ชั่วโมง มุ่งพัฒนาทักษะการใช้ชีวิต การอยู่ร่วมกับผู้อื่น และการเห็นคุณค่าในตนเอง

หมวดที่ 2 TSU รับใช้สังคม จำนวน 12 ชั่วโมง
ประกอบด้วยกิจกรรม TSU DO D : สร้างสรรค์สร้างสำนึกรับผิดชอบต่อสังคม จำนวน 12 ชั่วโมง เป็นกิจกรรมจิตอาสาและบำเพ็ญประโยชน์เพื่อชุมชนและสังคม

หมวดที่ 3 ศิลปวัฒนธรรมอาเซียน จำนวน 8 ชั่วโมง
ประกอบด้วยกิจกรรมเรียนรู้ศิลปวัฒนธรรมอาเซียน 6 ชั่วโมง และกิจกรรมบูรณาการ 3 จำนวน 2 ชั่วโมง มุ่งให้นิสิตเรียนรู้และเห็นคุณค่าของศิลปวัฒนธรรมไทยและอาเซียน

หมวดที่ 4 พัฒนาคุณธรรมและวินัย จำนวน 8 ชั่วโมง
ประกอบด้วยกิจกรรมสร้างวินัยในตนเอง 4 ชั่วโมง และกิจกรรมบูรณาการ 4 จำนวน 4 ชั่วโมง มุ่งปลูกฝังคุณธรรม จริยธรรม และความมีวินัย

หมวดที่ 5 ใฝ่เรียนรู้ตลอดชีวิต จำนวน 20 ชั่วโมง
ประกอบด้วยกิจกรรม ICT กับการรู้สารสนเทศ 1 และ 2 อย่างละ 2 ชั่วโมง, กิจกรรมเรียนรู้และรู้เท่าทันเทคโนโลยีดิจิทัล 4 ชั่วโมง, กิจกรรมปฐมนิเทศ 4 ชั่วโมง, กิจกรรมปัจฉิมนิเทศ 4 ชั่วโมง และกิจกรรมบูรณาการ 5 จำนวน 4 ชั่วโมง

การนับชั่วโมงและการอนุมัติ
ชั่วโมงกิจกรรมจะถูกนับให้ก็ต่อเมื่อนิสิตเข้าร่วมกิจกรรมจริง อัปโหลดหลักฐาน และหลักฐานได้รับการอนุมัติแล้วเท่านั้น กิจกรรมบางรายการเป็นกิจกรรมบังคับที่นิสิตทุกคนต้องเข้าร่วม
"""


def chunk_document(text: str) -> list[str]:
    """Split into chunks on blank lines. Each block (a category or a rule) is one
    self-contained chunk — the natural retrieval unit for this document."""
    blocks = [block.strip() for block in text.split("\n\n")]
    return [block for block in blocks if block]


def ingest_rules(llm: LlmClient, store: VectorStore, document: str = RULES_DOCUMENT) -> int:
    """Chunk, embed, and (idempotently) load the rules document into the store.
    Returns the number of chunks ingested."""
    chunks = chunk_document(document)
    if not chunks:
        store.replace_source(RULES_SOURCE, [])
        return 0
    embeddings = llm.embed(chunks)
    stored = [
        StoredChunk(source=RULES_SOURCE, chunk_index=i, content=content, embedding=embedding)
        for i, (content, embedding) in enumerate(zip(chunks, embeddings))
    ]
    store.replace_source(RULES_SOURCE, stored)
    return len(stored)


def retrieve(llm: LlmClient, store: VectorStore, question: str, k: int) -> list[RetrievedChunk]:
    query_embedding = llm.embed_query(question)
    return store.search(query_embedding, k)


_SYSTEM_PROMPT = (
    "คุณเป็นผู้ช่วยตอบคำถามเรื่องเกณฑ์กิจกรรมเสริมหลักสูตรของมหาวิทยาลัยทักษิณ "
    "ตอบเป็นภาษาไทยอย่างกระชับและถูกต้อง โดยอ้างอิงจากข้อมูลเกณฑ์ที่ให้ไว้เท่านั้น "
    "หากข้อมูลที่ให้ไม่เพียงพอ ให้บอกว่าไม่ทราบและแนะนำให้ติดต่อเจ้าหน้าที่"
)


def _build_prompt(question: str, chunks: list[RetrievedChunk]) -> str:
    context = "\n\n".join(f"[{i + 1}] {c.content}" for i, c in enumerate(chunks))
    return (
        f"ข้อมูลเกณฑ์กิจกรรมที่เกี่ยวข้อง:\n{context}\n\n"
        f"คำถามของนิสิต: {question}\n\n"
        "คำตอบ:"
    )


def answer_rules_question(
    llm: LlmClient, store: VectorStore, question: str, k: int
) -> tuple[str, list[RetrievedChunk]]:
    """RAG answer: retrieve relevant rule chunks and let the LLM answer grounded
    on them. Returns ``(answer_text, retrieved_chunks)``."""
    chunks = retrieve(llm, store, question, k)
    if not chunks:
        return (
            "ขออภัย ยังไม่มีข้อมูลเกณฑ์กิจกรรมในระบบ กรุณาติดต่อเจ้าหน้าที่",
            [],
        )
    answer = llm.generate(_build_prompt(question, chunks), system=_SYSTEM_PROMPT)
    return answer, chunks
