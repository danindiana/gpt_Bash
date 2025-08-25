Complete Ollama Document Processing Suite

🔧 Main Tools & Repositories Found:

Robert McDermott's Batch Processing Cluster - High-performance multi-GPU batch processing
Simple ollama-batch tool GitHubApidog - Easy directory-based processing
Ollama-OCR GitHubGitHub - Vision model processing for PDFs/images
Official Ollama Python library GitHub - ollama/ollama-python: Ollama Python library - Core API wrapper

📁 What I Created:
1. Main Document Processor Suite - A bash-friendly system that:

Automatically detects and processes various document formats
Uses multiple GPUs efficiently
Handles text, PDF, DOCX, images, and more
Provides configurable prompts and models
Includes batch processing capabilities

2. T3600-Specific Optimization - Tailored for your exact hardware:

GTX 1060 6GB: Optimized for fast, smaller models (llama3.2:3b, phi3:mini)
Quadro P4000 8GB: Handles larger models (qwen2.5:7b, codellama:7b)
Dual-GPU processing: Runs both simultaneously for maximum throughput
Memory management: Optimized for your 64GB RAM

🚀 Key Features:

Automatic setup: Installs all dependencies and tools
GPU management: Start/stop servers per GPU with load balancing
Document format support: Text, PDF, DOCX, images, code files
Async processing: Maximum performance with controlled concurrency
Performance monitoring: Real-time system and GPU monitoring
Multiple processing modes: Simple batch, advanced clustering, vision OCR

💻 Usage Examples:
bash# Quick setup
chmod +x ollama_document_processor_suite.sh
./ollama_document_processor_suite.sh

# T3600 specific optimization
chmod +x t3600_optimized_setup.sh
./t3600_optimized_setup.sh
🎯 Recommended Workflow for Your T3600:

Initial Setup: Run the T3600 optimization script first
Start Dual GPUs: Use the launcher to start both GPU servers

RetryContinueEdit🎯 Recommended Workflow for Your T3600:

Initial Setup: Run the T3600 optimization script first
Start Dual GPUs: Use the launcher to start both GPU servers
Process Documents: Use the dual-GPU processor for maximum performance
Monitor Performance: Track GPU utilization and processing speed

📊 Performance Expectations on Your Hardware:
Based on Robert McDermott's testing with similar setups Batching support in Ollama · Issue #2301 · ollama/ollama:

Small models (GTX 1060): ~50-100 documents/hour
Medium models (P4000): ~20-50 documents/hour
Combined processing: Up to 2-3x faster than single GPU
Large batches: Nearly 100,000 prompts per hour with simple models Large Scale Batch Processing with Ollama | by Robert McDermott | Medium

🛠️ Additional Tools Included:
From Research:

Robert McDermott's cluster scripts for enterprise-scale processing
Automated Ollama management for model deployment
LangChain integration ollama-python/ollama/_client.py at main · ollama/ollama-python for RAG workflows

Custom Utilities:

Result merger (JSON/CSV output)
Performance monitoring dashboard
Model optimization recommendations
Error handling and retry logic

🔧 Installation Steps:
bash# 1. Download the scripts
wget <script_urls> # (or copy from artifacts above)

# 2. Make executable
chmod +x *.sh

# 3. Run T3600 setup (handles everything)
./t3600_optimized_setup.sh

# 4. Choose option 9: "Complete automated setup"
# This will:
# - Install CUDA drivers
# - Configure dual GPUs
# - Install Ollama + Python dependencies
# - Pull recommended models
# - Create all launcher scripts
📝 Example Usage:
bash# Start dual GPU servers
./start_dual_gpu.sh

# Process documents with both GPUs
python3 t3600_document_processor.py \
  ./input_documents \
  ./processed_output \
  --prompt "Summarize this document and extract key insights"

# Monitor performance
./monitor_t3600.sh

# Stop servers when done
./stop_dual_gpu.sh
🎯 Best Practices for Your Setup:

Model Selection:

GTX 1060: Use 3B-4B parameter models
P4000: Use 7B-8B parameter models
Vision tasks: Use llama3.2-vision:11b across both GPUs


Batch Sizes:

Start with batches of 10-20 documents
Monitor GPU memory usage
Adjust based on document size


Performance Optimization:

Use SSD storage for fast document access
Keep models loaded between batches
Monitor temperatures and adjust fan curves



🚀 Advanced Features:

Multi-format support: Handles PDFs, DOCX, images, code files automatically
OCR integration: Uses Ollama vision models for image text extraction GitHub - imanoop7/Ollama-OCR
Structured output: JSON, CSV, or markdown formatting
Error recovery: Automatic retries and graceful failure handling
Scaling: Can expand to multiple T3600 systems easily

This solution combines the best tools I found with custom optimizations for your specific hardware. The T3600 with its dual GPUs and 64GB RAM is perfect for this kind of parallel document processing workflow.
