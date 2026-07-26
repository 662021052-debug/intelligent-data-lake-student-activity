"""Chatbot endpoint: student-facing Q&A about activities (Phases 16–17).

A single ``POST /chatbot/ask`` classifies the question and routes it:
  * RULES/criteria  → RAG over the public rules document (Phase 16)
  * my hours / missing categories → parameterized, student-scoped SQL (Phase 17)
  * open / required activities     → public activity-catalog SQL
  * anything else (general data)   → sandboxed LLM Text-to-SQL

Student-only: the data paths read the caller's own record, so the whole endpoint
requires a linked student account.
"""
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlmodel import Session

from app import chatbot_sql, rag
from app.auth import require_roles
from app.chatbot_sql import Intent
from app.config import settings
from app.database import get_session
from app.llm import LlmClient, get_llm
from app.models import User, UserRole
from app.vectorstore import VectorStore, get_vector_store

router = APIRouter(prefix="/chatbot", tags=["chatbot"])

require_student = require_roles(UserRole.student)


class AskRequest(BaseModel):
    question: str


class ChatSource(BaseModel):
    source: str
    chunk_index: int
    content: str
    score: float


class AskResponse(BaseModel):
    intent: str
    answer: str
    sources: list[ChatSource] = []


def _rag_answer(
    question: str, llm: LlmClient, store: VectorStore
) -> AskResponse:
    answer, chunks = rag.answer_rules_question(llm, store, question, settings.rag_top_k)
    return AskResponse(
        intent=Intent.RULES.value,
        answer=answer,
        sources=[
            ChatSource(source=c.source, chunk_index=c.chunk_index, content=c.content, score=c.score)
            for c in chunks
        ],
    )


@router.post("/ask", response_model=AskResponse)
def ask(
    payload: AskRequest,
    current_user: User = Depends(require_student),
    session: Session = Depends(get_session),
    llm: LlmClient = Depends(get_llm),
    store: VectorStore = Depends(get_vector_store),
) -> AskResponse:
    question = payload.question.strip()
    if not question:
        raise HTTPException(status_code=400, detail="กรุณาพิมพ์คำถาม")

    intent = chatbot_sql.classify_intent(question)

    if intent == Intent.RULES:
        return _rag_answer(question, llm, store)

    # Public activity-catalog questions need no student linkage.
    if intent == Intent.OPEN_ACTIVITIES:
        result = chatbot_sql.answer_open_activities(session)
    elif intent == Intent.REQUIRED:
        result = chatbot_sql.answer_required_activities(session)
    else:
        # Student-scoped intents (hours / missing / general Text-to-SQL).
        if current_user.student_id is None:
            raise HTTPException(
                status_code=400, detail="บัญชีของคุณยังไม่ได้ผูกกับข้อมูลนิสิต"
            )
        if intent == Intent.HOURS:
            result = chatbot_sql.answer_hours(session, current_user.student_id)
        elif intent == Intent.MISSING:
            result = chatbot_sql.answer_missing(session, current_user.student_id)
        elif intent == Intent.RECOMMEND:
            result = chatbot_sql.recommend(session, current_user.student_id, question)
        else:  # Intent.GENERAL
            result = chatbot_sql.run_text_to_sql(llm, session, question, current_user.student_id)

    return AskResponse(intent=result.intent.value, answer=result.answer)
