# Wallet Integration Practice (WIP) PRD

| 항목 | 내용 |
| :--- | :--- |
| **프로젝트명** | Wallet Integration Practice (WIP) |
| **버전** | 1.0 |
| **작성일** | 2024년 12월 |
| **담당자** | Flutter 개발팀 |
| **상태** | Draft - 프로토타입 개발 |

---

## 1. 프로젝트 개요

### 1.1 목적
* iLity Hub 본 개발에 앞서, 주요 암호화폐 지갑들의 연동 기술을 사전에 검증하고 학습하기 위한 프로토타입 프로젝트입니다.
* 이 프로젝트를 통해 다양한 지갑 연동 패턴을 익히고, 기술적 리스크를 조기에 파악하여 본 프로젝트의 안정성을 높입니다.

### 1.2 배경
* **iLity Hub**는 멀티체인을 지원하는 소셜 트레이딩 플랫폼입니다.
* EVM 계열(Ethereum, Polygon, BNB Chain 등)과 Non-EVM(Solana, Sui) 지원이 필요합니다.
* 외부 지갑 연결 및 트랜잭션 서명 기능이 핵심이며, 본 개발 전 지갑 연동 기술 검증이 필수적입니다.

### 1.3 목표
1.  **7개 주요 지갑**의 연결/해제 프로세스 구현 및 검증
2.  **WalletConnect v2** 프로토콜 심층 이해
3.  EVM / Non-EVM 체인별 연동 패턴 확립
4.  기본 트랜잭션 서명 플로우 검증
5.  Clean Architecture 기반 재사용 가능한 모듈 설계

---

## 2. 지원 지갑 목록

### 2.1 인기 지갑 (Priority 1)

#### MetaMask
| 항목 | 내용 |
| :--- | :--- |
| **설명** | 가장 인기 있는 브라우저 기반 지갑 |
| **지원 체인** | EVM 계열 (Ethereum, Polygon, BNB Chain, Arbitrum, Klaytn 등) |
| **연동 방식** | WalletConnect v2, Deep Link |
| **Flutter 패키지** | `walletconnect_flutter_v2`, `url_launcher` |

#### WalletConnect
| 항목 | 내용 |
| :--- | :--- |
| **설명** | 모바일 지갑 연결을 위한 표준 프로토콜 |
| **지원 체인** | EVM 계열 + 일부 Non-EVM (Solana, Cosmos 등) |
| **연동 방식** | QR 코드 스캔, Deep Link |
| **Flutter 패키지** | `walletconnect_flutter_v2` |

#### Coinbase Wallet
| 항목 | 내용 |
| :--- | :--- |
| **설명** | Coinbase의 셀프 커스터디 지갑 |
| **지원 체인** | EVM 계열, Solana |
| **연동 방식** | WalletConnect v2, Coinbase Wallet SDK |
| **Flutter 패키지** | `walletconnect_flutter_v2`, `coinbase_wallet_sdk` |

### 2.2 기타 지갑 (Priority 2)

#### Trust Wallet
| 항목 | 내용 |
| :--- | :--- |
| **설명** | 모바일 우선 암호화폐 지갑 |
| **지원 체인** | 70+ 체인 지원 (EVM, Solana, Cosmos 등) |
| **연동 방식** | WalletConnect v2 |
| **Flutter 패키지** | `walletconnect_flutter_v2` |

#### Rainbow
| 항목 | 내용 |
| :--- | :--- |
| **설명** | Ethereum 및 Layer 2 지원 지갑 |
| **지원 체인** | Ethereum, Polygon, Arbitrum, Optimism, Base 등 |
| **연동 방식** | WalletConnect v2 |
| **Flutter 패키지** | `walletconnect_flutter_v2` |

#### Phantom
| 항목 | 내용 |
| :--- | :--- |
| **설명** | Solana 및 Ethereum 지원 지갑 |
| **지원 체인** | Solana, Ethereum, Polygon |
| **연동 방식** | Deep Link, Phantom Connect API |
| **Flutter 패키지** | `solana_wallet_adapter`, `url_launcher` |
| **주의사항** | Non-EVM 체인으로 별도 연동 로직 필요 |

#### Rabby
| 항목 | 내용 |
| :--- | :--- |
| **설명** | 멀티체인 브라우저 지갑 |
| **지원 체인** | 100+ EVM 체인 |
| **연동 방식** | WalletConnect v2 |
| **Flutter 패키지** | `walletconnect_flutter_v2` |

---

## 3. 기술 스택

### 3.1 Core Dependencies

| 패키지 | 버전 | 용도 |
| :--- | :--- | :--- |
| **flutter** | 3.24+ | 프레임워크 |
| **flutter_riverpod** | 2.5+ | 상태 관리 |
| **walletconnect_flutter_v2** | 2.3+ | WalletConnect 프로토콜 |
| **web3dart** | 2.7+ | EVM 체인 연동 |
| **solana** | 0.30+ | Solana 체인 연동 |
| **url_launcher** | 6.2+ | Deep Link 처리 |
| **flutter_secure_storage** | 9.2+ | 세션 보안 저장 |

### 3.2 프로젝트 구조
Clean Architecture 기반으로 구성하며, 추후 iLity Hub 본 프로젝트에 모듈로 이식 가능하도록 설계합니다.

```text
lib/
├── core/                    # 공통 유틸리티, 상수
├── data/                    # Repository 구현체, 데이터 소스
├── domain/                  # Entity, UseCase, Repository 인터페이스
├── presentation/            # UI, ViewModel (Riverpod)
│   ├── providers/           # Riverpod Providers
│   ├── screens/             # 화면 위젯
│   └── widgets/             # 재사용 위젯
└── wallet/                  # 지갑 연동 모듈
    ├── adapters/            # 지갑별 어댑터
    │   ├── metamask_adapter.dart
    │   ├── walletconnect_adapter.dart
    │   ├── coinbase_adapter.dart
    │   ├── phantom_adapter.dart
    │