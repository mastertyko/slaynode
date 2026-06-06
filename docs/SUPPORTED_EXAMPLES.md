# Supported Examples

SlayNode does not rely on one framework-specific integration. It combines command parsing, process discovery, Docker/Homebrew discovery, and workspace heuristics. This page gives concrete examples of the service shapes the app is designed to recognize today.

## Local Process Runtimes

- `npm run dev`, `pnpm dev`, `yarn dev`, and `bun run dev` wrappers that launch a framework child process.
- Direct framework commands such as `vite`, `next dev`, `nuxt dev`, `webpack serve`, and `storybook dev`.
- TypeScript runner flows such as `tsx server.ts`, `tsx watch src/index.ts`, and `bun --watch server.ts`.
- Deno and Bun server patterns with explicit ports, such as `deno serve --listen 0.0.0.0:8787` and `bun run --hot server.ts`.
- Backend-style runtimes that expose ports through command flags, environment assignments, or listening sockets.

## Workspace Resolution

- Standard project roots such as `/Users/you/project`.
- Node workspace paths under `node_modules/.bin` or `node_modules/<tool>` that should collapse back to the owning project root.
- Package-manager wrapper processes where the child runtime owns the useful command or port signal.
- Docker bind mounts that point at real project directories rather than sockets or loose files.

## Docker Services

- Containers exposed through `docker ps`, including host-port ranges such as `0.0.0.0:3000-3002->3000-3002/tcp`.
- Containers with bind-mounted project directories, where SlayNode can offer `Open Workspace`.
- Containers in healthy, unhealthy, paused, or health-check-starting states.
- Common infrastructure images such as Redis, Postgres, Nginx, and generic web/API containers.

## Homebrew Services

- Services returned by `brew services list --json` with started, running, scheduled, stopped, or error states.
- Brew services with valid plist paths, where SlayNode can offer `Reveal Config`.
- Brew services without a usable plist path, where SlayNode intentionally hides config actions instead of pointing to a dead file.

## What To Expect

- Commands shown in the UI are redacted before display or copy.
- Port badges may be either live socket evidence or likely hints inferred from tooling defaults.
- `Slay` targets the selected process group, not just the top-level pid text shown in the list.
- Some services remain visible even without a resolved port when the framework signature is still strong enough to be useful.

## Good Bug Reports

When a real service is missing or misclassified, include:

- The launch command you used.
- Whether it was a local process, Docker container, or Homebrew service.
- The working directory or bind mount shape.
- The port you expected to see.
- Whether the app showed nothing, the wrong name/kind, or the wrong action set.
