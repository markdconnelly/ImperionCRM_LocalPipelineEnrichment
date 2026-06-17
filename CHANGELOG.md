# Changelog

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
