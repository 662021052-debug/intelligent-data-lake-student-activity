"""Phase 16 — chatbot RAG over the public activity-rules document.

Uses the offline StubLlm (deterministic char-ngram embeddings) and a fresh
in-memory vector store, so no Gemini key / network is required.
"""
import pytest

from app import rag
from app.llm import StubLlm, get_llm
from app.vectorstore import InMemoryVectorStore, get_vector_store


@pytest.fixture(name="chatbot")
def chatbot_fixture(client):
    """Wire an offline LLM + a freshly-ingested in-memory vector store into the app."""
    llm = StubLlm()
    store = InMemoryVectorStore()
    rag.ingest_rules(llm, store)

    from app.main import app

    app.dependency_overrides[get_llm] = lambda: llm
    app.dependency_overrides[get_vector_store] = lambda: store
    # conftest's client fixture clears all overrides on teardown.
    return client


def _ask(client, token, question):
    return client.post(
        "/chatbot/ask",
        json={"question": question},
        headers={"Authorization": f"Bearer {token}"},
    )


def test_rag_retrieves_relevant_rule_chunk(chatbot, tokens):
    resp = _ask(chatbot, tokens["student"], "หมวด TSU รับใช้สังคม ต้องเก็บกี่ชั่วโมง")
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["sources"], "RAG should return at least one source chunk"
    # The most relevant chunk must be the "TSU รับใช้สังคม" category block.
    top = body["sources"][0]
    assert "TSU รับใช้สังคม" in top["content"]
    assert "12 ชั่วโมง" in top["content"]
    assert isinstance(body["answer"], str) and body["answer"]


def test_rag_ranks_the_matching_category_first(chatbot, tokens):
    resp = _ask(chatbot, tokens["student"], "อยากรู้เรื่องหมวดศิลปวัฒนธรรมอาเซียน")
    assert resp.status_code == 200, resp.text
    assert "ศิลปวัฒนธรรมอาเซียน" in resp.json()["sources"][0]["content"]


def test_total_hours_question_retrieves_overview(chatbot, tokens):
    resp = _ask(chatbot, tokens["student"], "ต้องเก็บกิจกรรมทั้งหมดกี่ชั่วโมงถึงจะจบ")
    assert resp.status_code == 200, resp.text
    contents = " ".join(s["content"] for s in resp.json()["sources"])
    assert "60 ชั่วโมง" in contents


def test_chatbot_is_student_only(chatbot, tokens):
    for role in ("staff", "admin"):
        resp = _ask(chatbot, tokens[role], "หมวด TSU รับใช้สังคม กี่ชั่วโมง")
        assert resp.status_code == 403, f"{role} should be forbidden: {resp.text}"


def test_empty_question_is_rejected(chatbot, tokens):
    resp = _ask(chatbot, tokens["student"], "   ")
    assert resp.status_code == 400


def test_ask_requires_authentication(chatbot):
    resp = chatbot.post(
        "/chatbot/ask",
        json={"question": "กี่ชั่วโมง"},
        headers={"Authorization": "Bearer not-a-valid-token"},
    )
    assert resp.status_code == 401
