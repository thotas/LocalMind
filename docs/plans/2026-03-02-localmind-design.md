# LocalMind — Architecture & Design Document

## Overview

LocalMind is a native macOS desktop app for local, privacy-preserving document Q&A. Users add local folders, the app indexes their contents into a vector store, and users ask questions answered by a local LLM (Ollama) using RAG retrieval.

## Key Decisions

### 1. Framework: SwiftUI + Swift Concurrency

- **SwiftUI** for all UI (macOS 14+ target for NavigationSplitView, modern APIs)
- **Swift Actors** for thread-safe state management
- **async/await** throughout for non-blocking operations
- **AppKit bridging** only where needed (NSOpenPanel for folder selection)

### 2. Vector Storage: SQLite + Accelerate Framework

**Decision: Shared SQLite database with folder-level metadata filtering.**

Trade-off analysis:
- *Per-folder databases*: Simpler deletion/reindex (just delete the file), but harder to query across folders, more file management overhead.
- *Shared database with metadata*: Single connection, atomic operations, folder filtering via SQL WHERE clauses, simpler backup. Deletion requires DELETE WHERE folder_id = X.

**Winner: Shared database.** For a local desktop app with moderate data volumes, a single SQLite DB is simpler, more robust, and easier to maintain. Folder isolation is achieved via metadata columns.

**Vector similarity** is computed using Apple's Accelerate/vDSP framework (SIMD-optimized cosine similarity). At local-document scale (tens of thousands of chunks), brute-force similarity search with Accelerate is sub-millisecond on Apple Silicon. No need for HNSW/FAISS complexity.

Storage: GRDB.swift (Swift SQLite wrapper with excellent concurrency support).

### 3. Embedding Model: Ollama Embeddings API

- Use Ollama's `/api/embed` endpoint
- Default embedding model: `nomic-embed-text` (768 dimensions, fast, high quality)
- Configurable in settings
- Embeddings stored as BLOB in SQLite

### 4. LLM: Ollama Chat API

- Use Ollama's `/api/chat` endpoint with streaming
- Default model: `llama3.2` (the user specified `gpt-oss:20b` but that's not a real Ollama model; we'll default to a real model and make it configurable)
- System prompt includes retrieved context chunks
- Streaming responses for fluid UX

### 5. File Parsing

| Format | Parser |
|--------|--------|
| .txt, .md, .csv, .json | Direct UTF-8 string reading |
| .pdf | PDFKit (native macOS) |
| .docx | ZIPFoundation + XML parsing |
| Source code (.swift, .py, .js, .ts, .rs, .go, .java, .c, .cpp, .h, .rb, .sh) | Direct UTF-8 reading |

Extensible via `FileParser` protocol.

### 6. Chunking Strategy

- Recursive text splitting with configurable chunk size (default: 512 tokens / ~2000 chars)
- 10% overlap between chunks
- Preserve paragraph boundaries where possible
- Each chunk stores: text, source file path, folder ID, chunk index, character offset

## Architecture

```
┌─────────────────────────────────────────────┐
│                   SwiftUI                    │
│  ┌──────────┐ ┌──────────┐ ┌──────────────┐ │
│  │ Sidebar  │ │ ChatView │ │SettingsView  │ │
│  └────┬─────┘ └────┬─────┘ └──────┬───────┘ │
│       │             │              │         │
│  ┌────┴─────────────┴──────────────┴───────┐ │
│  │          AppState (@Observable)          │ │
│  └────┬─────────────┬──────────────┬───────┘ │
├───────┼─────────────┼──────────────┼─────────┤
│       │    Services  │              │         │
│  ┌────┴────┐  ┌─────┴─────┐  ┌────┴───────┐ │
│  │Indexing │  │ Retrieval │  │  Ollama    │ │
│  │Engine   │  │ Engine    │  │  Client    │ │
│  └────┬────┘  └─────┬─────┘  └────────────┘ │
│       │             │                        │
│  ┌────┴─────────────┴──────────────────────┐ │
│  │         Database (GRDB + SQLite)         │ │
│  └──────────────────────────────────────────┘ │
│  ┌──────────────────────────────────────────┐ │
│  │      File Parsers (protocol-based)       │ │
│  └──────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

## Data Model

### SQLite Tables

```sql
-- Tracked folders
CREATE TABLE folders (
    id TEXT PRIMARY KEY,          -- UUID
    path TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    status TEXT NOT NULL,          -- ready, indexing, reindexing, failed, unavailable
    file_count INTEGER DEFAULT 0,
    chunk_count INTEGER DEFAULT 0,
    last_indexed_at TEXT,
    error_message TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

-- Document chunks with embeddings
CREATE TABLE chunks (
    id TEXT PRIMARY KEY,           -- UUID
    folder_id TEXT NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
    file_path TEXT NOT NULL,
    file_name TEXT NOT NULL,
    chunk_index INTEGER NOT NULL,
    content TEXT NOT NULL,
    char_offset INTEGER NOT NULL,
    embedding BLOB,                -- Float32 array as raw bytes
    created_at TEXT NOT NULL
);

CREATE INDEX idx_chunks_folder ON chunks(folder_id);

-- Chat history
CREATE TABLE conversations (
    id TEXT PRIMARY KEY,
    title TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE messages (
    id TEXT PRIMARY KEY,
    conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    role TEXT NOT NULL,             -- user, assistant
    content TEXT NOT NULL,
    sources TEXT,                   -- JSON array of source references
    folder_ids TEXT,                -- JSON array of folder IDs queried
    created_at TEXT NOT NULL
);
```

## Folder Lifecycle

```
Add → Indexing → Ready ←→ Reindexing
                   ↓           ↓
                Failed      Failed
                   ↓
               Removed (deleted from DB)
```

- **Add**: User selects folder → row inserted with status=indexing → background indexing starts
- **Indexing**: Parse files → chunk → embed → store. Progress updates via @Observable
- **Ready**: Folder selectable for Q&A. Monitoring for file changes (future feature)
- **Reindex**: Status→reindexing, delete existing chunks, re-run indexing pipeline
- **Remove**: Delete folder row (CASCADE deletes chunks), remove from UI immediately
- **Failed**: Store error message, allow retry (reindex)

## Retrieval Pipeline

1. User enters question with selected folders
2. Embed the question using Ollama embedding model
3. Load all chunk embeddings for selected folders from SQLite
4. Compute cosine similarity using Accelerate/vDSP
5. Take top-K chunks (default K=5, configurable)
6. Build system prompt with retrieved context
7. Stream response from Ollama chat API
8. Display answer with source citations

## UX Structure

### Layout: NavigationSplitView (three-column)

- **Sidebar**: Folder list with status badges, selection checkboxes, "Add Folder" button
- **Content**: Chat interface with question input and streaming answers
- **Detail** (optional inspector): Source references, file previews

### Screens

1. **Main View** — Sidebar + Chat (primary interaction)
2. **Settings** — Model configuration, embedding model, chunk size, Ollama URL
3. **Folder Detail** (sheet/popover) — File list, indexing stats, reindex/remove actions

### Visual Language

- SF Symbols throughout
- System colors with accent color customization
- Vibrancy and translucency where appropriate
- Subtle animations for state transitions
- Native macOS typography (system font, proper hierarchy)
- Proper spacing using Apple's 8pt grid

## Concurrency Model

- `IndexingEngine`: Swift Actor — manages indexing queue, prevents concurrent indexing of same folder
- `OllamaClient`: Sendable struct with async methods
- `DatabaseManager`: Actor wrapping GRDB's DatabasePool for thread-safe access
- `RetrievalEngine`: Struct with async methods, reads from database actor
- UI updates via `@Observable` on `@MainActor`

## Settings

Stored in UserDefaults:
- Ollama base URL (default: http://localhost:11434)
- Chat model name (default: llama3.2)
- Embedding model name (default: nomic-embed-text)
- Chunk size (default: 2000 chars)
- Top-K results (default: 5)
- Temperature (default: 0.7)

## Error States

- Ollama not running → show connection error with "Open Ollama" button
- Model not available → show model pull suggestion
- Folder access denied → show permission error
- Indexing failure → mark folder as failed with error message, allow retry
- Empty folder → mark as ready with 0 chunks, warn user
- Unsupported files → skip with warning in indexing log

## Tech Stack

| Component | Technology |
|-----------|-----------|
| UI | SwiftUI (macOS 14+) |
| Database | GRDB.swift 7.x |
| PDF Parsing | PDFKit (native) |
| DOCX Parsing | ZIPFoundation + Foundation XML |
| Vector Math | Accelerate/vDSP |
| HTTP | URLSession (native) |
| LLM/Embeddings | Ollama REST API |
| Project Gen | XcodeGen |
| Dependency Mgmt | Swift Package Manager |
