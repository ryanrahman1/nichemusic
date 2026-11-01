# Niche Music

Niche Music is a cross-platform music discovery and social platform I founded and developed. It combines music discovery, social features, real-time messaging, multiplayer music games, and an editorial publication into one platform.

This repository contains the source code for the applications and services I've built for Niche Music. I've organized the previously separate repositories into one location for my portfolio, preserving their development histories.

## Project Overview

I started building Niche because I wanted a platform where people could discover lesser-known artists, share music with friends, and engage with independent music beyond traditional streaming platforms.

Since then, Niche has grown to over 600 users across more than 20 countries, with a six-person team producing editorial content and managing the platform.

I serve as the founder, lead engineer, and creative director. I independently programmed the platform's backend, frontend, and core features, and I create the majority of its published editorials.

## Repository Structure

```text
niche-music-maker-portfolio/
├── backend/       # Fastify API and backend services
├── ios/           # SwiftUI iOS application
├── editorial/     # Next.js editorial website and CMS
└── README.md
```

The codebases were originally developed in separate repositories and combined here for easier review.

## Technical Architecture

Niche's applications communicate with a shared backend rather than maintaining separate implementations of the same application logic.

| Component | Technologies | Purpose |
|---|---|---|
| Backend | Node.js, TypeScript, Fastify | REST API, authentication, real-time communication, and application logic |
| Database | Supabase PostgreSQL | Application data, authentication records, and custom database functions |
| Real-time systems | WebSockets | Messaging and multiplayer game events |
| Media storage | Cloudflare R2 | Images, videos, and other media assets |
| iOS application | Swift, SwiftUI | Native mobile client |
| Editorial platform | Next.js, Tiptap | Publishing, rich-text editing, and editorial management |

### Authentication

I implemented my own session-based authentication system rather than relying on a prebuilt authentication provider.

Sessions are stored and validated on the backend, allowing access to be revoked without waiting for a stateless token to expire. I separated authentication records from public application data using an isolated PostgreSQL schema.

### Real-Time Messaging

I built a messaging system that supports conversations, replies, music sharing, and notifications.

Messages are validated and stored in PostgreSQL before being broadcast through WebSockets. Client-generated identifiers help prevent duplicate messages when requests are retried, and events are broadcast to conversation members, including the sender, to support synchronization across devices.

### Aux Battle

Aux Battle is a multiplayer music game where players submit songs based on a prompt, compete in tournament brackets, and vote on matchups.

I developed its backend game logic, including room creation, player management, bracket generation, voting, and game progression.

The server validates game actions and stores the current state in PostgreSQL. WebSockets distribute updates to connected players, while room-state snapshots help clients synchronize when joining.

I also built a standalone HTML test client to simulate games with multiple accounts, inspect API responses, and monitor WebSocket events during development.

### Niche Editorial Creator

Originally, publishing an editorial required me to manually code its layout.

To make this process easier for our team, I built a visual editorial creator using Tiptap for rich-text editing and a custom modular block system for organizing article sections.

The block system supports reusable layouts and different editorial formats, allowing our team to create articles without manually coding each page.

## Development Process

Niche went through several major design and engineering iterations.

I began designing the interface in Canva in November 2025, moved to Figma for subsequent prototypes, and released the first version of the app in April 2026.

As the platform evolved, I redesigned its interfaces, expanded the backend, and developed additional features to support different clients and workflows.

Some of the most significant challenges involved organizing a shared backend for multiple platforms, managing session-based authentication, and keeping real-time features synchronized.

The accompanying portfolio contains screenshots of early prototypes, design iterations, architecture, code excerpts, and development testing.

## My Contributions and Collaborators

I independently developed Niche's application code, backend infrastructure, database architecture, authentication, real-time systems, and core interfaces.

James Woo, our design lead, contributed to the initial UI design of Niche's first version and has provided feedback on subsequent designs. I independently designed and implemented later iterations.

Our six-person team also contributes to editorial writing, content creation, design, and marketing. I personally create the majority of our published editorials.

## External Tools and Services

Niche uses established libraries and infrastructure, including Fastify, Next.js, Tiptap, PostgreSQL, Supabase, and Cloudflare R2.

These provide frameworks, editing functionality, hosting, database infrastructure, and media storage. The application-specific logic and systems described above were implemented by me.

I have occasionally used Cursor's AI features to assist with debugging and interpreting errors, and ChatGPT to discuss ideas and technical approaches. I reviewed and implemented changes myself.

## Source Code and Demonstration

This repository is provided as supporting source code for my portfolio.

The portfolio includes a short demonstration of the working application, covering its social features, real-time messaging, Aux Battle, and Editorial Creator.

Some components require environment variables, external services, and credentials that are intentionally excluded from this public repository.

## Development History

The repositories were originally maintained separately and later combined into this repository for portfolio review. Their Git histories have been preserved to document the development process.

## License

No open-source license is granted for this repository. All rights reserved unless otherwise noted.
