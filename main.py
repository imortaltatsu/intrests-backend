import os
import logging
from typing import List, Optional, Dict, Any
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
import chromadb
from chromadb.config import Settings
import uvicorn

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ChromaDB Configuration
CHROMA_PERSIST_DIR = os.path.join("..", "glimpse_backend", "index_data", "chroma_db")

# Initialize ChromaDB client
chroma_client = chromadb.PersistentClient(
    path=CHROMA_PERSIST_DIR,
    settings=Settings(anonymized_telemetry=False, allow_reset=True)
)

# Get collections
collections = {}
for modality in ["image", "video"]:
    try:
        collections[modality] = chroma_client.get_collection(f"arweave_{modality}")
        logger.info(f"✅ Loaded collection 'arweave_{modality}'")
    except Exception as e:
        logger.warning(f"Collection 'arweave_{modality}' not found: {e}")

# FastAPI app
app = FastAPI(
    title="Vector Gateway",
    description="Minimal vector retrieval service for doom scroller recommendations",
    version="1.0.0"
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Request/Response models
class QueryRequest(BaseModel):
    embedding: List[float] = Field(..., description="1024-dimensional embedding vector")
    k: Optional[int] = Field(50, ge=1, le=200, description="Number of results to return")
    filter_nsfw: Optional[bool] = Field(False, description="Filter out NSFW content")

class QueryResult(BaseModel):
    id: str
    score: float
    metadata: Dict[str, Any]

class QueryResponse(BaseModel):
    index_version: str
    results: List[QueryResult]

class EmbeddingResponse(BaseModel):
    txid: str
    embedding: Optional[List[float]]
    found: bool
    index_version: str

def get_index_version() -> str:
    """Generate index version from ChromaDB directory mtime"""
    try:
        mtime = os.path.getmtime(CHROMA_PERSIST_DIR)
        return str(int(mtime))
    except:
        return "unknown"

def validate_embedding(embedding: List[float]) -> None:
    """Validate embedding vector"""
    if len(embedding) != 1024:
        raise HTTPException(status_code=400, detail="Embedding must be 1024-dimensional")
    
    if any(not isinstance(x, (int, float)) or not (float('-inf') < x < float('inf')) for x in embedding):
        raise HTTPException(status_code=400, detail="Embedding contains invalid values (NaN/Inf)")

@app.get("/healthz")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "ok",
        "index_ready": len(collections) > 0,
        "collections": list(collections.keys())
    }

@app.post("/query", response_model=QueryResponse)
async def query_vectors(request: QueryRequest):
    """Query similar vectors from image and video collections"""
    try:
        validate_embedding(request.embedding)
        
        all_results = []
        
        # Query both image and video collections
        for modality, collection in collections.items():
            try:
                results = collection.query(
                    query_embeddings=[request.embedding],
                    n_results=request.k,
                    include=["metadatas", "distances"]
                )
                
                if results["ids"] and results["ids"][0]:
                    for i, (id_val, distance, metadata) in enumerate(zip(
                        results["ids"][0],
                        results["distances"][0],
                        results["metadatas"][0]
                    )):
                        # Filter NSFW if requested
                        if request.filter_nsfw and metadata.get("is_nsfw", False):
                            continue
                            
                        all_results.append(QueryResult(
                            id=id_val,
                            score=1.0 - distance,  # Convert distance to similarity score
                            metadata=metadata
                        ))
                        
            except Exception as e:
                logger.warning(f"Error querying {modality} collection: {e}")
                continue
        
        # Sort by score and limit results
        all_results.sort(key=lambda x: x.score, reverse=True)
        all_results = all_results[:request.k]
        
        return QueryResponse(
            index_version=get_index_version(),
            results=all_results
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Query error: {e}")
        raise HTTPException(status_code=500, detail=f"Query failed: {str(e)}")

@app.get("/embedding/{txid}", response_model=EmbeddingResponse)
async def get_embedding(txid: str):
    """Get embedding for a specific transaction ID"""
    try:
        embedding = None
        found = False
        
        # Search in both collections
        for modality, collection in collections.items():
            try:
                results = collection.get(
                    where={"txid": txid},
                    include=["embeddings"]
                )
                
                if results["embeddings"]:
                    embedding = results["embeddings"][0]
                    found = True
                    break
                    
            except Exception as e:
                logger.warning(f"Error searching {modality} collection for {txid}: {e}")
                continue
        
        return EmbeddingResponse(
            txid=txid,
            embedding=embedding,
            found=found,
            index_version=get_index_version()
        )
        
    except Exception as e:
        logger.error(f"Embedding lookup error for {txid}: {e}")
        raise HTTPException(status_code=500, detail=f"Embedding lookup failed: {str(e)}")

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
