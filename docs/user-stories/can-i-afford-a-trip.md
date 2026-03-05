# Can I Afford a Trip?

> **As a user**, I want to ask my finance app natural language questions about my spending and get intelligent answers based on my actual transaction data, so I can make informed financial decisions.

![AI Advisory Chat](../../screenshots/ai_advisor_chatting.png)

## The Problem

You're thinking about booking a trip, but you're not sure if you can afford it. You'd need to check your current balance, upcoming bills, recent spending trends, and savings goals — then do the math yourself. What if you could just ask?

## How LedgeIt Solves It

The **AI Advisory** chat lets you ask questions in plain language. In this example, the user asks "How much can I spend on my next trip?" and the AI:

1. **Checks your financial situation** — current spending, upcoming payments, savings goals
2. **Identifies concerns** — 3 overdue bills totaling NT$14,684, no income recorded this month, active savings goals
3. **Gives honest advice** — "I would strongly recommend postponing your trip" with specific reasons
4. **Provides actionable steps** — Pay off overdue bills first, investigate suspicious charges, work on accepted goals

## How It Works Under the Hood

- **Local RAG** — Your transaction data is indexed with multilingual embeddings (E5-small) and FTS5 full-text search
- **Hybrid Search** — Combines semantic vector search with keyword matching for accurate retrieval
- **Cross-Language** — Ask in Chinese, find English transactions (and vice versa). "寶可夢" finds "Pokemon GO" purchases
- **Tool Calling** — The AI has access to 8 tools: transaction search, category breakdown, upcoming payments, goals, and more
- **Streaming** — Responses stream in real-time so you see the answer forming as the AI thinks

## Example Questions

- "How much did I spend on Pokemon GO?" (cross-language: Chinese query finds English data)
- "When is my next credit card payment due?"
- "What was my biggest expense last month?"
- "How much did I spend at Starbucks?"
- "What category am I overspending in?"
