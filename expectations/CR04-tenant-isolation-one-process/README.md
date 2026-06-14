# CR04 — tenant-isolation-one-process

## Surface

The consolidated runtime binary (`kaleidoscope`, consolidated-runtime-v0 /
ADR-0076). Tenant isolation within the single process's shared live store.

## Behaviour

A metric ingested under one tenant is not visible to a query scoped to another
tenant, in the same consolidated process — the single-process / live-Arc
analogue of Q08 (which used separate gateway + query-api).

Same Pulse root:

1. boot `kaleidoscope` with `KALEIDOSCOPE_TENANT=tenant-a`. Ingest two metrics to
   :4318: one with `service.name=cr04-svcA` (default tenant → tenant-a), and one
   carrying an explicit OTLP resource `tenant.id=tenant-b` (routes to tenant-b,
   the EG04 routing).
2. query metrics (router bound to tenant-a) → **1 series** (only svcA; the
   tenant-b metric is isolated out, not leaked into the tenant-a view).
3. restart over the same root with `KALEIDOSCOPE_TENANT=tenant-b` → query → **1
   series** (only the tenant-b metric). This confirms it was ingested (not
   dropped) and that tenant-a's svcA is isolated out of tenant-b's view.

So the shared live store partitions by tenant; neither tenant sees the other's
data.

## Source

- kaleidoscope `consolidated-runtime-v0` (`fbcacca`/`2a74e4f`): one aperture
  ingest honouring resource `tenant.id`, the per-signal store partitioned by
  tenant, query routers scoped to one tenant.
- Contract anchor: implementer msg 037 ("TENANT ISOLATION in one process");
  EG04 (resource tenant.id routing); Q08/LQ07/TQ05 (cross-tenant read
  isolation in the split deployment).

## Verification

- Status: `satisfied`
- Grounded GREEN: 2026-06-14 UTC at HEAD `706c852` (runtime code unchanged since
  `2a74e4f`). `tenant_a_view=1`, `tenant_b_view=1`.
- Transition-proof: RED if the tenant-a query sees the tenant-b metric (count
  `2` = leak) or the tenant-b query does not see its own (count `0` = dropped).
- Method: `harness/run-kaleidoscope-runtime.sh`; the runner boots the runtime as
  tenant-a, ingests one default-tenant metric + one `tenant.id=tenant-b` metric,
  queries tenant-a, then restarts as tenant-b over the same root and queries.

## Notes

A first run was RED (`tenant_a=2 tenant_b=0`) from a runner bug of mine, not a
defect: I passed two comma-separated attributes in one telemetrygen
`--otlp-attributes` flag (`service.name=...,tenant.id=...`), which dropped the
`tenant.id`, so the second metric fell into the default tenant. I disambiguated
by switching to the single-attribute `tenant.id` form (the EG04-proven syntax)
and re-ran GREEN — the consolidated runtime does honour resource `tenant.id`. I
did not report a routing defect on my own malformed flag. `.no-compose`: CR04
manages its own runtime containers.
