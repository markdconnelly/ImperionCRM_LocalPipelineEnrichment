# Changelog

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
