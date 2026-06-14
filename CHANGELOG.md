# Changelog

## [0.9.0](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/compare/v0.8.0...v0.9.0) (2026-06-14)


### Features

* **autotask:** scheduled TimeEntry bulk pull -&gt; autotask_time_entry bronze ([#171](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/171)) ([#172](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/172)) ([99cb0ed](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/99cb0ed229e8c44d10cd8b99ee261a71fc4c60ad))
* Azure DNS-zone collector + write-access probe ([#155](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/155)) ([#158](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/158)) ([cca3b88](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/cca3b8836ae520c5d2971ca6c2a607261a6a0ded))
* **entra:** group membership collector -&gt; m365_group_members bronze ([#139](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/139)) ([#153](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/153)) ([62693f2](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/62693f21a5f85576b1173f820b3f9255394389e7))
* **entra:** groups collector -&gt; m365_groups bronze ([#150](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/150)) ([#151](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/151)) ([6145185](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/614518513efe745f81d3931894e759eead492598))
* **kqm:** opportunity header ingest -&gt; kqm_opportunities bronze ([#160](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/160)) ([#162](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/162)) ([e55116a](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/e55116a3da21966e6b037c4ea7ca9b2557265156))
* public-resolve DNS collector (ground-truth plane) ([#156](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/156)) ([#159](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/159)) ([1f0a8c5](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/1f0a8c5bf4920fe77eafc72559f1ce7cfb1adf9e))
* **qbo:** scheduled vendor bill-payment bulk pull -&gt; qbo_bill_payments bronze ([#170](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/170)) ([#173](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/issues/173)) ([428aeb1](https://github.com/markdconnelly/ImperionCRM_LocalPipelineEnrichment/commit/428aeb169342347d6d0112a594337c9385485761))

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
