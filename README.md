# LocalMind

A native macOS desktop app for local, privacy-preserving document Q&A using RAG (Retrieval-Augmented Generation).

## What It Does

LocalMind lets you index local folders and ask questions about their contents. It uses a local LLM (Ollama) to understand your documents and provide contextual answers — all without sending your data to the cloud.

## Features

- **Folder Indexing**: Add local folders and index their contents into a searchable vector store
- **Semantic Search**: Find relevant content using embeddings rather than just keywords
- **Chat Interface**: Ask questions and get answers with source citations
- **Local & Private**: Everything runs locally on your Mac — no cloud dependencies
- **Multi-format Support**:
  - Plain text (.txt, .md, .csv, .json)
  - PDF documents
  - Word documents (.docx)
  - Source code (.swift, .py, .js, .ts, .rs, .go, .java, .c, .cpp, .rb, .sh)
- **Streaming Responses**: Real-time streaming from the LLM for a fluid experience
- **Conversation History**: Save and revisit previous Q&A sessions

## Tech Stack

| Component | Technology |
|-----------|-----------|
| UI Framework | SwiftUI (macOS 14+) |
| Language | Swift 6.0 |
| Database | GRDB.swift (SQLite) |
| PDF Parsing | PDFKit (native) |
| DOCX Parsing | ZIPFoundation + Foundation XML |
| Vector Similarity | Accelerate/vDSP |
| LLM & Embeddings | Ollama REST API |
| Build System | XcodeGen |

## Requirements

- macOS 14.0 (Sonoma) or later
- [Ollama](https://ollama.ai) installed and running locally

### Required Ollama Models

Pull the following models before using LocalMind:

```bash
# For chat (default: llama3.2)
ollama pull llama3.2

# For embeddings (default: nomic-embed-text)
ollama pull nomic-embed-text
```

## How to Build

1. **Generate the Xcode project** (if needed):
   ```bash
   cd LocalMind
   xcodegen generate
   ```

2. **Generate app icons** (optional - requires Python and Pillow):
   ```bash
   python3 generate_icon.py
   ```

3. **Open in Xcode**:
   ```bash
   open LocalMind.xcodeproj
   ```

4. **Run** (Cmd+R in Xcode) or build from command line:
   ```bash
   xcodebuild -project LocalMind.xcodeproj -scheme LocalMind -configuration Debug build
   ```

The built app will be located at:
- Xcode DerivedData: `~/Library/Developer/Xcode/DerivedData/LocalMind-*/Build/Products/Debug/LocalMind.app`

## How to Use

1. **Start Ollama**: Ensure Ollama is running (`ollama serve`)
2. **Launch LocalMind**: Open the app
3. **Add Folders**: Use File > Add Folder (Cmd+Shift+O) to select folders to index
4. **Wait for Indexing**: Folders will show "Indexing" status until ready
5. **Ask Questions**: Select indexed folders in the sidebar and type your question

## Settings

Configure the app via Settings (Cmd+,):

- **Ollama URL**: Default `http://localhost:11434`
- **Chat Model**: Default `llama3.2`
- **Embedding Model**: Default `nomic-embed-text`
- **Chunk Size**: Default 2000 characters
- **Top-K Results**: Default 5
- **Temperature**: Default 0.7

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
└─────────────────────────────────────────────┘
```

## License

MIT
