# Vector Gateway

Minimal vector retrieval service for doom scroller recommendations. Provides vector similarity search and embedding lookup for AO processes.

## Features

- **Vector Similarity Search**: Query similar vectors from image and video collections
- **Embedding Lookup**: Retrieve embeddings by Arweave transaction ID
- **NSFW Filtering**: Optional content filtering
- **Direct ChromaDB Access**: Connects to existing `glimpse_backend/index_data/chroma_db`

## API Endpoints

### POST `/query`
Query similar vectors using a 1024-dimensional embedding.

**Request:**
```json
{
  "embedding": [0.1, 0.2, ...],  // 1024-dimensional vector
  "k": 50,                       // Number of results (1-200, default 50)
  "filter_nsfw": false           // Filter NSFW content (optional)
}
```

**Response:**
```json
{
  "index_version": "1704067200",
  "results": [
    {
      "id": "content_id",
      "score": 0.95,
      "metadata": {
        "txid": "arweave_tx_id",
        "type": "image",
        "url": "https://...",
        "is_nsfw": false
      }
    }
  ]
}
```

### GET `/embedding/{txid}`
Get embedding for a specific Arweave transaction ID.

**Response:**
```json
{
  "txid": "arweave_tx_id",
  "embedding": [0.1, 0.2, ...],  // 1024-dimensional vector or null
  "found": true,
  "index_version": "1704067200"
}
```

### GET `/healthz`
Health check endpoint.

**Response:**
```json
{
  "status": "ok",
  "index_ready": true,
  "collections": ["image", "video"]
}
```

## Usage

### Development
```bash
uv run python main.py
```

### Production
```bash
uv run uvicorn main:app --host 0.0.0.0 --port 8000
```

## Integration with AO

This service is designed to work with AO processes for doom scroller recommendations:

1. **User Profile**: AO maintains user taste as sum of liked content embeddings
2. **Recommendation**: AO calls `/query` with user profile embedding → gets 200 candidates
3. **Lua Re-ranking**: AO processes re-rank candidates based on diversity, recency, etc.
4. **Embedding Lookup**: AO calls `/embedding/{txid}` to retrieve embeddings of liked content

## Architecture

- **Collections**: Searches `arweave_image` and `arweave_video` collections
- **Embedding Dimension**: 1024 (matches ImageBind)
- **Index Version**: Generated from ChromaDB directory mtime for consistency
- **Error Handling**: Validates embeddings, handles missing collections gracefully
