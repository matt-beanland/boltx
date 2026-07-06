<!--
SPDX-FileCopyrightText: 2024 bolty contributors
SPDX-License-Identifier: Apache-2.0
-->

# bolty against a Neo4j cluster

bolty can talk to a Neo4j Enterprise **causal cluster** using server-side
routing (SSR): you point a connection at one cluster member with a `neo4j://`
scheme, and the server forwards each statement to the member that can serve it —
a writable member for writes, a read member for reads — based on the query's
access mode. This page covers what SSR does, how to enable it, and the caveats
that matter before you rely on it in production.

> #### Scope {: .info}
>
> SSR gives you correct routing (writes reach a leader, reads reach a read
> member) from a single configured entry point. It is **not** full driver-side
> cluster routing: bolty does not discover the cluster topology, load-balance
> across read replicas, or fail over automatically if the configured member goes
> down. See [Caveats](#caveats) below.

## How it works

Neo4j's `neo4j`/`neo4j+s`/`neo4j+ssc` schemes mean "routed" across the ecosystem,
in contrast to `bolt`/`bolt+s`/`bolt+ssc`, which mean "connect directly to this
one server". The distinction is carried on the wire by a single field in the
Bolt `HELLO` message: when a connection opts into routing, bolty sends
`routing = %{"address" => "<host>:<port>"}` in the `HELLO` extras (Bolt 4.1+).
Its presence tells the server "this is a routed connection, forward my
statements as needed"; its absence means "serve everything here directly".

bolty already sends the two fields the server routes on — `:mode` (`"w"`/`"r"`)
and `:bookmarks` — through every `RUN` and `BEGIN`. SSR simply lets the server
act on them.

## Enabling it

Routing is derived from the scheme, so most setups need nothing extra:

```elixir
# Routed: writes go to a leader, reads to a read member — automatically.
{:ok, conn} =
  Bolty.start_link(
    scheme: "neo4j+s",
    hostname: "cluster-member-1.example.com",
    port: 7687,
    auth: [username: "neo4j", password: System.fetch_env!("NEO4J_PASSWORD")]
  )
```

`neo4j*` schemes enable routing by default; `bolt*` schemes disable it. Override
with the explicit `:routing` option when you need to:

```elixir
# A neo4j:// URI pointed at a single instance or a proxy — opt out of routing.
Bolty.start_link(uri: "neo4j://localhost:7687", routing: false, auth: [...])

# Force routing on a bolt:// scheme (unusual — prefer the neo4j:// scheme).
Bolty.start_link(scheme: "bolt", hostname: "member-1", routing: true, auth: [...])
```

Precedence follows the rest of bolty's config: an explicit `:routing` option wins
over the scheme-derived default.

### Choosing an access mode

Under routing, tag reads so they can be served by a read member instead of
loading the leader:

```elixir
# Routed to a writable member (default).
Bolty.query!(conn, "CREATE (:Person {name: $n})", %{n: "Ada"})

# Routed to a read member.
Bolty.query!(conn, "MATCH (p:Person) RETURN p", %{}, mode: "r")
```

`:mode` and `:bookmarks` are documented on `Bolty.query/4` and
`Bolty.transaction/4`.

## Server prerequisites

- **Neo4j Enterprise Edition** running as a causal cluster. SSR does nothing on
  Community Edition or a standalone server (a routed connection still works — it
  just resolves to that one server).
- Routing must be enabled on the cluster members via `dbms.routing.enabled`.
  Whether that is on by default, and how `dbms.routing.default_router` interacts
  with it, varies by Neo4j version — **verify the defaults for your specific
  Enterprise version** rather than assuming; don't take a value stated here or
  elsewhere as authoritative for your deployment.

## Caveats

Read these before depending on SSR. They are consequences of bolty deliberately
*not* implementing a full routing driver.

- **You are pinned to one member.** The `address` bolty advertises is the single
  member you configured. Writes and uncacheable reads that land on the wrong
  member cost an extra forwarding hop, and there is **no read-replica
  load-balancing or scaling** — every connection enters through the same member.
- **No automatic failover.** If the configured member goes down, bolty does not
  discover another one; new connections to it fail. Front the cluster with DNS
  or an L4 (TCP) load balancer over the members and point bolty at that name —
  this composes cleanly with SSR, since routing is negotiated per connection
  once the TCP connection lands on *any* live member.
- **Causal consistency is manual.** There is no session abstraction, so
  read-after-write consistency requires threading bookmarks yourself: read the
  `bookmark` from a `Bolty.Response` (or the last response in a transaction) and
  pass it as `:bookmarks` to the next query/transaction. Without this, a read
  routed to a lagging member may not see a write you just made against the
  leader.
- **No topology awareness.** bolty does not fetch or cache a routing table, so it
  cannot pick "the nearest read replica" or re-route around a demoted leader
  mid-connection the way the official drivers do.

If you need automatic failover, read-replica load-balancing, or topology-aware
routing, put a load balancer in front (for failover/spread) and use bookmarks
(for consistency) — or use an official Neo4j driver that implements full
client-side routing.
