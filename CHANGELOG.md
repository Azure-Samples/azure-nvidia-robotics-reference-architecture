---
title: Changelog
description: Automatically generated changelog tracking all notable changes to the Azure NVIDIA Robotics Reference Architecture using semantic versioning
author: Edge AI Team
ms.date: 2026-02-06
ms.topic: reference
---

<!-- markdownlint-disable MD012 MD024 -->

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> **Note:** This file is automatically maintained by [release-please](https://github.com/googleapis/release-please). Do not edit manually.

## [0.3.0](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/compare/v0.2.0...v0.3.0) (2026-02-19)


### ✨ Features

* add LeRobot imitation learning pipelines for OSMO and Azure ML ([#165](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/165)) ([baef32d](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/baef32de241def42a2d688a47d1628f182d6f272))
* **linting:** add YAML and GitHub Actions workflow linting via actionlint ([#192](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/192)) ([e6c1730](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/e6c1730b73c65172a9a6858bcae6536de84f9323))
* **scripts:** add dependency pinning compliance scanning ([#169](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/169)) ([5d90d4c](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/5d90d4c2608f325dabd8a78b1b67b1917e4024ea))
* **scripts:** add frontmatter validation linting pipeline ([#185](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/185)) ([6ff58e3](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/6ff58e3a001fc86189fbb79cd5a1f434fbb0114a))
* **scripts:** add verified download utility with hash checking ([#180](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/180)) ([063dd69](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/063dd692a8ec02c62934040d7a6d983617d38f07))


### 🐛 Bug Fixes

* **build:** remove [double] cast on JaCoCo counter array in coverage threshold check ([#312](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/312)) ([6b196de](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/6b196de1280a0683f4a14bb19a10662527a237a2))
* **build:** resolve release-please draft race condition ([#311](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/311)) ([6af1d8b](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/6af1d8b2dc633d62ade95d2722bf469aabe3c60c))
* **scripts:** wrap Get-MarkdownTarget returns in array subexpression ([#314](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/314)) ([1c5e757](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/1c5e757fbaa78441d95c94dde0aa5459666e8a22))
* **src:** replace checkpoint-specific error message in upload_file ([#178](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/178)) ([bc0bc7f](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/bc0bc7f396d9386d026de62d49250c3ff3bccb5f))
* **workflows:** add id-token write permission for pester-tests ([#183](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/183)) ([5c87ca8](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/5c87ca8c9ec8965298d7c21b7ad9951544af2e8d))


### ♻️ Code Refactoring

* **scripts:** align LintingHelpers.psm1 with hve-core upstream ([#193](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/193)) ([f24bc04](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/f24bc0465aab0ffb255ad122175fc7a1b894742e))
* **scripts:** replace GitHub-only CI wrappers with CIHelpers in linting scripts ([#184](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/184)) ([033cc9c](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/033cc9cf75c82b2ba9169c3c7f5abea1a098c491))
* **src:** standardize os.environ usage in inference upload script ([#194](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/194)) ([5a82581](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/5a82581f89fb7e2c0b88f168a7735707788f087c))


### 🔧 Miscellaneous

* **scripts:** add Pester test runner and fix test configuration ([#176](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/176)) ([4e54ae2](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/4e54ae2330b09a437f5bbfb0a9832f971852058f))

## [0.2.0](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/compare/v0.1.0...v0.2.0) (2026-02-12)


### ✨ Features

* **build:** add automatic milestone closure on release publish ([#148](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/148)) ([18c72e5](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/18c72e56f53afef39eb0db16ad6246f6ddc43827))


### 🐛 Bug Fixes

* **build:** restore release-please skip guard on release PR merge ([#147](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/147)) ([d8ade84](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/d8ade846074d9b184959715775184b2dc3284af4))
* **workflows:** quote if expression to resolve YAML syntax error ([#172](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/172)) ([b3120a6](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/b3120a6b07253fb494da20d1e2acdf9f1bc6a627))


### 📚 Documentation

* add deployer-facing security considerations ([#161](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/161)) ([1f5c110](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/1f5c1101efe80d3564e8eb5204cd52f75dba116c))
* add hve-core onboarding to README and contributing guides ([#153](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/153)) ([8fb63bb](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/8fb63bbc0c2543a1cf24a15fbbe7020dd4c16c47))
* add testing requirements to CONTRIBUTING.md ([#150](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/150)) ([0116c4f](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/0116c4f9e6c45e29327bb6e0f59af140237462fa))
* **contributing:** add accessibility best practices statement ([#166](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/166)) ([2d5f239](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/2d5f2399bcb39bff8c5ae276cfe77524297c4e48))
* **contributing:** publish 12-month roadmap ([#159](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/159)) ([f158463](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/f158463fcca6d2eeaab48c88da3a242ed6b2df7d))
* create comprehensive CONTRIBUTING.md ([#119](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/119)) ([9c60073](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/9c600734b139099e7f6f0976a2791de13a19096c))
* define documentation maintenance policy ([#162](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/162)) ([bd750ed](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/bd750ed2a7943680b5ee0ab24e9e77899d2b9c0c))
* **deploy:** standardize installation and uninstallation terminology in README files ([#168](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/168)) ([43427f3](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/43427f323aaaa30888742875949497106543a9b7))
* **docs:** add test execution and cleanup instructions ([#167](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/167)) ([d83b20e](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/d83b20e1714da98d67ea11145def056a710ff7e2))
* **docs:** decompose and relocate detailed contributing guide ([#156](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/156)) ([3783400](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/3783400811df619cc4b9b150048ccea032fa9351))
* **scripts:** document submit script CLI arguments ([#123](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/123)) ([adabdd5](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/adabdd51e8db0e734d0875a070bc4ded338ec8a6))
* **src:** add docstrings to training utils context module ([#157](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/157)) ([b6312f5](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/b6312f5942b32bf4f0f94625baec100279c674b9))
* **src:** add Google-style docstrings to metrics module ([#151](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/151)) ([311886c](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/311886c5740ba4d5ab98a215998514772c9bb965))
* **src:** expand Google-style docstrings for training utils env module ([#131](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/131)) ([29ab4f8](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/29ab4f802fd023a3b1ec6318b449ab60356b28fa))


### 🔧 Miscellaneous

* **deps:** bump protobuf from 6.33.3 to 6.33.5 ([#51](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/51)) ([cab59e6](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/cab59e620678d3056180ffc152bfd0789891f4ac))
* **deps:** bump the github-actions group with 4 updates ([#155](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/155)) ([f73898f](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/f73898f9b6f9b919a819633cdc7b200f41eb145b))
* **deps:** bump the python-dependencies group across 1 directory with 11 updates ([#134](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/134)) ([09331ea](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/09331ea3757681f1fca2acf9eca61043718cb409))

## [0.1.0](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/compare/v0.0.1...v0.1.0) (2026-02-07)


### ✨ Features

* **.github:** Add GitHub workflows from hve-core ([#22](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/22)) ([96ae111](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/96ae111622bc751f38d616803c85f5ab6e5dcca4))
* add PR template and YAML issue form templates ([#16](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/16)) ([059ac48](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/059ac48d133eb7fb6013408e2df74de948769293))
* **automation:** add runbook automation ([#25](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/25)) ([c8f0fd4](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/c8f0fd4f8bc661f3caff1d737e4c05ad2bb70d19))
* **build:** integrate release-please bot with GitHub App auth and CI gating ([#139](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/139)) ([f930b6b](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/f930b6bcb569b624622c73a3c4893a50fa26dbaa))
* **build:** migrate package management to uv ([#43](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/43)) ([cfe028f](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/cfe028f3943192793af932bbadf83e50d50c375e))
* **cleanup:** remove NGC token requirement and add infrastructure cleanup documentation ([#31](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/31)) ([51ed7d6](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/51ed7d683e39d12cdc82b53ba83b8a71e75c25e6))
* **deploy:** add Azure PowerShell modules for automation runbooks ([#44](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/44)) ([0148921](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/01489211b29b762453669a04ef07433465114496))
* **deploy:** add policy export and inference scripts for ONNX/JIT ([#21](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/21)) ([94b6ff1](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/94b6ff1aa69f4643292ca75707bd8e7cd74c55bf))
* **deploy:** add support for workload identity osmo datasets ([#24](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/24)) ([c948a3c](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/c948a3c8bf47dfbb5d78d6b70ae71651de020743))
* **deploy:** implement robotics infrastructure with Azure resources ([#9](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/9)) ([103e31e](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/103e31eb481356b3c19d0ed9f7e8a4b320dd6d1b))
* **deploy:** integrate Azure Key Vault secrets sync via CSI driver ([#32](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/32)) ([864006b](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/864006b3af8dabd17d73748dfbc610c10fc3e1a1))
* **devcontainer:** enhance development environment setup ([#28](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/28)) ([a930ac0](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/a930ac00565fcb29ef01c3df3e58d40b0aa196ee))
* **docs:** documentation updates ([#27](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/27)) ([3fcc6b6](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/3fcc6b6f69439f112e47b42e292abfd747ff282c))
* initial osmo workflow and training on Azure ([#1](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/1)) ([ff5f7df](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/ff5f7df55ddb474e72e8f508120b1c69a24d9d7d))
* **instructions:** add Copilot instruction files and clean up VS Code settings ([#36](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/36)) ([6d8fb2c](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/6d8fb2c14f7703cd3ee233a11d4370c5d35ecb75))
* **repo:** add root capabilities and reorganize README ([#17](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/17)) ([4aede6f](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/4aede6fb33fecd066748c198d12fee288b427596))
* **robotics:** refactor infra and finish OSMO and AzureML support ([#23](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/23)) ([3b15665](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/3b15665dc563253a2460c01f8057d8719e97a815))
* **scripts:** add CIHelpers.psm1 shared CI module ([#129](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/129)) ([467e071](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/467e071381e559d143b271a3f898c88ca2f67d03))
* **scripts:** add RSL-RL 3.x TensorDict compatibility and training backend selection ([#26](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/26)) ([4986caa](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/4986caa92d2dbcae874b6f95f9fe3d952471c565))
* **scripts:** reduce payload size by excluding any cache from python ([#29](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/29)) ([8a20b46](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/8a20b46c869cfee5e2f587f63b78d3a1f9164b25))
* **training:** add MLflow machine metrics collection ([#5](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/5)) ([1f79dc0](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/1f79dc0439072af7b3a6407e7b460d166147217d))


### 🐛 Bug Fixes

* **build:** strip CHANGELOG frontmatter and fix initial version for release-please ([#142](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/142)) ([81755ec](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/81755ecd86100f0507d768c980ccae4ebe76a9df))
* **deploy:** ignore changes to zone in PostgreSQL flexible server lifecycle ([#34](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/34)) ([80ef4a6](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/80ef4a625bb50090477b5bd23a797aa414c2c1a3))
* **deploy:** resolve hybrid cluster deployment issues ([#39](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/39)) ([69f69d7](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/69f69d7dfb96fde6cf831983971e3ae9af67232f))
* **ps:** avoid PowerShell ternary for compatibility ([#124](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/124)) ([b8da8a1](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/b8da8a1a353b4edec28ff9958a3b3810be542912))
* **script:** replace osmo-dev function with direct osmo command usage ([#30](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/30)) ([29c8b6d](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/29c8b6d9b3c11ca2e145454a2aaea3dd8f782ad2))


### 📚 Documentation

* **deploy:** enhance VPN and network configuration documentation ([#38](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/38)) ([2992f07](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/2992f0743265387a3c754b650d8641e41f9ab9c0))
* **deploy:** enhance VPN documentation with detailed client setup instructions ([#35](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/35)) ([4ded515](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/4ded515697bd8b3c0235c5487d01b9a8e35950e5))
* enhance README with architecture diagram and deployment documentation ([#33](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/33)) ([7baf903](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/7baf90331684647c39d18bfe70e8f5fc28499eec))
* update README.md with architecture overview and repository structure ([4accbdb](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/4accbdbd6ff088e7e898f1222d99b030b78daffa))


### 🔧 Miscellaneous

* **deps:** bump azure-core from 1.28.0 to 1.38.0 ([#45](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/45)) ([d25d14e](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/d25d14e151af8b0b79fc50ff514ec61531715cb5))
* **deps:** bump azure-core from 1.28.0 to 1.38.0 in /src/training ([#42](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/42)) ([b1bd20c](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/b1bd20c478e1b69312627104f81819fd9ac305de))
* **deps:** bump pyasn1 from 0.6.1 to 0.6.2 ([#46](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/46)) ([97a3b2c](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/97a3b2c1cda50023255aeaf20a0df1c33f85744a))
* **instructions:** add general instructions copilot instructions ([44fc94d](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/44fc94d70caf9d07dc2c402bf71c6e761ec9566d))
* **settings:** add development environment configuration ([c3c8e32](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/c3c8e32c46429e0c131638c77f1daf70322976d3))
* **settings:** migrate cspell to modular dictionary structure ([#15](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/15)) ([ff8ffd2](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/ff8ffd243fa349a9f4b7023157e2a74ea5bab217))
* **training:** refactor SKRL training scripts for maintainability ([#4](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/4)) ([8cdadac](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/8cdadacd367ae4620d4fe10978936d1c6840476c))
