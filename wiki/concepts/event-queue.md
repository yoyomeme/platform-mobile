# Event Queue (Redpanda / Kafka)

> Huly's asynchronous backbone: a Kafka-compatible **Redpanda** event bus where the transactor and workspace services **produce** transaction/lifecycle events that fulltext, media, process, github, and mail services **consume** — wired through `QUEUE_CONFIG` and the `PlatformQueue` abstraction.

## Where in code

| Component | File | Purpose |
|-----------|------|---------|
| Queue interfaces | `foundations/server/packages/core/src/queue/types.ts` | `PlatformQueue`, `QueueTopic`, producer/consumer contracts |
| Kafka implementation | `foundations/server/packages/kafka/src/index.ts` | `parseQueueConfig`, `getPlatformQueue`, Kafka producer/consumer |
| Tx producer (transactor) | `foundations/server/packages/middleware/src/queue.ts` | `QueueMiddleware` sends every broadcast tx to `tx` topic |
| Workspace/user producers | `foundations/server/packages/server/src/sessionManager.ts` | `workspace` + `users` topic producers |
| Fulltext consumers | `pods/fulltext/src/manager.ts` | consumes `tx`, `fulltext`, `workspace` topics |
| Datalake producer | `services/datalake/pod-datalake/src/server.ts` | `getProducer(..., QueueTopic.Tx)` |
| Mail queue | `services/mail/mail-common/src/queue.ts` | mail service consumer |

## Purpose

Some work must happen as a side effect of a data change but must not block the user's write: indexing for search, extracting text from uploaded files, running automation, mirroring to GitHub, sending mail. Doing these synchronously inside the transactor would couple unrelated services and slow every transaction.

Instead the transactor **publishes** every committed transaction onto a durable Kafka topic and returns immediately. Independent consumer services read the stream at their own pace, with retries and dead-letter handling. This is the classic event-sourced fan-out: one producer, many decoupled consumers, replayable history.

## Details

### Topics — `QueueTopic`

```typescript
export enum QueueTopic {
  Tx = 'tx',                       // workspace transactions (partitioned)
  Workspace = 'workspace',         // workspace lifecycle info
  Fulltext = 'fulltext',           // fulltext-private: reindex requests etc.
  Users = 'users',                 // user activity
  TelegramBot = 'telegramBot',
  CalendarEventCUD = 'calendarEventCUD',
  Process = 'process',             // process/automation events
  TimeMachine = 'timeMachine'
}
```

The `tx` topic is the heart of the system: it carries every committed transaction, **partitioned** so a workspace's transactions stay ordered while different workspaces parallelize.

### Configuration — `QUEUE_CONFIG`

The bus is configured by one env var, parsed into brokers + a topic name-spacing scheme:

```typescript
// 'brokers;postfix' — brokers comma-separated
export function parseQueueConfig (config: string, serviceId: string, region: string): QueueConfig {
  const [brokers, postfix] = config.split(';')
  return { brokers: brokers.split(','), postfix: postfix ?? '', region, ... }
}

export function getPlatformQueue (serviceId: string, region?: string): PlatformQueue {
  const queueConfig = process.env.QUEUE_CONFIG ?? 'huly.local:9092'
  const config = parseQueueConfig(queueConfig, serviceId, region ?? process.env.REGION ?? '')
  return createPlatformQueue(config)
}
```

Topics are **region-prefixed** so multiple deployments can share one broker cluster:

```typescript
// effective topic name
`${config.region}.${topic}${config.postfix ?? ''}`   // e.g. "cockroach.tx"
```

In the reference compose, `QUEUE_CONFIG = cockroach|http://redpanda:9092` and `REGION = cockroach`, so the live transaction topic is effectively `cockroach.tx`.

### The `PlatformQueue` abstraction

Services never touch Kafka directly; they go through `PlatformQueue`:

```typescript
export interface PlatformQueue {
  getProducer: <T>(ctx: MeasureContext, topic: QueueTopic | string) => PlatformQueueProducer<T>
  createConsumer: <T>(
    ctx: MeasureContext,
    topic: QueueTopic | string,
    groupId: string,
    onMessage: (ctx, msg: ConsumerMessage<T>, queue: ConsumerControl) => Promise<void>,
    options?: { fromBegining?: boolean, retryDelay?: number, maxRetryDelay?: number }
  ) => ConsumerHandle
  createTopics: (tx: number) => Promise<void>   // tx = partition count for the tx topic
  // ...
}

export interface PlatformQueueProducer<T> {
  send: (ctx, workspace: WorkspaceUuid, msgs: T[], partitionKey?: string) => Promise<void>
  // ...
}

export interface ConsumerMessage<T> { workspace: WorkspaceUuid, value: T }
export interface ConsumerControl { pause: () => void, heartbeat: () => Promise<void> }
```

Every message is keyed by `workspace` (the Kafka partition key defaults to the workspace uuid), preserving per-workspace ordering. A `DummyQueue` (`queue/dummyQueue.ts`) implements the same interface for single-process/test runs without Redpanda.

### Producers

| Producer | Topic | Source |
|----------|-------|--------|
| **transactor** | `tx` | `QueueMiddleware` — every broadcast transaction |
| **transactor** | `workspace`, `users` | `sessionManager` — open/close + user-activity events |
| **datalake** | `tx` | blob events emitted as transactions |

The transactor's `QueueMiddleware` publishes on every broadcast — the same transactions it pushes to live WebSocket clients also go onto the bus:

```typescript
async handleBroadcast (ctx: MeasureContext<SessionData>): Promise<void> {
  await Promise.all([
    this.provideBroadcast(ctx),                       // → WebSocket clients
    this.txProducer.send(                             // → Kafka 'tx' topic
      ctx,
      this.context.workspace.uuid,
      ctx.contextData.broadcast.txes
        .concat(ctx.contextData.broadcast.queue)
        .map((tx) => ({ ...tx, meta: { ... } }))
    )
  ])
}
```

The session manager opens workspace/user producers at startup:

```typescript
this.workspaceProducer = this.queue.getProducer(ctx.newChild('ws-queue', {}, { span: false }), QueueTopic.Workspace)
this.usersProducer    = this.queue.getProducer(ctx.newChild('user-queue', {}, { span: false }), QueueTopic.Users)
// ...
await this.workspaceProducer.send(ctx, workspaceUuid, [workspaceEvents.open()])
```

### Consumers

Consumers join a **consumer group** (`groupId`) so the partitions of a topic are balanced across instances. The fulltext service is the canonical consumer — it subscribes to three topics at once:

```typescript
this.workspaceConsumer = queue.createConsumer<QueueWorkspaceMessage>(
  ctx, QueueTopic.Workspace, queue.getClientId(),
  async (ctx, msg, control) => this.processWorkspaceEvent(ctx, msg, control))

this.fulltextConsumer = queue.createConsumer<QueueWorkspaceMessage>(
  ctx, QueueTopic.Fulltext, queue.getClientId(),
  async (ctx, msg, control) => this.processFulltextEvent(msg, control))

this.txConsumer = queue.createConsumer<TxCUD<Doc> | TxDomainEvent<QueueSourced<Event>>>(
  ctx, QueueTopic.Tx, queue.getClientId(),
  async (ctx, msg, control) => this.processTransactions(msg, control))

this.txDeadLetterProducer = queue.getProducer(ctx, getDeadletterTopic(QueueTopic.Tx))
```

Note the `tx` payload type: `TxCUD<Doc> | TxDomainEvent<QueueSourced<Event>>` — fulltext sees both ordinary create/update/delete transactions **and** wrapped communication events (chat messages), because the communication subsystem rides the same `tx` topic (see [communication](communication.md)). Failed messages are routed to a **dead-letter** topic (`getDeadletterTopic(QueueTopic.Tx)`) rather than blocking the stream.

| Consumer | Topics | Reacts by |
|----------|--------|-----------|
| **fulltext** (`:4702`) | `tx`, `fulltext`, `workspace` | index docs/messages, reindex |
| **media** | media/tx | transcode video/audio |
| **process** | `process`, `tx` | run automation workflows |
| **github** | `tx` | mirror issues/PRs |
| **mail** | mail topics | deliver/ingest email |
| **hulygun** | `tx` (all) | general event processing |

### End-to-end picture

```
  PRODUCERS                 BUS (Redpanda :9092)             CONSUMERS
  ─────────                 ────────────────────             ─────────
  transactor ─ tx ─────────▶  cockroach.tx (partitioned) ──▶ fulltext  (index)
  transactor ─ workspace ──▶  cockroach.workspace ─────────▶ media     (transcode)
  transactor ─ users ──────▶  cockroach.users ─────────────▶ process   (automation)
  datalake   ─ tx ─────────▶                              ──▶ github / mail / hulygun
                              cockroach.fulltext (private) ◀─ fulltext (reindex reqs)
                              ...tx-deadletter ◀──────────── failed messages
  QUEUE_CONFIG = cockroach|http://redpanda:9092   (region prefix + brokers)
```

### Key properties

| Property | Value | Description |
|----------|-------|-------------|
| Broker | Redpanda (Kafka API) | `:9092` / `:19092` |
| Partition key | workspace uuid | per-workspace ordering |
| Topic naming | `{region}.{topic}{postfix}` | shared-cluster isolation |
| Config | `QUEUE_CONFIG` = `brokers;postfix` | parsed by `parseQueueConfig` |
| Failure handling | dead-letter topic + retry | `retryDelay`/`maxRetryDelay` |
| Test/dev | `DummyQueue` | same interface, no broker |

## Cross-references

- [fulltext-search](fulltext-search.md) — the primary `tx` consumer
- [communication](communication.md) — chat events ride the `tx` topic as `TxDomainEvent`
- [storage-blobs](storage-blobs.md) — datalake also produces to `tx`
- Service: [transactor](../services/transactor.md), [fulltext-service](../services/fulltext-service.md)

## Gotchas

- **Topic names are region-prefixed.** The literal topic is `tx`, but the broker topic is `{region}.tx` (e.g. `cockroach.tx`). Tools that subscribe directly must use the prefixed name.
- **Mobile clients never touch the queue.** Live updates reach clients over the transactor WebSocket; the queue is server-internal. Don't try to consume Kafka from a client.
- **The `tx` topic carries two payload shapes.** Plain `TxCUD<Doc>` and wrapped `TxDomainEvent<...Event>` (communication). Consumers must branch on the type.
- **Ordering is per-partition (per-workspace) only.** There is no global order across workspaces.
- **Dead-letter, not silent drop.** A consumer that throws sends the message to the dead-letter topic; monitor it — failures are not lost but also not retried forever in place.
- **`DummyQueue` means no fan-out.** Running without Redpanda (dev) disables async consumers like indexing; search will be stale.
