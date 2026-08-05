from contextlib import asynccontextmanager

from fastapi import FastAPI, Response, status
from pydantic import BaseModel
from sentence_transformers import CrossEncoder, SentenceTransformer

EMBEDDING_MODEL_NAME = "all-MiniLM-L6-v2"
RERANK_MODEL_NAME = "cross-encoder/ms-marco-MiniLM-L-6-v2"

models: dict[str, object] = {}


@asynccontextmanager
async def lifespan(app: FastAPI):
    models["bi_encoder"] = SentenceTransformer(EMBEDDING_MODEL_NAME)
    models["cross_encoder"] = CrossEncoder(RERANK_MODEL_NAME)
    models["loaded"] = True
    yield
    models.clear()


app = FastAPI(lifespan=lifespan)


class EmbedRequest(BaseModel):
    texts: list[str]


class EmbedResponse(BaseModel):
    embeddings: list[list[float]]


class RerankRequest(BaseModel):
    query: str
    candidates: list[str]


class RerankResponse(BaseModel):
    scores: list[float]


@app.post("/embed")
def embed(payload: EmbedRequest) -> EmbedResponse:
    if not payload.texts:
        return EmbedResponse(embeddings=[])
    vectors = models["bi_encoder"].encode(payload.texts)
    return EmbedResponse(embeddings=[vector.tolist() for vector in vectors])


@app.post("/rerank")
def rerank(payload: RerankRequest) -> RerankResponse:
    if not payload.candidates:
        return RerankResponse(scores=[])
    pairs = [[payload.query, candidate] for candidate in payload.candidates]
    scores = models["cross_encoder"].predict(pairs)
    return RerankResponse(scores=[float(score) for score in scores])


@app.get("/health")
def health(response: Response) -> dict[str, bool]:
    ready = bool(models.get("loaded"))
    if not ready:
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
    return {"ready": ready}
