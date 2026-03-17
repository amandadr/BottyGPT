import logging
from application.vectorstore.base import BaseVectorStore
from application.core.settings import settings
from application.vectorstore.document_class import Document


def _get_embedding_dimension(embedding):
    """Return vector size for any embedding type (EmbeddingsWrapper, RemoteEmbeddings, OpenAI, etc.)."""
    dim = getattr(embedding, "dimension", None)
    if dim is not None:
        return dim
    if getattr(embedding, "client", None) is not None:
        try:
            return embedding.client[1].word_embedding_dimension
        except (AttributeError, IndexError, TypeError):
            pass
    # Fallback: embed one token and use length
    try:
        vec = embedding.embed_query("x")
        return len(vec) if vec else 1536
    except Exception:
        return 1536


def _make_qdrant_client():
    """Build QdrantClient from settings. Prefer url; fall back to location/path for local."""
    from qdrant_client import QdrantClient as QdrantClientClass

    if settings.QDRANT_URL:
        return QdrantClientClass(
            url=settings.QDRANT_URL,
            api_key=settings.QDRANT_API_KEY,
            timeout=settings.QDRANT_TIMEOUT,
            prefix=settings.QDRANT_PREFIX,
            https=settings.QDRANT_HTTPS,
        )
    if settings.QDRANT_LOCATION:
        return QdrantClientClass(
            location=settings.QDRANT_LOCATION,
            path=settings.QDRANT_PATH,
        )
    # Default for Docker/Compose
    return QdrantClientClass(
        url=settings.QDRANT_URL or "http://qdrant:6333",
        api_key=settings.QDRANT_API_KEY,
        timeout=settings.QDRANT_TIMEOUT,
    )


class QdrantStore(BaseVectorStore):
    def __init__(self, source_id: str = "", embeddings_key: str = "embeddings"):
        from qdrant_client import models
        from langchain_community.vectorstores.qdrant import Qdrant

        # Store the source_id for use in add_chunk
        self._source_id = str(source_id).replace("application/indexes/", "").rstrip("/")

        self._filter = models.Filter(
            must=[
                models.FieldCondition(
                    key="metadata.source_id",
                    match=models.MatchValue(value=self._source_id),
                )
            ]
        )

        embedding = self._get_embeddings(settings.EMBEDDINGS_NAME, embeddings_key)
        collection_name = settings.QDRANT_COLLECTION_NAME
        vector_size = _get_embedding_dimension(embedding)

        # Create client and collection ourselves so we never pass init_from (LangChain's
        # construct_instance passes init_from to recreate_collection, which triggers
        # qdrant_client's "Unknown arguments" assert).
        client = _make_qdrant_client()
        try:
            client.get_collection(collection_name=collection_name)
        except Exception:
            # Collection missing: create with only supported args (no init_from)
            distance_name = (settings.QDRANT_DISTANCE_FUNC or "Cosine").strip().upper()
            distance = getattr(models.Distance, distance_name, models.Distance.COSINE)
            client.recreate_collection(
                collection_name=collection_name,
                vectors_config=models.VectorParams(
                    size=vector_size,
                    distance=distance,
                ),
            )

        try:
            client.create_payload_index(
                collection_name=collection_name,
                field_name="metadata.source_id",
                field_schema=models.PayloadSchemaType.KEYWORD,
            )
        except Exception as index_error:
            if "already exists" not in str(index_error).lower():
                logging.warning("Could not create index for metadata.source_id: %s", index_error)

        # Wrap with LangChain Qdrant using our client (no construct_instance)
        distance_strategy = (settings.QDRANT_DISTANCE_FUNC or "Cosine").strip()
        self._docsearch = Qdrant(
            client=client,
            collection_name=collection_name,
            embeddings=embedding,
            distance_strategy=distance_strategy,
        )

    def search(self, *args, **kwargs):
        return self._docsearch.similarity_search(filter=self._filter, *args, **kwargs)

    def add_texts(self, *args, **kwargs):
        return self._docsearch.add_texts(*args, **kwargs)

    def save_local(self, *args, **kwargs):
        pass

    def delete_index(self, *args, **kwargs):
        return self._docsearch.client.delete(
            collection_name=settings.QDRANT_COLLECTION_NAME, points_selector=self._filter
        )

    def get_chunks(self):
        try:
            chunks = []
            offset = None
            while True:
                records, offset = self._docsearch.client.scroll(
                    collection_name=settings.QDRANT_COLLECTION_NAME,
                    scroll_filter=self._filter,
                    limit=10,
                    with_payload=True,
                    with_vectors=False,
                    offset=offset,
                )
                for record in records:
                    doc_id = record.id
                    text = record.payload.get("page_content")
                    metadata = record.payload.get("metadata")
                    chunks.append({"doc_id": doc_id, "text": text, "metadata": metadata})
                if offset is None:
                    break
            return chunks
        except Exception as e:
            logging.error(f"Error getting chunks: {e}", exc_info=True)
            return []

    def add_chunk(self, text, metadata=None):
        import uuid

        metadata = metadata or {}

        # Create a copy to avoid modifying the original metadata
        final_metadata = metadata.copy()

        # Ensure the source_id is in the metadata so the chunk can be found by filters
        final_metadata["source_id"] = self._source_id

        doc = Document(page_content=text, metadata=final_metadata)
        # Generate a unique ID for the document
        doc_id = str(uuid.uuid4())
        doc.id = doc_id
        doc_ids = self._docsearch.add_documents([doc])
        return doc_ids[0] if doc_ids else doc_id

    def delete_chunk(self, chunk_id):
        try:
            self._docsearch.client.delete(
                collection_name=settings.QDRANT_COLLECTION_NAME,
                points_selector=[chunk_id],
            )
            return True
        except Exception as e:
            logging.error(f"Error deleting chunk: {e}", exc_info=True)
            return False
