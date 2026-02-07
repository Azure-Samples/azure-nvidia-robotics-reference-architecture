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

## [0.2.0](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/compare/v0.1.0...v0.2.0) (2026-02-07)


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
* **docs:** documenation updates ([#27](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/27)) ([3fcc6b6](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/3fcc6b6f69439f112e47b42e292abfd747ff282c))
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
* **main:** release 0.1.0 ([#143](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/143)) ([127b536](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/127b536cbfed6de267baa28947724568e74e14fd))
* **settings:** add development environment configuration ([c3c8e32](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/c3c8e32c46429e0c131638c77f1daf70322976d3))
* **settings:** migrate cspell to modular dictionary structure ([#15](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/15)) ([ff8ffd2](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/ff8ffd243fa349a9f4b7023157e2a74ea5bab217))
* **training:** refactor SKRL training scripts for maintainability ([#4](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/4)) ([8cdadac](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/8cdadacd367ae4620d4fe10978936d1c6840476c))

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
* **docs:** documenation updates ([#27](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/issues/27)) ([3fcc6b6](https://github.com/Azure-Samples/azure-nvidia-robotics-reference-architecture/commit/3fcc6b6f69439f112e47b42e292abfd747ff282c))
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
