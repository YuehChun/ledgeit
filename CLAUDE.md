# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

"Amin" (امين) — an AI assistant for banking, travel, and financial tasks. The project is a multi-service monorepo with two main components:

- **Python AI Backend** (`old-ai/`) — LangGraph-based agent with Flask/gRPC interfaces
- **Next.js Frontend** (`old-ai/agent-entrypoint/`) — conversational travel planning UI

## Commands

### Docker (full stack, from `old-ai/`)
```bash
make up          # docker-compose down + up --build -d
make down        # stop all services
make restart     # down + up
make logs        # tail all service logs
make status      # docker-compose ps
make clean       # down -v + prune

# Dev with hot reload
./dev.sh dev     # start with dev overrides
./dev.sh restart # restart app-grpc only
./dev.sh logs    # view logs
./dev.sh shell   # shell into container
```

### Python Backend (from `old-ai/`)
```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python app.py          # Flask REST at :5035
python app-grpc.py     # gRPC at :50051
python mock-backend.py # Mock backend
./compile_proto.sh     # Regenerate proto stubs
```

### Next.js Frontend (from `old-ai/agent-entrypoint/`)
```bash
pnpm install
pnpm dev               # dev server at :3000
pnpm build             # production build
pnpm worker            # main task worker
pnpm worker:email      # email parser worker
pnpm worker:followup   # follow-up worker
```

### Testing (from `old-ai/agent-entrypoint/`)
```bash
pnpm test:smoke              # fast smoke test (~30s)
pnpm test:regression         # basic regression (~8s)
pnpm test:regression:full    # full suite with workers + wallet
pnpm test:almosafer          # Almosafer E2E
pnpm test:hotel-search       # hotel search + AI scoring
pnpm test:negotiation        # email negotiation flow
pnpm test:booking-flow       # selection → booking → payment
pnpm test:wallet             # wallet integration
pnpm test:auth-flow          # onboarding + wallet setup
```

### Database Migrations (from `old-ai/agent-entrypoint/`)
```bash
pnpm migrate:all             # run all migrations
pnpm migrate:supabase        # Supabase-specific migrations
```

## Architecture

```
agent-entrypoint (Next.js :3001→:3000)
    │ HTTP/WebSocket
    ▼
mock-backend (Flask/SocketIO :15013→:8000, gRPC :40052→:50052)
    │ gRPC
    ▼
app-grpc (Python LangGraph AI :8000→:50051)
    ├── Redis (:6379)
    └── payment-api (Playwright booking :443→:8080)
```

All services run on Docker network `amin-network`.

### Communication Rule (enforced)
Services MUST NOT communicate directly with frontend. All frontend notifications must go through mock-backend via HTTP POST to `/FBB/notification`, which then broadcasts via Socket.IO WebSocket. See `app-grpc.py::_notify_mock_backend()` for the reference implementation.

### AI Agent Architecture
- **LangGraph state machines** define conversation flows (`graph.py` ~142K)
- **Multi-level intent classification** using YAML configs (`config/journey_types.yaml`, `config/levels.yaml`)
- **Tool nodes** for domain actions: bank, hotel, flight, shopping (in `tools/`)
- **Service subgraphs** for specific journeys: hotel, shopping, bank (in `services/`)

### Frontend Architecture
- Next.js 15 App Router with route groups (`app/(app)/` for authenticated pages)
- API routes under `app/api/` (chat, bookings, wallet, etc.)
- shadcn/ui components (new-york style, neutral base) in `components/ui/`
- Background workers in `lib/workers/` (task, email-parser, follow-up)
- External API integrations in `lib/services/` (Almosafer, Amadeus, Lago, Mamopay)
- Supabase for auth + data; path alias `@/*` maps to project root

## Code Conventions

- **ALL code, comments, docstrings, prompts, variables, and error messages MUST be in English** — no Chinese characters in code files
- Python: PEP 8 naming conventions
- Frontend: TypeScript strict mode, Tailwind CSS v4, pnpm as package manager
- ESLint and TypeScript errors are ignored during `next build` (configured in `next.config.mjs`)

## Key Dependencies

**Python**: langchain, langgraph, langsmith, flask, flask-restx, grpcio, redis, supabase, playwright, boto3 (AWS SSM for secrets)

**Frontend**: next 15, react 19, @supabase/ssr, shadcn/ui (radix-ui), tailwindcss v4, framer-motion, zod, recharts, jest
