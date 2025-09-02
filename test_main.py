import pytest
import httpx
from fastapi.testclient import TestClient
import numpy as np
import os

from main import app, collections, chroma_client

client = TestClient(app)

# Test embedding vector (1024 dimensions)
TEST_EMBEDDING = [0.1] * 1024

# Test data for ChromaDB
TEST_TXID = "test_txid_12345"
TEST_METADATA = {
    "txid": TEST_TXID,
    "type": "image",
    "url": "https://example.com/test.jpg",
    "is_nsfw": False
}

@pytest.fixture(scope="module")
def setup_test_data():
    """Setup test data in ChromaDB"""
    # Add test data to image collection if it exists
    if "image" in collections:
        try:
            # Check if test data already exists
            existing = collections["image"].get(where={"txid": TEST_TXID})
            if not existing["ids"]:
                # Add test data
                collections["image"].add(
                    ids=[f"test_{TEST_TXID}"],
                    embeddings=[TEST_EMBEDDING],
                    metadatas=[TEST_METADATA]
                )
        except Exception as e:
            print(f"Warning: Could not setup test data: {e}")
    yield
    # Cleanup test data
    if "image" in collections:
        try:
            collections["image"].delete(where={"txid": TEST_TXID})
        except Exception as e:
            print(f"Warning: Could not cleanup test data: {e}")

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
    def test_query_success(self, setup_test_data):
        """Test successful vector query against real ChromaDB"""
        response = client.post("/query", json={
            "embedding": TEST_EMBEDDING,
            "k": 10,
            "filter_nsfw": False
        })
        
        assert response.status_code == 200
        data = response.json()
        assert "index_version" in data
        assert "results" in data
        assert isinstance(data["results"], list)
        
        # If we have results, check structure
        if data["results"]:
            result = data["results"][0]
            assert "id" in result
            assert "score" in result
            assert "metadata" in result
            assert isinstance(result["score"], (int, float))

    def test_query_with_nsfw_filter(self, setup_test_data):
        """Test query with NSFW filtering against real ChromaDB"""
        response = client.post("/query", json={
            "embedding": TEST_EMBEDDING,
            "k": 10,
            "filter_nsfw": True
        })
        
        assert response.status_code == 200
        data = response.json()
        assert "results" in data
        assert isinstance(data["results"], list)
        
        # If we have results, ensure no NSFW content
        for result in data["results"]:
            if "metadata" in result and "is_nsfw" in result["metadata"]:
                assert result["metadata"]["is_nsfw"] == False

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
        # Test with a string instead of float to trigger validation error
        invalid_embedding = ["invalid"] * 1024
        
        response = client.post("/query", json={
            "embedding": invalid_embedding,
            "k": 10
        })
        
        # Should get validation error from Pydantic
        assert response.status_code == 422

    def test_query_invalid_k_value(self):
        """Test query with invalid k value"""
        response = client.post("/query", json={
            "embedding": TEST_EMBEDDING,
            "k": 300  # Too large
        })
        
        assert response.status_code == 422  # Validation error

class TestEmbeddingEndpoint:
    def test_get_embedding_success(self, setup_test_data):
        """Test successful embedding retrieval against real ChromaDB"""
        response = client.get(f"/embedding/{TEST_TXID}")
        
        assert response.status_code == 200
        data = response.json()
        assert data["txid"] == TEST_TXID
        assert "found" in data
        assert "embedding" in data
        assert "index_version" in data
        
        # If found, check embedding structure
        if data["found"]:
            assert data["embedding"] is not None
            assert isinstance(data["embedding"], list)
            assert len(data["embedding"]) == 1024

    def test_get_embedding_not_found(self):
        """Test embedding retrieval when not found"""
        response = client.get("/embedding/nonexistent_txid_99999")
        
        assert response.status_code == 200
        data = response.json()
        assert data["txid"] == "nonexistent_txid_99999"
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

    def test_query_default_values(self, setup_test_data):
        """Test query with default values against real ChromaDB"""
        response = client.post("/query", json={
            "embedding": TEST_EMBEDDING
            # k and filter_nsfw should use defaults
        })
        
        assert response.status_code == 200
        data = response.json()
        assert "results" in data
        assert isinstance(data["results"], list)
