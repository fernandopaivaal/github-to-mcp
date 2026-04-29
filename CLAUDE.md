# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Install dependencies (requires Node.js 22+, pnpm 10+)
pnpm install

# Build all packages
pnpm build

# Build a single package
pnpm build:core          # packages/core only
pnpm build:web           # apps/web only

# Watch a single package during development
pnpm --filter @nirholas/github-to-mcp dev

# Start the Next.js web app dev server
pnpm dev

# Run all tests (Vitest)
pnpm test

# Run a single test file
pnpm test packages/core/src/__tests__/github-client.test.ts

# Run tests in watch mode
pnpm test:watch

# Run tests with coverage (70% threshold enforced)
pnpm test:coverage

# Lint (ESLint with TypeScript rules)
pnpm lint

# Type check
pnpm typecheck

# Create a changeset before merging user-facing changes
pnpm changeset
```

## Architecture

This is a **pnpm monorepo** with `apps/*` and `packages/*` as workspace members. Packages are built with `tsup` outputting ESM `.mjs` files.

### Package dependency graph

```
apps/web              → @nirholas/github-to-mcp, @github-to-mcp/openapi-parser
apps/vscode           → @nirholas/github-to-mcp
packages/mcp-server   → @nirholas/github-to-mcp
packages/core         → @github-to-mcp/openapi-parser
packages/registry     → (standalone)
packages/openapi-parser → (standalone)
```

### `packages/core` — the conversion engine

`GithubToMcpGenerator` in `src/index.ts` orchestrates the full pipeline:

1. **Fetch** — `GithubClient` (Octokit-based) fetches repo metadata, README, and files. A pluggable `CacheAdapter` (`src/cache/`) backs responses; Redis/Upstash adapters are provided for production.
2. **Classify** — heuristic keyword scan of README sets `RepoType` (`api-sdk`, `mcp-server`, `cli-tool`, `library`, `documentation`, `data`, `unknown`) and a 0–1 confidence score.
3. **Extract** — multiple independent extractors run and their results are merged:
   - `ReadmeExtractor` — parses code blocks and CLI patterns from Markdown.
   - `CodeExtractor` — TypeScript/JS/Python AST scanning for exported functions and decorators.
   - `GraphQLExtractor` — parses `.graphql`/`.gql` schemas into MCP tools.
   - `McpIntrospector` — detects existing MCP server tool registrations in source files.
   - `extractFromOpenApi` — delegates to `@github-to-mcp/openapi-parser`.
   - Language-specific extractors: `RustExtractor`, `GoExtractor`, `JavaExtractor` in `src/extractors/`.
   - Universal fallback tools (`get_readme`, `list_files`, `read_file`, `search_code`) are always appended.
4. **Deduplicate** — tools with the same name are merged; priority order is `mcp-introspect > openapi > graphql > code > readme > universal`.
5. **Generate** — `generateCode()` emits a TypeScript MCP server; `PythonGenerator` and `GoGenerator` handle alternate language outputs.

The `StreamingGenerator` in `src/streaming.ts` wraps this pipeline and emits typed `StreamEvent` objects (`start`, `metadata`, `classifying`, `classified`, `extracting`, `tool-found`, `source-complete`, `generating`, `complete`, `error`, `progress`) for real-time UI updates.

**Plugin system** (`src/plugins/`): Third-party extractors implement `ExtractorPlugin` (detect + extract methods, lifecycle hooks). `PluginManager` runs them alongside built-in extractors.

**Multi-provider support** (`src/providers/`): `BaseProvider` interface is implemented by `GitHubProviderAdapter`, `GitLabClient`, and `BitbucketClient`. `ProviderFactory.getProviderFromUrl()` auto-detects the correct provider.

### `packages/openapi-parser`

Converts OpenAPI 2/3, AsyncAPI, GraphQL SDL, Postman collections, Insomnia workspaces, HAR, and gRPC specs into `McpToolDefinition[]`. Key classes: `OpenApiToMcp` (convert/getMcpTools/generateCode), `RefResolver` for `$ref` resolution, and per-framework analyzers (`ExpressAnalyzer`, `FastAPIAnalyzer`, `NextJSAnalyzer`) that reverse-engineer OpenAPI specs from source code.

### `packages/mcp-server`

Wraps the conversion engine as an MCP server itself (runs via `npx @github-to-mcp/mcp-server`). Tools: `convert_repo`, `list_extracted_tools`, `generate_openapi`, `stream_convert`, `export_docker`, `list_providers`, `test_mcp_tool`, `monitor_mcp_server`. Also exposes MCP prompts via `src/prompts/index.ts`.

### `packages/registry`

A standalone registry (`McpRegistry`) for storing and querying conversion results. Ships with pre-baked popular entries (Stripe, Slack, Notion, etc.) in `src/popular/`. Supports pluggable `StorageAdapter` (file or memory).

### `apps/web`

Next.js 14 App Router application. API routes in `app/api/`:
- `POST /api/convert` — one-shot conversion.
- `GET /api/stream` — Server-Sent Events streaming conversion (consumed by `useStreaming` hook and `StreamingProgress` component).
- `POST /api/generate-openapi` — reverse-engineer OpenAPI from a code repo.

Custom hooks in `hooks/` (`useStreaming`, `useBatchConversion`, `usePlatformDetection`, `useDockerConfig`) own all async state. UI components in `components/ui/` are Radix UI primitives styled with Tailwind. Animations use Framer Motion. Design system: black/white monochrome palette, Inter font, glass-morphism cards.

### `apps/vscode`

VS Code extension. Commands in `src/commands/` (convert, validate, browse registry, configure Claude Desktop). Tree views and webviews in `src/views/` and `src/webviews/`.

## Key Conventions

- **TypeScript strict mode** throughout; no `any` (use `unknown`). Public function return types are explicit.
- **ESM only** — all packages use `"type": "module"` and `tsup` outputs `.mjs`.
- **File naming**: kebab-case files, PascalCase components, camelCase functions, `UPPER_SNAKE` constants.
- **Tests** live next to source as `module.test.ts`; root `vitest.config.ts` picks them up from `packages/*/src/**/*.test.ts` and `tests/**/*.test.ts`. Coverage threshold is 70% across branches/functions/lines/statements.
- **Pre-commit hook** (Husky) runs `lint-staged`: ESLint on `.ts`/`.tsx`, Prettier on JSON/Markdown/YAML.
- **Commit messages** follow Conventional Commits (`feat(scope): subject`).
- **Changesets** (`pnpm changeset`) are required for any user-facing change before merging.
- `GITHUB_TOKEN` env var raises GitHub API rate limit from 60/hr to 5,000/hr; copy `.env.example` to `.env` to set it locally.
- Web components must be `'use client'` when they use hooks or browser APIs.
