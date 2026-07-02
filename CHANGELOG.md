# Changelog

## [0.17.0](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/compare/v0.16.0...v0.17.0) (2026-07-02)


### Features

* **host:** sub-daily repetition for Register-ImperionTask ([#447](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/447)) ([#452](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/452)) ([cfcac59](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/cfcac59683e261ab4d2a9ef6d254ea7e7983bf16))


### Bug Fixes

* **collectors:** fail fast on -ColumnSet schema drift via information_schema guard ([#427](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/427)) ([#449](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/449)) ([59bdb58](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/59bdb58df6d72a99078e55a5cdaaca39dbe05b19))

## [0.16.0](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/compare/v0.15.1...v0.16.0) (2026-07-01)


### Features

* **merge:** add Invoke-ImperionMergeByPlan scaffold + invariant tests ([#430](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/430)) ([#434](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/434)) ([cfb6425](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/cfb6425ba9489122cd3e785b045f31bb6bab212b))
* **meta:** emit agent_event wake on freshly-merged inbound DM ([#446](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/446)) ([#448](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/448)) ([cc21749](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/cc2174952b833659abbf47d6e908e00e264ee58a))

## [0.15.1](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/compare/v0.15.0...v0.15.1) (2026-06-29)


### Bug Fixes

* **observability:** log task + HTTP failures to the structured JSONL ([#410](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/410)) ([#415](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/415)) ([2c524ff](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/2c524ff44bc66a3afc4e2d2e4eaa16cc76962604))
* **posture:** drift loop skips a misshapen golden table instead of aborting ([#409](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/409)) ([#412](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/412)) ([12d43ee](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/12d43ee24b4b8f829e304e8fd315e0250365d3d4))
* **release:** pin psd1 ModuleVersion to release-please + warn on shadowed Voyage key ([#411](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/411)) ([#414](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/414)) ([580bd59](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/580bd59f6adbeb61bce156ecdd0624525ea0559b))

## [0.15.0](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/compare/v0.14.0...v0.15.0) (2026-06-28)


### Features

* **autotask:** Opportunities entityInformation/fields probe ([#1325](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/1325)) ([#398](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/398)) ([d46fd23](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/d46fd23ecd4a4969e12f1eff81628ea9f4a5f7fc))
* **collector:** Instagram DM ingest -&gt; bronze -&gt; silver interaction + lead_hook ([#361](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/361)) ([#363](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/363)) ([65575fe](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/65575feb89f16213669a6981f5481acdcc934727))
* **context:** uniform per-tenant token resolver, ARM reuses m365 app ([#327](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/327)) ([#328](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/328)) ([ebdb04b](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/ebdb04b1e9e38b9ce4e8860ec02adc6b9c5ed884))
* **creds:** DB-authoritative company credential resolver + vendor-catalog cutover ([#319](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/319)) ([#320](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/320)) ([33045eb](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/33045eb6af7ec31c883619b25740f235617a7fd3))
* **intune:** Invoke-ImperionSoftwareCiMerge — intune_managed_apps → software_ci silver ([#354](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/354)) ([#355](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/355)) ([29b6883](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/29b68836bb3db61fa842192d322198e5d24e3d63))
* **knowledge:** scaffold Curated Vault local-sync arm ([#306](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/306)) ([#313](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/313)) ([30ccb4b](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/30ccb4b698de9e58836dd8a5482b803750380806))
* **knowledge:** vectorize the OKF semantic-layer bundle into gold ([#176](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/176)) ([#310](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/310)) ([3dd47e6](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/3dd47e6eac89547272dd688de64f53d8ad461700))
* **m365:** cut the 365 estate over to the tenant-outer driver ([#359](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/359)) ([#367](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/367)) ([fee3851](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/fee3851f52b11dc0a11f0a5205b135447ebc824c))
* **m365:** per-client security-posture scope + collector fan-out across mapped tenants ([#379](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/379)) ([#381](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/381)) ([7c96964](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/7c969645172bfc3fe863c8b9eb53c7a6d8489629))
* **m365:** registry-driven tenant fan-out for the 365 estate sweep ([#358](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/358)) ([#360](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/360)) ([968faff](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/968faff73c2592c14f250a1fa0ecde42a55e4dac))
* **m365:** tenant-outer hydration driver Invoke-ImperionTenantHydration ([#359](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/359), slice 3b pt1) ([#364](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/364)) ([7924c82](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/7924c822a1b31cd261586ac43459a4a34d331ba3))
* **merge:** fold Meta DMs into client_communication (channel=social_dm) ([#383](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/383)) ([#397](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/397)) ([14c2967](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/14c29675297f351485dce5d0d6d25348f268c01f))
* **merge:** M365 comms → client_communication, client-filtered ([#395](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/395)) ([#396](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/396)) ([f270402](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/f2704023aa89f2ff6cb9115e92a5d6a71fc8e5e1))
* **meta:** Meta Lead Ads collector + co-located lead_hook merge ([#362](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/362)) ([#365](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/365)) ([319a91e](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/319a91eb3a946f7b2da4e8e492100312bb642526))
* **pax8:** bronze-&gt;silver merge — resolve company to account via entity_xref ([#280](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/280)) ([#314](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/314)) ([008c50e](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/008c50e0e1592b3980206e4a1dddc2a2f06cbf63))
* **pax8:** collector -&gt; pax8_* bronze (companies/subscriptions/licenses/orders) ([#279](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/279)) ([#290](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/290)) ([4f440ee](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/4f440ee408c1e67e3ab303082df389a114a467de))
* **pax8:** populate license_assignment silver from subscriptions ([#316](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/316)) ([#344](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/344)) ([6418d9d](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/6418d9d69f911ccef31f46c1a6138194a007aad0))
* **social:** Meta brand-mention collector -&gt; social_engagement ([#391](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/391)) ([#392](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/392)) ([1eec491](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/1eec4914d7a7cc23e018f485ee9d78db4c637bbf))
* **social:** Social Engagement + post/ad metric collectors, normalize metric names ([#357](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/357)) ([#378](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/378)) ([b3fa6ca](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/b3fa6ca8a39af626025c7dd6474f51c630a8b4c7))
* **threads:** ingest collectors (posts/replies/mentions/insights) + merge ([#356](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/356)) ([#371](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/371)) ([79150c8](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/79150c8dbb66389b2a828020ce0e322a84aca590))
* **unifi:** Invoke-ImperionUniFiMerge — unifi_devices bronze -&gt; silver device ([#284](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/284)) ([#317](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/317)) ([0ec69c3](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/0ec69c3636f67d7f132ad537881a28fd80e0d3c5))
* **unifi:** one company Site Manager key enumerates all sites ([#321](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/321)) ([#345](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/345)) ([3c6a237](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/3c6a237463434f0b825e56d3cc6ae6bd464db44a))
* **vectorize:** read the Voyage key from conn-platform-voyage ([#406](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/406)) ([#407](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/407)) ([ad2cd73](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/ad2cd73a7ae28a75a3bb9a7047db828585b3a970))


### Bug Fixes

* **creds:** align account_tenant/connection param casts to column types ([#334](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/334)) ([#336](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/336)) ([f2ea1b3](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/f2ea1b3baeda30dbf188893a50b101997d4a61e2))
* **creds:** cast provider param to connection_provider enum in registry resolvers ([#330](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/330)) ([#331](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/331)) ([cb7f988](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/cb7f98824428e765a68afb9126e53aa78cff16f8))
* **darkwebid:** use Basic auth (username+password) from the credential registry ([#348](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/348)) ([#349](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/349)) ([81fc729](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/81fc729ce913930ee731be2709dc3ca380d2e44b))
* **dns:** guard empty zone id so one malformed zone never aborts the sync ([#323](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/323)) ([#333](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/333)) ([c95ebb3](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/c95ebb3dc98943ddbdcafeac4a8f077e8a9311b5))
* **dns:** isolate per-subscription failures in the DNS zone sweep ([#339](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/339)) ([#343](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/343)) ([0f1d0c4](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/0f1d0c43a412e6e3c689d4b1cf9bd0a3e94ae8b6))
* **m365:** collect home-tenant comms unfiltered; move client scoping to silver ([#380](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/380)) ([#382](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/382)) ([216bf63](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/216bf63205f66e291d918c1b3245b5e38d8aba80))
* **m365:** drop to one $expand on roleAssignments, hydrate principal by id ([#322](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/322)) ([#332](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/332)) ([0bf73ae](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/0bf73ae9eb520f404178442d53451a92f07caa54))
* **m365:** guard intune managed-apps collector against id-less device/app ([#374](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/374)) ([#376](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/376)) ([36f927d](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/36f927d9659142b687e33259857d06ee980d297f))
* **m365:** per-user app-only sensitivity-label endpoint + null-key skip ([#375](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/375)) ([#377](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/377)) ([90b789b](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/90b789b7f0df9cde3d00a92622a485ad3fbb8d26))
* **m365:** read group-member fields via safe accessor (StrictMode) ([#337](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/337)) ([#342](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/342)) ([0f78f2c](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/0f78f2c7a3482bd4730c4d776ab957f8e56dd46d))
* **m365:** reconcile info-protection collectors to the applied [#575](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/575) schema ([#372](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/372)) ([#373](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/373)) ([91c7c6a](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/91c7c6aa4330d6ba91724252432af0916f5d065b))
* **m365:** skip id-less group members so membership upsert can't 23502 ([#366](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/366)) ([#368](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/368)) ([cf2e32a](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/cf2e32a7eff311810dc4d3c6f97f1d310ed77e03))
* **m365:** use beta endpoint for per-device Intune detectedApps ([#369](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/369)) ([#370](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/370)) ([1bd2c09](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/1bd2c090ae23cbfcb27c3b5bcf37fc92bdc10fb2))
* **pax8:** repeat partial-index predicate in entity_xref ON CONFLICT ([#403](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/403)) ([#404](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/404)) ([85f935a](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/85f935aecb9c339c948d625e42bd436e715d1a21))
* **social:** register SocialEngagementSync + SocialMetricSync tasks ([#393](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/393)) ([#394](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/394)) ([8a620e0](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/8a620e0e503079217101c444fa952492002afa6d))
* **telivy:** add secret-safe API-shape discovery probe ([#312](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/312)) ([#315](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/315)) ([b13a429](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/b13a4294389d0ef2575743d73b9c816ae30f3272))

## [0.14.0](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/compare/v0.13.0...v0.14.0) (2026-06-22)


### Features

* **autotask:** promote contract + ticket collectors to *Sync cmdlets ([#287](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/287)) ([#288](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/288)) ([595fbdc](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/595fbdc63dfdac9e7e97eba5e2369d5deb730d2d))
* **knowledge:** vectorize memory_drawer into gold `memory` knowledge objects ([#300](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/300)) ([#309](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/309)) ([f7d011b](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/f7d011bbddea0a643323f4fb86a83e6f91711e6b))
* **m365:** per-tenant fail-isolation via shared estate-sweep helper ([#266](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/266)) ([#282](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/282)) ([2554be1](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/2554be15773cea28d0e3fd125b38c243d9a948f0))


### Bug Fixes

* **creds:** on-prem IT Glue/KQM/Telivy resolve from Key Vault standardized names ([#291](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/291)) ([#293](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/293)) ([2ced71b](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/2ced71b5caac085df2b648e8319cfcfbf12e4b46))
* **creds:** parse conn-company JSON credential blob + reroute myITprocess ([#299](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/299)) ([#301](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/301)) ([1b4ed76](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/1b4ed76de946a0a2e1dfcead96c886b07d3f96ff))
* **intune:** reconcile managed-apps collector to the per-device detectedApps schema ([#252](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/252)) ([#296](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/296)) ([39d3fbc](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/39d3fbcf45667304c72b81402a9be323bcd29631))
* **m365:** reconcile entra tenant-hygiene collectors to landed migration 0136 ([#219](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/219)) ([#295](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/295)) ([c63a362](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/c63a3623978ed1e0fc4754e41ab3392824b6972c))
* **myitprocess:** correct live API base host, auth header, items wrapper ([#297](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/297)) ([#302](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/302)) ([243d0e1](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/243d0e165430e98de26cb55a00d78a25deb21d99))
* **myitprocess:** map category/target_date to verified live field names ([#303](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/303)) ([#304](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/304)) ([9f45128](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/9f45128418582072f144b0969d6623d773de028a))

## [0.13.0](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/compare/v0.12.0...v0.13.0) (2026-06-21)


### Features

* **creds:** resolve per-tenant m365 app credential at the Graph-token seam ([#250](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/250)) ([#267](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/267)) ([4369d6f](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/4369d6fca1fec687618bd168bd36928f40754cfa))
* **creds:** Resolve-ImperionTenantCredential resolver core ([#257](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/257)) ([#265](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/265)) ([f60e9b3](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/f60e9b32b7f33d7eee02b3a905923dd3d0873d39))
* **creds:** UniFi multi-console sweep resolving per-client API keys from the registry ([#259](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/259)) ([#269](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/269)) ([061ac4a](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/061ac4a5e14bd2f3d721c79cf30540530820b713))
* **creds:** wire Azure ARM cloud-resource sync to the per-tenant resolver ([#258](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/258)) ([#268](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/268)) ([dbc58b0](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/dbc58b0aed4295abe819019cf4431e48ad36b07c))
* **onboarding:** New-ImperionClientOnboardingApp.ps1 — per-client read-only Entra app ([#261](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/261)) ([#262](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/262)) ([b9ca147](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/b9ca147bf6a3e253e8a0dc64418536b9ad521a02))

## [0.12.0](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/compare/v0.11.0...v0.12.0) (2026-06-20)


### Features

* **azure:** estate fan-out from account_tenant + cert-or-secret enterprise-app auth ([#234](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/234)) ([#235](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/235)) ([b2e119f](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/b2e119fe6e8d95536fe80c775577c5c75012791a))
* **merge:** own the Azure cloud_asset bronze→silver merge on-prem ([#241](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/241)) ([#242](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/242)) ([7db38f9](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/7db38f9d89ce9a7950a81d4d8db8c912699da34b))
* **merge:** own the M365 directory-group bronze→silver merge on-prem ([#239](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/239)) ([#240](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/240)) ([193ab47](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/193ab477b22a315051d8c35829aebe5553f41528))
* **secretstore:** support DPAPI (-Authentication None) unattended unlock ([#223](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/223)) ([#224](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/224)) ([a4ed79c](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/a4ed79c8800d16c8a8278a129de7852c7f343d34))
* **semantic:** reconcile the authority rule, not just columns ([#175](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/175)) ([#249](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/249)) ([e5cb903](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/e5cb90342cfb5026b5e34cf3e7ea37239ba59d42))


### Bug Fixes

* **azure:** emit cloud_* tags as jsonb, not text — fixes 42804 on the resource/RG insert ([#237](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/237)) ([#238](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/238)) ([e2f7946](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/e2f7946cf5dc5ee4cc2ac4e8943c00d8ffe97e3a))
* **tasks:** resolve '.\user' to a SID + report task registration failures honestly ([#246](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/246)) ([#247](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/247)) ([bb9feaa](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/bb9feaa9a2ad3b2a005ad8aa709abfae2fcf09d7))
* **tasks:** wire cloud_asset + M365 directory merges into Register-ImperionTask ([#243](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/243)) ([#244](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/244)) ([c6b1a7b](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/c6b1a7be65f15c83c06beac30a6e4476e61d9608))

## [0.11.0](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/compare/v0.10.0...v0.11.0) (2026-06-17)


### Features

* **arm:** Azure ARM cloud-resource inventory — slice 1 (ADR + per-client resource bronze collector) ([#217](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/217)) ([db11e44](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/db11e449fa26284b14c21e85eab5f5283fbe15d1))

## [0.10.0](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/compare/v0.9.0...v0.10.0) (2026-06-16)


### Features

* **local-pipeline:** Amazon Business + CDW logistics collectors → bronze ([#198](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/198)) ([#211](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/211)) ([b897b35](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/b897b35083b1c64ef775d4005094b2153bc5ac94))
* **local-pipeline:** scoped interaction collector (allowlisted principal ↔ client) → bronze + ADR-0022 ([#199](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/199)) ([#213](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/213)) ([2272bae](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/2272bae5f52572d7f2c1cbe56e330a7bea755529))

## [0.9.0](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/compare/v0.8.0...v0.9.0) (2026-06-16)


### Features

* **autotask:** scheduled TimeEntry bulk pull -&gt; autotask_time_entry bronze ([#171](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/171)) ([#172](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/172)) ([99cb0ed](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/99cb0ed229e8c44d10cd8b99ee261a71fc4c60ad))
* Azure DNS-zone collector + write-access probe ([#155](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/155)) ([#158](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/158)) ([cca3b88](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/cca3b8836ae520c5d2971ca6c2a607261a6a0ded))
* **dns:** golden-state + drift silver merge into dns_domain ([#157](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/157)) ([#181](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/181)) ([ae46d47](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/ae46d473c4e02459e6aebcf771a8afce85fed39b))
* **easydmarc:** EasyDMARC domain/DMARC posture collector -&gt; bronze ([#122](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/122)) ([#187](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/187)) ([6d0bc6f](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/6d0bc6f02f8d508a60787b44fb39dfd12a319cd7))
* **enrichment:** OKF drift agent opens cross-repo PR ([#190](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/190)) ([#193](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/193)) ([7f28623](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/7f286233bb29b9b15a7cf0f2795510e23eeae8d0))
* **enrichment:** OKF semantic-layer drift agent (propose-only, gated) ([#175](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/175)) ([#189](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/189)) ([d084db6](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/d084db6bc444dd46b1445778a82cdb1a40c7edbb))
* **entra:** group membership collector -&gt; m365_group_members bronze ([#139](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/139)) ([#153](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/153)) ([62693f2](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/62693f21a5f85576b1173f820b3f9255394389e7))
* **entra:** groups collector -&gt; m365_groups bronze ([#150](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/150)) ([#151](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/151)) ([6145185](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/614518513efe745f81d3931894e759eead492598))
* **expense:** receipt-blob 90-day lifecycle, guarded by verified-in-Autotask ([#169](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/169)) ([#180](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/180)) ([936df2f](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/936df2f93ac5575f183546f94e6d4796b5bbe43a))
* **ingest:** scheduled per-employee MileIQ drive pull -&gt; mileiq_drive bronze ([#167](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/167)) ([#191](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/191)) ([2c6613f](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/2c6613f1dd450407e911282b88097025226fd82f))
* **ingest:** scheduled QBO chart-of-accounts pull -&gt; qbo_expense_account bronze ([#168](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/168)) ([#192](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/192)) ([25a078c](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/25a078c20856e05f401b79784eedbf91d116e3d8))
* **intune:** managed-apps collector -&gt; security-posture bronze ([#143](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/143)) ([#182](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/182)) ([b73124d](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/b73124da8059f800e17d3c95c3ada902b275367e))
* **knowledge:** compose FB/IG social interactions into gold ([#127](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/127)) ([#184](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/184)) ([7ead719](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/7ead719025114487bb964cea8384f4c868368a95))
* **kqm:** opportunity header ingest -&gt; kqm_opportunities bronze ([#160](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/160)) ([#162](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/162)) ([e55116a](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/e55116a3da21966e6b037c4ea7ca9b2557265156))
* **kqm:** won-only opportunity detail ingest ([#161](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/161)) ([#163](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/163)) ([d6b50d9](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/d6b50d967ee573eef8ff6d5cdee4107a08a854f6))
* **local-pipeline:** QBO finance read-only collectors → bronze ([#197](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/197)) ([#210](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/210)) ([ef6d338](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/ef6d338aa516ec60a22cfa0e128d4e7f9e4d7daf))
* **local-pipeline:** transcript segment vectorization + citation view ([#200](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/200)) ([#202](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/202)) ([91c65c9](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/91c65c913a785d50c25c4aeed743a0bac6205b68))
* **posture:** sensitivity-labels + custom-security-attribute collectors -&gt; bronze ([#141](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/141)) ([#185](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/185)) ([4552181](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/4552181bc2e27957b3bb2305af83b1a437b04f0d))
* **posture:** tenant-hygiene collectors - domains, app registrations, role assignments ([#142](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/142)) ([#183](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/183)) ([92974af](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/92974af03030d5e2cacd514bf2c5066905eb2bac))
* public-resolve DNS collector (ground-truth plane) ([#156](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/156)) ([#159](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/159)) ([1f0a8c5](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/1f0a8c5bf4920fe77eafc72559f1ce7cfb1adf9e))
* **qbo:** re-target bronze collector BillPayment→Purchase ([#174](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/174)) ([#203](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/203)) ([2774d25](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/2774d25bc2acb7fd8d3f2f938427edc791fbc364))
* **qbo:** scheduled vendor bill-payment bulk pull -&gt; qbo_bill_payments bronze ([#170](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/170)) ([#173](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/173)) ([428aeb1](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/428aeb169342347d6d0112a594337c9385485761))
* **rmm:** Datto RMM/BCDR + myITprocess bronze collectors ([#195](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/195)) ([#207](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/207)) ([838aa15](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/838aa15a9db659f306e9cc24a73bae019cad514d))
* **security:** MS↔Autotask incident + Purview posture collectors + 180d retention sweep ([#196](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/196)) ([#208](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/208)) ([0eb9393](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/0eb9393534ed6c774ec2b04063b3a56512fe1515))


### Bug Fixes

* **meta:** update insight metric defaults ([#135](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/135)) ([#179](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/179)) ([c93d317](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/c93d3171d2de28cd1c6f39abb42017e3db242fb6))

## [0.8.0](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/compare/v0.7.0...v0.8.0) (2026-06-13)


### Features

* **sharepoint:** site inventory collector ([#137](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/137)) ([#148](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/148)) ([42f2507](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/42f2507228a8372e78215a41dda4944111becdc9))

## [0.7.0](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/compare/v0.6.1...v0.7.0) (2026-06-13)


### Features

* **posture:** auth methods / MFA registration collector ([#140](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/140)) ([#147](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/147)) ([01a1f80](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/01a1f803a385597625131a126eae1571425a79bd))
* **security:** defender incidents + alerts collector ([#138](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/138)) ([#145](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/145)) ([e0b8efb](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/e0b8efb4ca7c72074eea2f1ea3f871c4d10098e4))

## [0.6.1](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/compare/v0.6.0...v0.6.1) (2026-06-12)


### Bug Fixes

* **meta:** page-token hop, empty-envelope unwrap, intra-batch dedupe ([#133](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/133)) ([#134](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/134)) ([fc45032](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/fc4503229299c050cc8ec3b88fb8e5504302a31d))

## [0.6.0](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/compare/v0.5.0...v0.6.0) (2026-06-12)


### Features

* **meta:** Facebook/Instagram Business Manager collector + local silver merge ([#126](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/126)) ([#128](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/128)) ([d8243a9](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/d8243a9d6ef8b812d9b7fed265ba9c3d12bc7eb0))

## [0.5.0](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/compare/v0.4.0...v0.5.0) (2026-06-12)


### Features

* **docusign:** envelopes collector into docusign_contracts bronze, gated on secrets ([#99](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/99)) ([#117](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/117)) ([cc42971](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/cc42971b8f11547992f8c7b1ab32e4946c656193))
* **intune:** managedDevices device-compliance bronze feed, gated on migration ([#75](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/75)) ([#123](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/123)) ([edc4365](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/edc436550f462d19f683741065ac80aa2101c807))
* **kqm:** verify-first KQM quote collector into kqm_proposals bronze, gated on the API key ([#98](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/98)) ([#124](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/124)) ([1ff092f](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/1ff092f966010daa4cd8426b0fb2774530239a56))
* **m365:** mail/Teams post writers + gated comms tasks into the 0065 bronze tables ([#100](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/100)) ([#125](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/125)) ([5bd2cff](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/5bd2cff41ab5978626a89c526cebace50f8cf580))
* **plaud:** MCP recordings collector into plaud_recordings bronze, double-gated ([#72](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/72)) ([#121](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/121)) ([380c799](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/380c79921f4f6ee884d43c44f6b3b72c6fa3eca6))
* **sentinel:** per-entity Sentinel get + multi-table bronze router ([#97](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/97)) ([#119](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/119)) ([de7b7fc](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/de7b7fccd29c19081ad472b61df120eed3f9fd40))
* **unifi:** device inventory + config-compliance collector, double-gated ([#73](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/73)) ([#120](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/120)) ([8d806fd](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/8d806fd69824b09e6fa01c2ce517912635859df7))

## [0.4.0](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/compare/v0.3.0...v0.4.0) (2026-06-11)


### Features

* **setup:** svc-imperion local service account support ([#94](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/94), ADR-0012) ([#95](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/95)) ([b9b7ee1](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/b9b7ee11ff572f18b0642d538e1119ec8dc6196d))

## [0.3.0](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/compare/v0.2.0...v0.3.0) (2026-06-11)


### Features

* **posture:** quarterly Imperion Secure Score snapshot job ([#89](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/89)) ([#92](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/92)) ([6dcf81c](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/6dcf81c1823518d61ff14f1a3d72b413e0f76e80))

## [0.2.0](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/compare/v0.1.0...v0.2.0) (2026-06-11)


### Features

* **posture:** bulk posture silver merge - all tenants nightly ([#88](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/88)) ([#90](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/90)) ([7ad5249](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/7ad5249e9f0f892649babc65cd8787458262c390))
