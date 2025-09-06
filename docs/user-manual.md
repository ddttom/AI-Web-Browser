# Web Browser User Manual

A privacy-first AI-powered macOS web browser with local AI capabilities and intelligent browsing features.

## Table of Contents

1. [Getting Started](#getting-started)
2. [AI Sidebar](#ai-sidebar)
3. [AI Features](#ai-features)
4. [Privacy & Security](#privacy--security)
5. [Settings & Configuration](#settings--configuration)
6. [Troubleshooting](#troubleshooting)

## Getting Started

### First Launch

When you launch the browser for the first time:

1. **AI Sidebar Automatically Opens** - The AI sidebar will be visible by default to help you get started
2. **Smart AI Detection** - The app automatically detects available AI providers:
   - 🦙 **Ollama running** → Instant 2-second startup with any model
   - 💻 **Apple Silicon** → Downloads MLX model (Gemma 2 2B, ~2GB) if no Ollama
   - ☁️ **API Keys configured** → Uses cloud providers (OpenAI, Claude, Gemini)
3. **Provider Display** - See which AI provider is active in the sidebar header
4. **Ready Indicator** - Wait for the "AI Ready" status (2 seconds with Ollama, 30-60 seconds with MLX)

### System Requirements

**For Built-in MLX AI:**
- **macOS 14.0+** (macOS Sonoma or later)
- **Apple Silicon (M1/M2/M3)** required for MLX
- **4GB+ available storage** for AI model files
- **8GB+ RAM** recommended for smooth operation

**For Ollama AI (Recommended):**
- **macOS 10.15+** (any Mac)
- **Ollama installed** from [ollama.ai](https://ollama.ai)
- **2GB+ per model** (varies by model size)
- **Works on Intel and Apple Silicon**

## AI Sidebar

The AI sidebar is the central hub for all AI-powered features in the browser. It appears as a collapsible panel on the right side of the window.

### Sidebar States

**Collapsed State**
- Shows as a thin 4px line on the right edge
- Hover over the edge to expand
- Click the edge to permanently expand

**Expanded State**
- Full 320px wide sidebar with all AI features
- Contains chat interface, page context, and controls
- Can be collapsed using the `←` button in the header

### Sidebar Components

#### AI Status Indicator
Located in the top-left of the sidebar header:
- **Orange "Starting"** - AI is initializing
- **Blue "Thinking..."** with spinning animation - AI is processing
- **Green "AI Ready"** - Ready for use

#### Provider Display
The sidebar header clearly shows which AI provider and model is active:

**Header Badge:**
- 🦙 **Ollama** (indigo) - Local Ollama service with server.rack icon
- 💻 **MLX** (blue) - Built-in Apple Silicon AI with cpu icon  
- 🧠 **OpenAI** (green) - Cloud API with brain.head.profile icon
- 👤 **Claude** (orange) - Anthropic API with person.crop.circle.fill icon
- 💎 **Gemini** (purple) - Google API with diamond.fill icon

**Model Information Bar:**
- **Model name** - Shows active model (llama3, gemma-2-2b, gpt-4, etc.)
- **Privacy badge** - 🔒 "Private" for local providers, ☁️ "Cloud" for APIs
- **Cost display** - Shows pricing per 1M tokens for paid services

**Interactive Features:**
- **Click badge** to open provider/model switcher dropdown
- **Quick switching** between available providers and models
- **Settings shortcut** for privacy and API key configuration
- **Real-time updates** when providers change or models load

#### TL;DR Card
Automatically appears below the header when browsing:
- **Auto-generates** page summaries as you browse
- **Expandable** - click to see full summary
- **Context-aware** - understands the current page content
- **Streaming** - shows real-time generation with typing indicator

#### Chat Area
The main conversation interface:
- **Message history** - scrollable conversation with AI
- **Typing indicators** - shows when AI is generating responses
- **Message bubbles** - clean, readable format for conversations

#### Input Controls
At the bottom of the sidebar:
- **History toggle** - include/exclude browsing history in AI context
- **Ask/Agent mode toggle** - switch between chat and action modes
- **Privacy settings** - quick access to privacy controls
- **Text input field** - type your questions or commands
- **Send button** - submit messages (or press Enter)

### Keyboard Shortcuts

- `Cmd + Shift + A` - Toggle AI sidebar
- `Cmd + Shift + F` - Focus AI input field
- `Enter` - Send message to AI
- `Esc` - Collapse sidebar (when focused)

## AI Features

### 1. Chat Mode (Ask)

**What it does:** Conversational AI that can answer questions about the current page, your browsing history, or general topics.

**How to use:**
1. Ensure the toggle shows "Ask" mode
2. Type your question in the input field
3. Press Enter or click send
4. Watch the AI generate a response in real-time

**Example queries:**
- "Summarize this article"
- "What are the key points on this page?"
- "Explain this concept in simple terms"
- "What's the main argument of this blog post?"

### 2. Agent Mode (Act)

**What it does:** AI agent that can perform actions on web pages like clicking buttons, filling forms, and navigating websites.

**How to use:**
1. Toggle to "Agent" mode using the Ask/Agent switch
2. Describe what you want the agent to do
3. Watch the agent timeline show step-by-step actions
4. Review results and provide follow-up instructions

**Example commands:**
- "Fill out this form with my information"
- "Click the 'Sign up' button"
- "Find and click the download link"
- "Navigate to the pricing page"

**Agent Timeline Features:**
- **Step-by-step breakdown** - see each action the agent plans to take
- **Real-time updates** - watch progress as actions are performed
- **Action results** - success/failure status for each step
- **Error handling** - descriptive messages when actions fail

### 3. Page Context Understanding

**Automatic Context Extraction:**
- The AI automatically reads and understands the current page content
- **Context indicator** shows when page content is available
- **Word count** displays how much content was extracted
- Updates automatically when navigating to new pages

**Context Controls:**
- **History toggle** - include recent browsing history in AI context
- **Privacy settings** - control what information is shared with AI

### 4. Smart Page Summaries (TL;DR)

**Auto-generation:**
- Automatically creates summaries as you browse
- **Streaming generation** - watch summaries appear in real-time
- **Sentiment analysis** - includes relevant emoji indicators
- **Progressive disclosure** - click to expand/collapse details

**When summaries are generated:**
- New page loads
- Significant content changes
- Manual refresh triggers

### 5. Research & Synthesis

**Multi-page Research:**
The AI can help synthesize information across multiple pages in your browsing session.

**How to use:**
- Browse multiple related pages
- Ask the AI to "compare these articles" or "synthesize the key findings"
- The AI will reference content from your recent browsing history

### 6. Privacy-First AI Processing

**Local AI Processing:**
- **Default mode** - all AI processing happens on your device
- **No data sent to cloud** unless you explicitly enable cloud providers
- **Encrypted conversation storage** - all chat history encrypted locally
- **Automatic data cleanup** - conversations deleted after retention period

**Cloud AI Integration (Optional):**
- **Bring Your Own Key (BYOK)** - use your own API keys
- **Provider choice** - OpenAI, Anthropic, or Google Gemini
- **Granular privacy controls** - choose what data to share
- **Cost tracking** - monitor usage and spending

## Privacy & Security

### Data Protection

**Local Processing**
- AI model runs entirely on your device
- No conversation data sent to external servers
- Page content processed locally

**Conversation Encryption**
- All chat history encrypted with AES-256
- Encryption keys stored securely in macOS Keychain
- Data retention policies configurable (1-30 days)

**Browsing Privacy**
- No telemetry or tracking by default
- Page content only shared with AI when explicitly requested
- History context can be disabled per conversation

### Privacy Settings

Access via the shield icon in the AI sidebar:

**Data Retention**
- Set how long conversations are stored (1-30 days)
- Option to purge all AI conversation data
- Automatic cleanup of expired data

**Cloud Provider Settings** (if enabled)
- API key management
- Data sharing preferences
- Usage and billing controls

**Context Sharing**
- Control what page content is shared with AI
- Toggle browsing history inclusion
- Granular permission controls

## Settings & Configuration

### AI Model Management

**Local Model (Recommended)**
- **Gemma 2 2B (4-bit quantized)** - optimized for Apple Silicon
- **Automatic updates** - model updates downloaded automatically
- **Cache location** - `~/.cache/huggingface/hub/`
- **Manual management** - use provided scripts for troubleshooting

**Local Providers**
- **MLX (Apple Silicon)** - Gemma 2 2B (4-bit quantized), optimized for Apple Silicon
- **Ollama** - Run any supported model locally (llama3, gemma, mistral, codellama, etc.)

**Cloud Providers**
Configure in Privacy Settings:
- **OpenAI** - GPT-3.5, GPT-4, GPT-4 Turbo
- **Anthropic** - Claude 3 (Haiku, Sonnet, Opus)  
- **Google** - Gemini Pro, Gemini Pro Vision

### Performance Optimization

**Memory Management**
- **Tab hibernation** - unused tabs automatically hibernated
- **Smart model loading** - AI model loaded only when needed
- **Efficient caching** - intelligent content caching

**Battery Optimization**
- **Local AI preferred** - reduces network usage
- **Efficient processing** - optimized for Apple Silicon
- **Sleep mode support** - AI pauses when system sleeps

### Ollama Configuration

**Prerequisites**
1. Install Ollama from [ollama.ai](https://ollama.ai)
2. Start the Ollama service: `ollama serve`
3. Download a model: `ollama pull llama3` (or any supported model)

**Setup in Browser**
1. Open **Settings** → **AI Provider**
2. Select **Ollama (Local)** from available providers
3. Configure connection settings:
   - **Host**: Default `127.0.0.1` (localhost)
   - **Port**: Default `11434`
4. Select your preferred model from the dropdown

**Supported Models**
- **Llama 3** (8B, 70B) - General purpose chat and reasoning
- **Code Llama** - Optimized for code generation
- **Gemma** (2B, 7B) - Lightweight and efficient
- **Mistral** (7B) - High performance multilingual
- **Phi-3** - Microsoft's small language model

**Benefits**
- ✅ **Privacy**: All processing stays on your device
- ✅ **No API costs**: Free to use any model
- ✅ **Model flexibility**: Switch between any Ollama-compatible model
- ✅ **Offline capable**: Works without internet connection
- ✅ **Cross-platform**: Runs on Apple Silicon and Intel Macs
- ⚡ **Fast startup**: Auto-detected and prioritized when running

**Smart Initialization**
The browser automatically detects if Ollama is running on startup and will:
1. **Auto-select Ollama** if it's running and available (fast ~2 second startup)
2. **Skip MLX initialization** when Ollama is preferred (saves 30-60 seconds)
3. **Fallback to MLX/cloud** providers if Ollama is not running
4. **Respect user preference** if a specific provider was previously selected

**Troubleshooting Ollama**
- **Connection failed**: Ensure Ollama service is running (`ollama serve`)
- **No models available**: Download models with `ollama pull <model-name>`
- **Slow responses**: Consider using smaller models (2B-7B) for better performance

### Logging & Debugging

**Verbose Logging** (for troubleshooting)
```bash
defaults write com.example.Web App.VerboseLogs -bool YES
```

**Log Categories**
- Essential: Important system messages
- Debug: Detailed operation logs (debug builds only)
- Error: Error messages and warnings

## Troubleshooting

### AI Not Initializing

**Symptoms:** Stuck on "Starting" or "Preparing AI"

**Solutions:**
1. **Check storage space** - ensure 4GB+ available
2. **Restart the application** - force quit and reopen
3. **Clear model cache** - run `./scripts/clear_model.sh`
4. **Re-download model** - run `./scripts/manual_model_download.sh`
5. **Check system requirements** - verify macOS 14+ and Apple Silicon

### AI Responses Slow or Poor Quality

**Solutions:**
1. **Check system resources** - ensure sufficient RAM available
2. **Switch to cloud provider** - for faster responses (requires API key)
3. **Restart application** - refresh AI model state
4. **Check model integrity** - run `./scripts/verify_model.sh`

### Sidebar Not Responding

**Solutions:**
1. **Toggle sidebar** - use Cmd+Shift+A to reset
2. **Focus input field** - use Cmd+Shift+F
3. **Check browser permissions** - verify app has necessary permissions
4. **Restart application** - reset UI state

### Context Not Loading

**Symptoms:** AI doesn't seem to understand current page

**Solutions:**
1. **Wait for context indicator** - look for green "Page context" status
2. **Refresh page** - reload to trigger context extraction
3. **Check page compatibility** - some dynamic sites may not work
4. **Enable JavaScript** - ensure JavaScript is enabled for the site

### Privacy & Data Concerns

**Clear All AI Data**
1. Open Privacy Settings (shield icon)
2. Click "Purge All Data"
3. Confirm deletion

**Reset Encryption Key**
1. Clear all AI data (above)
2. Restart application
3. New encryption key generated automatically

### Performance Issues

**High Memory Usage**
1. **Close unused tabs** - reduce memory overhead
2. **Restart application** - clear memory leaks
3. **Disable history context** - reduce AI memory usage
4. **Switch to cloud AI** - reduce local processing load

**Slow Page Loading**
1. **Check internet connection**
2. **Disable AI features temporarily** - isolate performance issues
3. **Clear browser cache** - reset cached content
4. **Update application** - ensure latest optimizations

### Getting Help

**Built-in Diagnostics**
- Check AI status indicator for current state
- Review conversation history for error messages
- Monitor system resource usage

**Log Files**
- Enable verbose logging for detailed troubleshooting
- Share relevant log entries when reporting issues

**Community Support**
- Check project documentation and issues
- Report bugs with detailed system information
- Include logs and reproduction steps

---

*This user manual covers the core features and functionality of the AI-powered web browser. For technical documentation and development information, see the project's technical documentation.*