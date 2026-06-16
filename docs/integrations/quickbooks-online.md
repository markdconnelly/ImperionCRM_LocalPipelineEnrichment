# Integration — QuickBooks Online: payment fact, chart-of-accounts, and the full finance/BI pull

QuickBooks Online (QBO) is the MSP's accounting source of record. **Read-only** scheduled bulk
pulls land into Postgres bronze, all via the **one** shared connect helper
(`Invoke-ImperionQboRequest`) and the same `qbo-access-token` / `qbo-realm-id` secrets — **one
connection, many readers, no second app registration, no write authority ever**:

1. **Purchases (Check/Expense) → `qbo_purchases`** — the authoritative **payment fact** (ADR-0014).
2. **Expense chart-of-accounts → `qbo_expense_account`** — the authoritative **category** list
   (ADR-0014, amended for #168).
3. **Full read-only finance pull → `qbo_invoices` / `qbo_payments` / `qbo_customers` /
   `qbo_estimates` / `qbo_bills` / `qbo_accounts` / `qbo_profit_and_loss`** — finance as a
   first-class account-health / BI signal (**ADR-0020**, issue #197; §3 below).

> **Simple Start, not AP (#174, front-end ADR-0085).** Imperion's QBO company is **Simple Start**,
> which has **no Accounts Payable** — `Bill`/`BillPayment` return "Feature Not Supported". 1099
> payments and reimbursements are Checks/Expenses = the **`Purchase`** entity. §1 below was
> re-targeted `BillPayment` → `Purchase` (front-end migration 0092 supersedes 0091).

**Read-only throughout — the app never writes QuickBooks.** Pure finance/reference data: both
flatten **straight to Postgres** and **skip the IT Glue hub** (ADR-0006).

## 1. Purchases — Check/Expense (the payment fact)

**Purpose.** Bulk-pull the MSP's own **Check/Expense transactions** from QuickBooks Online (QBO)
into Postgres bronze (`qbo_purchases`). This is the **authoritative payment fact** for employee
time-tracking (front-end **ADR-0082**, epic markdconnelly/ImperionCRM#458) and expense
reimbursement (front-end **ADR-0083**): the backend Payroll Reconciliation
(ImperionCRM_Backend#105) matches expected pay to a real QBO payment to move a timesheet to
**Paid**, and the reimbursement reconciliation matches a reimbursement the same way. **Read-only —
QBO is authoritative for the payment fact ALONE; the app never pays.** Pure finance data: flattens
**straight to Postgres** and **skips the IT Glue hub** (ADR-0006).

> **Simple Start → Purchase, not BillPayment (#174, front-end ADR-0085).** The QBO company is
> **Simple Start** — it has **no Accounts Payable**, so `Bill`/`BillPayment` (the entity this leg
> originally used) return "Feature Not Supported". 1099 contractor payments and reimbursements are
> recorded as **Checks / Expenses**, exposed as the **`Purchase`** entity. The subscription is NOT
> upgraded. Front-end migration **0092** (`qbo_purchases`) **supersedes** 0091 (`qbo_bill_payments`,
> which was empty and never wired).

> **v1 = all 1099.** Employees are paid hourly direct (gross = net) as QBO Check/Expense purchases
> → an exact amount match. W2 payroll is modeled-dormant (front-end ADR-0082).

## Source & auth
| Source | API | Auth |
| --- | --- | --- |
| QuickBooks Online | Intuit Accounting API v3 `https://quickbooks.api.intuit.com/v3/company/{realmId}/` | **OAuth2 `Authorization: Bearer <accessToken>`**; the company is the **realm id**. SecretStore `qbo-access-token` + `qbo-realm-id` |

- **Read-only / pull-only** (no webhooks reach a home server — ADR-0001).
- **Query endpoint:** `GET /v3/company/{realmId}/query?query=<url-encoded SQL>&minorversion=N`.
  The SQL-like grammar: `SELECT * FROM Purchase [WHERE MetaData.LastUpdatedTime > '<iso>']
  STARTPOSITION <n> MAXRESULTS <p>`.
- **Paging is in the query text** (`STARTPOSITION`/`MAXRESULTS`, max 1000/page). The connect
  helper (`Invoke-ImperionQboRequest`) owns the page-walk and stops on a short page.
- **Incremental:** `MetaData.LastUpdatedTime > '<ISO-8601>'` (the `IMPERION_QBO_SINCE_DAYS`
  window; 0 = full backfill).
- **Tokens EXPIRE (~1h) and the refresh token rotates (~100 days).** A refresh failure must
  re-auth (operator); the scheduled task logs + exits cleanly until then (idempotent re-run
  converges). Token refresh/custody for the *cloud* read path is backend BE-2's concern
  (ImperionCRM_Backend#104) — this node reads whatever access token the operator provisions.

## Entity & Postgres target (bronze)
| Entity | Source | Bronze table |
| --- | --- | --- |
| Purchase (Check/Expense) | `qbo` | `qbo_purchases` |

`qbo_purchases` columns (front-end migration 0092): `txn_date, total_amount, payment_type,
account_ref, account_name, entity_id, entity_type, entity_name, doc_number, currency,
created_time, last_updated_time` + the standard envelope (`tenant_id, source, external_id,
collected_at, raw_payload, content_hash`). `external_id` = the QBO Purchase **`Id`** (stable,
realm-scoped) → idempotent upsert. `total_amount` is the **payment fact** the backend
reconciliation reads; it is NOT comp data (pay_rate stays in the front-end finance-gated 0085
store) and is **never logged** (metric counts only). The payee link is the existing
`employee_profile.qb_vendor_id` (migration 0085) = `Purchase.EntityRef.value`.

> **Schema is front-end-owned (ADR-0042).** `qbo_purchases` is **SHIPPED** — front-end migration
> **0092** (markdconnelly/ImperionCRM#526 / front-end ADR-0085; drops + supersedes 0091/
> `qbo_bill_payments`), with the `imperion-localpipeline` SELECT/INSERT/UPDATE grant. The collector
> is still **deploy-ahead** on the QBO app registration (the task logs + exits until the secrets
> land), like UniFi / Plaud / intune-devices.

## Flatten
Standard pattern: flatten Purchase to `[PSCustomObject]` with the columns above +
`tenant_id, source, external_id, content_hash, collected_at, raw_payload`. `tenant_id` =
partner tenant (QBO is the MSP's own books, not per-customer credentialed — like KQM).

## Cadence
Daily (`scheduled-tasks/qbo/purchases.task.ps1`). Payment events are low-volume; a daily
incremental page-walk is ample. Stagger from other finance tasks.

## Provenance & posture
- Every row stamped `source = 'qbo'`, `collected_at`, full `raw_payload`. Read-only; no QBO
  write surface (the app never pays — front-end ADR-0082).
- **Comp/PII discipline (CLAUDE.md §8):** the payment amount and payee name are landed in
  bronze (the fact) but **never logged**. No pay_rate here.

## Gates (Mark — block LIVE not BUILD)
1. **QuickBooks Online read-only app registration** + token custody — the standing
   time-tracking blocker (same gate as backend ImperionCRM_Backend#104). Provision
   `qbo-access-token` + `qbo-realm-id` in the SecretStore.
2. ~~Front-end `qbo_purchases` bronze migration~~ — **SHIPPED** (front-end migration 0092, #526;
   includes the local-pipeline grant). No longer a gate; the app registration alone blocks LIVE.

## Still assumptions (no live access yet) — CONFIRM BEFORE LIVE
Modeled from the documented Intuit Accounting API; **unverified against the real company** until
the app registration lands (do not over-fit — the flatten keeps a fallback chain and
`raw_payload` is lossless, the KQM/DocuSign precedent):
- Purchase field names/casing (`TxnDate`, `TotalAmt`, `PaymentType`, `AccountRef.value/.name`,
  `EntityRef.value/.type/.name`, `DocNumber`, `CurrencyRef.value`,
  `MetaData.CreateTime/LastUpdatedTime`).
- The `QueryResponse.<Entity>` wrapper shape and the `minorversion` value.
- Production vs sandbox base host.
- ~~Whether `BillPayment` is the right entity~~ — **resolved (#174):** Simple Start has no AP, so
  the entity is **`Purchase`** (Check/Expense). Confirm against the real books which `PaymentType`
  values and which `Line[].AccountBasedExpenseLineDetail.AccountRef` accounts represent
  contractor-pay vs reimbursable-expense (CFO mapping, lives in `raw_payload` — no migration
  depends on the list).

## 2. Expense chart-of-accounts (the category system of record)

**Purpose.** Bulk-pull the MSP's **expense-type chart-of-accounts** from QBO into Postgres bronze
(`qbo_expense_account`). QuickBooks is the **category system of record** for expense tracking
(front-end **ADR-0083**, epic markdconnelly/ImperionCRM#482): the chart of accounts is synced
read-only and a front-end admin maps each account to a clean website `expense_category`
(front-end **#489**). **Read-only — the app never writes QuickBooks.** When finance needs a
missing category they create it in QuickBooks manually; the next pull surfaces it for mapping.
Pure reference data (account names like "Travel" / "Office Supplies" — not comp, not PII):
flattens straight to Postgres, skips the IT Glue hub (ADR-0006).

> **Boundary (#168):** this is the chart-of-accounts bulk sync ONLY. The backend QBO read client
> owns the bill-payment read for reconciliation (§1 above is the on-prem bulk leg of that fact).

### Entity & Postgres target (bronze)
| Entity | Source | Bronze table (proposed) |
| --- | --- | --- |
| Expense account | `qbo` | `qbo_expense_account` |

`qbo_expense_account` columns (proposed): `name, fully_qualified_name, account_type,
account_sub_type, classification, active, created_time, last_updated_time` + the standard envelope
(`tenant_id, source, external_id, collected_at, raw_payload, content_hash`). `external_id` = the
QBO Account **`Id`** (stable, realm-scoped) → idempotent upsert.

> **Schema is front-end-owned (ADR-0042).** `qbo_expense_account` does **not exist yet** — it is
> **proposed here** for a front-end migration (column set above + the `imperion-localpipeline`
> SELECT/INSERT/UPDATE grant), tracked as front-end **#592** (filed from #168) per migration 0088
> in the expense epic. Until that migration lands, the collector is **deploy-ahead** (the task logs
> + exits), exactly like the bill-payment pull.

### Query / filter
`SELECT * FROM Account WHERE Classification = 'Expense' [AND MetaData.LastUpdatedTime > '<iso>']`.
The `Classification = 'Expense'` filter covers the `AccountType` Expense / CostOfGoodsSold /
OtherExpense. Same page-walk (`Invoke-ImperionQboRequest`) and `IMPERION_QBO_SINCE_DAYS` window
(0 = full backfill — the chart of accounts is small, so a full backfill is cheap).

### Cadence
Daily (`scheduled-tasks/qbo/chart-of-accounts.task.ps1`). Slow-changing; stagger from the
bill-payment task.

### Gates (Mark — block LIVE not BUILD)
1. **Extend the QBO read scope to chart-of-accounts** (front-end markdconnelly/ImperionCRM#497) +
   the QuickBooks credential (`qbo-access-token` / `qbo-realm-id`, shared with §1).
2. **Front-end `qbo_expense_account` bronze migration** + the local-pipeline grant (front-end
   **#592**; migration 0088, apply gated by front-end #494).

### Still assumptions (no live access yet) — CONFIRM BEFORE LIVE
Modeled from the documented Intuit Accounting API; **unverified against the real company** until
the app registration lands (the flatten keeps a fallback chain, `raw_payload` is lossless):
- Account field names/casing (`Name`, `FullyQualifiedName`, `AccountType`, `AccountSubType`,
  `Classification`, `Active`, `MetaData.CreateTime/LastUpdatedTime`).
- The `Classification = 'Expense'` filter value vs. filtering on `AccountType` directly.
- The `QueryResponse.<Entity>` wrapper shape, `minorversion`, prod vs sandbox host.

## 3. Full read-only finance pull (the intelligence / BI engine — ADR-0020, issue #197)

**Purpose.** QBO is the company's accounting system of record for the *whole* finance picture, but
the engine previously saw only the two reconciliation slices (§1, §2). This widens QBO to a
**read-only, full-data** source so finance becomes a first-class account-health / BI signal —
revenue billed, cash received, A/R, A/P / procurement, the chart of accounts, and the period P&L.
Pure finance data: every collector flattens **straight to Postgres** and **skips the IT Glue hub**
(ADR-0006). **Read-only throughout — the app never writes QuickBooks.**

> **Additive, breaks nothing.** This reuses the existing `conn-company-qbo` connection
> (`Invoke-ImperionQboRequest`) in read-only form, adding **read scopes + new bronze targets only**.
> The two existing readers (§1, §2) keep their exact entities, tables, secrets, and posture. **No
> second app registration. No write authority is granted, ever** (ADR-0020 §2; the established QBO
> posture, ADR-0014 — "the app never pays / never writes QuickBooks").

### Entities, reports & Postgres targets (bronze — front-end migration 0120, front-end #688)

| QBO entity / report | Source | Bronze table | Collector → writer | BI meaning |
| --- | --- | --- | --- | --- |
| `Invoice` | `qbo` | `qbo_invoices` | `Get-ImperionQboInvoice` → `Set-ImperionQboInvoiceToBronze` | revenue billed; A/R when unpaid |
| `Payment` | `qbo` | `qbo_payments` | `Get-ImperionQboPayment` → `Set-ImperionQboPaymentToBronze` | customer cash IN against invoices |
| `Customer` | `qbo` | `qbo_customers` | `Get-ImperionQboCustomer` → `Set-ImperionQboCustomerToBronze` | finance customer master → join to silver account |
| `Estimate` | `qbo` | `qbo_estimates` | `Get-ImperionQboEstimate` → `Set-ImperionQboEstimateToBronze` | quotes / committed-but-unbilled pipeline |
| `Bill` *(see degrade note)* | `qbo` | `qbo_bills` | `Get-ImperionQboBill` → `Set-ImperionQboBillToBronze` | vendor bills / A/P — what the MSP owes |
| `Account` (FULL COA) | `qbo` | `qbo_accounts` | `Get-ImperionQboAccount` → `Set-ImperionQboAccountToBronze` | full chart of accounts for classification + rollups |
| Profit & Loss report | `qbo` | `qbo_profit_and_loss` | `Get-ImperionQboProfitAndLoss` → `Set-ImperionQboProfitAndLossToBronze` | period P&L snapshot for revenue / margin BI |

Each table carries the standard bronze envelope (`tenant_id, source = 'qbo', external_id,
collected_at, raw_payload, content_hash`) + the flat finance columns; `external_id` = the QBO entity
`Id` (idempotent upsert + content-hash skip). `qbo_purchases` (§1, migration 0092) is **reused, not
duplicated** — its collector is unchanged.

- **`qbo_accounts` is the FULL chart of accounts** (no `Classification` filter), distinct from the
  expense-only `qbo_expense_account` (§2). Whether the expense slice becomes a **view** over
  `qbo_accounts` or stays a separate table is a **front-end migration-author call** (ADR-0020 open
  item) — this repo just lands the full COA.
- **P&L is a REPORT, not an entity.** It is pulled from the QBO **Reports** API
  (`GET /v3/company/{realmId}/reports/ProfitAndLoss?start_date&end_date&minorversion`), **not** the
  `/query` endpoint, so the P&L collector calls the transport core directly (not
  `Invoke-ImperionQboRequest`). One **immutable snapshot** row per period (`external_id` = the
  period key, ADR-0011 snapshot idiom); headline totals (income / expenses / net income) are
  surfaced as flat columns, the full report lives in `raw_payload`. Window defaults to the current
  calendar month; override via `IMPERION_QBO_PNL_START` / `IMPERION_QBO_PNL_END`.

### `Bill` / A/P on Simple Start — graceful degrade (CONFIRM-BEFORE-LIVE)

Imperion's QBO company is **Simple Start**, which has **no Accounts Payable**, so `Bill` may return
**"Feature Not Supported"** (the same constraint that re-targeted the payment fact `BillPayment` →
`Purchase`, #174). `Get-ImperionQboBill` **degrades gracefully**: on a Feature-Not-Supported fault it
logs a clear **warning** and yields **no rows** — it does NOT hard-fail. `qbo_bills` then stays
**dormant** and the A/P / procurement signal is carried by `qbo_purchases` + `qbo_accounts` (expense
classifications). Any *other* error (token expiry, transport) **re-throws** so the schedule fails
loudly per the standard posture. `qbo_bills` is modeled for completeness and a future non-Simple-Start
tier. Whether `Bill` is available at all on the live company is **confirmed in the collector phase**.

### Cadence
Daily per entity (`scheduled-tasks/qbo/{invoices,payments,customers,estimates,accounts,bills}.task.ps1`);
the full chart of accounts defaults to a full backfill (it is small). The P&L snapshot
(`scheduled-tasks/qbo/profit-and-loss.task.ps1`) runs daily/monthly and is idempotent on the period.
Stagger from the §1 / §2 finance tasks.

### Provenance & posture
- Every row stamped `source = 'qbo'`, `collected_at`, full `raw_payload`. Read-only; no QBO write
  surface. **Client financial PII** (invoice/payment/customer/bill amounts, names, balances) lands
  in the access-controlled store tagged with the owning tenant; the structured logs record
  **counts only — never amounts, customer/vendor names, or row content** (CLAUDE.md §8). No comp
  data (`pay_rate`) is read or stored here.

### Gates (Mark — block LIVE not BUILD)
1. **QuickBooks Online read-only app registration** + token custody — the standing QBO blocker
   (shared with §1/§2 and backend #104). Extend the read scope to the new entities/reports;
   provision `qbo-access-token` + `qbo-realm-id`. The collectors are **DORMANT** until then (each
   task logs + exits).
2. **Front-end finance-bronze migration `0120`** (front-end #688) merged + applied — defines the
   seven tables above + the `imperion-localpipeline` SELECT/INSERT/UPDATE grant. Until then the
   collectors **fail loudly** on the missing tables (ADR-0005); no table is touched.

### Still assumptions (no live access yet) — CONFIRM BEFORE LIVE
Modeled from the documented Intuit Accounting + Reports API; **unverified against the real company**
until the app registration lands (the flatten keeps a fallback chain, `raw_payload` is lossless):
- Invoice / Payment / Customer / Estimate / Bill / Account field names + casing.
- **Whether `Bill` / A/P is available on this Simple Start company at all** (§3 degrade note).
- The exact P&L Reports shape — the Header/Rows/Summary tree and where the income / expenses / net
  income totals sit in it; the report path/params and `minorversion`; prod vs sandbox host.

### Front-end follow-up (OKF + silver, system CLAUDE.md §11)
Finance becoming a first-class account-health / BI signal — joining `qbo_customers` to the silver
`account`, rolling revenue / A/R / A/P / margin into account health — is a silver-entity
shape / source-of-record decision (QBO = SoR for the finance facts). The matching OKF concept
file(s) + `coverage-matrix.md` row(s) are **proposed back to the front end** (file a front-end issue
at the collector phase, parallel to the schema-ownership rule). Bronze-only ingestion (this PR) does
not itself change a silver entity's meaning.

## Cross-references
- **ADR-0020** (this repo — finance QBO read-only full-data pull into the BI engine), issue **#197**.
- front-end **ADR-0082** (time-tracking design), epic markdconnelly/ImperionCRM#458.
- front-end **ADR-0083** (expense tracking design), epic markdconnelly/ImperionCRM#482; **#489**
  (admin account→category mapping), **#497** (extend QBO read scope), **#494** (apply migrations),
  **#592** (proposed `qbo_expense_account` bronze migration, filed from #168).
- backend **#104** (QBO cloud read client + KV custody), **#105** (Payroll Reconciliation —
  reads `qbo_bill_payments` to set Paid).
- This repo: the QBO source ADR (`docs/decision-records/ADR-0014-quickbooks-online-payment-fact.md`),
  ADR-0001 (cloud keeps webhooks), ADR-0005 (source catalog), ADR-0042 (four-repo split, system).
