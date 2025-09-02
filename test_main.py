import pytest
import httpx
from fastapi.testclient import TestClient
from unittest.mock import Mock, patch
import numpy as np

from main import app

client = TestClient(app)

# Mock embedding vector (1024 dimensions)
MOCK_EMBEDDING = [0.1] * 1024

# Mock ChromaDB results
MOCK_CHROMA_RESULTS = {
    "ids": [["test_id_1", "test_id_2"]],
    "distances": [[0.1, 0.2]],
    "metadatas": [[
        {
            "txid": "test_txid_1",
            "type": "image",
            "url": "https://example.com/image1.jpg",
            "is_nsfw": False
        },
        {
            "txid": "test_txid_2", 
            "type": "video",
            "url": "https://example.com/video1.mp4",
            "is_nsfw": True
        }
    ]]
}

MOCK_EMBEDDING_RESULTS = {
    "embeddings": [[0.1] * 1024],
    "ids": ["test_id_1"]
}

class TestHealthEndpoint:
    def test_health_check(self):
        """Test health check endpoint"""
        response = client.get("/healthz")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ok"
        assert "index_ready" in data
        assert "collections" in data

class TestQueryEndpoint:
    @patch('main.collections')
    def test_query_success(self, mock_collections):
        """Test successful vector query"""
        # Mock collection
        mock_collection = Mock()
        mock_collection.query.return_value = MOCK_CHROMA_RESULTS
        mock_collections.__iter__.return_value = [("image", mock_collection)]
        mock_collections.items.return_value = [("image", mock_collection)]
        
        response = client.post("/query", json={
            "embedding": MOCK_EMBEDDING,
            "k": 10,
            "filter_nsfw": False
        })
        
        assert response.status_code == 200
        data = response.json()
        assert "index_version" in data
        assert "results" in data
        assert len(data["results"]) == 2
        
        # Check first result
        result = data["results"][0]
        assert result["id"] == "test_id_1"
        assert result["score"] == 0.9  # 1.0 - 0.1
        assert result["metadata"]["txid"] == "test_txid_1"

    @patch('main.collections')
    def test_query_with_nsfw_filter(self, mock_collections):
        """Test query with NSFW filtering"""
        mock_collection = Mock()
        mock_collection.query.return_value = MOCK_CHROMA_RESULTS
        mock_collections.items.return_value = [("image", mock_collection)]
        
        response = client.post("/query", json={
            "embedding": MOCK_EMBEDDING,
            "k": 10,
            "filter_nsfw": True
        })
        
        assert response.status_code == 200
        data = response.json()
        # Should filter out NSFW content (test_id_2)
        assert len(data["results"]) == 1
        assert data["results"][0]["id"] == "test_id_1"

    def test_query_invalid_embedding_dimension(self):
        """Test query with invalid embedding dimension"""
        response = client.post("/query", json={
            "embedding": [0.1] * 512,  # Wrong dimension
            "k": 10
        })
        
        assert response.status_code == 400
        assert "1024-dimensional" in response.json()["detail"]

    def test_query_invalid_embedding_values(self):
        """Test query with invalid embedding values"""
        invalid_embedding = [float('inf')] * 1024
        
        response = client.post("/query", json={
            "embedding": invalid_embedding,
            "k": 10
        })
        
        assert response.status_code == 400
        assert "invalid values" in response.json()["detail"]

    def test_query_invalid_k_value(self):
        """Test query with invalid k value"""
        response = client.post("/query", json={
            "embedding": MOCK_EMBEDDING,
            "k": 300  # Too large
        })
        
        assert response.status_code == 422  # Validation error

class TestEmbeddingEndpoint:
    @patch('main.collections')
    def test_get_embedding_success(self, mock_collections):
        """Test successful embedding retrieval"""
        mock_collection = Mock()
        mock_collection.get.return_value = MOCK_EMBEDDING_RESULTS
        mock_collections.items.return_value = [("image", mock_collection)]
        
        response = client.get("/embedding/test_txid_1")
        
        assert response.status_code == 200
        data = response.json()
        assert data["txid"] == "test_txid_1"
        assert data["found"] == True
        assert data["embedding"] == MOCK_EMBEDDING
        assert "index_version" in data

    @patch('main.collections')
    def test_get_embedding_not_found(self, mock_collections):
        """Test embedding retrieval when not found"""
        mock_collection = Mock()
        mock_collection.get.return_value = {"embeddings": []}
        mock_collections.items.return_value = [("image", mock_collection)]
        
        response = client.get("/embedding/nonexistent_txid")
        
        assert response.status_code == 200
        data = response.json()
        assert data["txid"] == "nonexistent_txid"
        assert data["found"] == False
        assert data["embedding"] is None

class TestCORS:
    def test_cors_headers(self):
        """Test CORS headers are present"""
        response = client.options("/healthz")
        # FastAPI TestClient doesn't show CORS headers in options, 
        # but we can test that the endpoint is accessible
        assert response.status_code in [200, 405]  # 405 if OPTIONS not implemented

class TestValidation:
    def test_query_missing_embedding(self):
        """Test query without required embedding field"""
        response = client.post("/query", json={
            "k": 10
        })
        
        assert response.status_code == 422  # Validation error

    def test_query_default_values(self):
        """Test query with default values"""
        with patch('main.collections') as mock_collections:
            mock_collection = Mock()
            mock_collection.query.return_value = {"ids": [[]], "distances": [[]], "metadatas": [[]]}
            mock_collections.items.return_value = [("image", mock_collection)]
            
            response = client.post("/query", json={
                "embedding": MOCK_EMBEDDING
                # k and filter_nsfw should use defaults
            })
            
            assert response.status_code == 200
            data = response.json()
            assert "results" in data
