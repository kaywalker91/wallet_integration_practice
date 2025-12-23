# Initial Requirements - Wallet Integration Practice

**프로젝트**: iLity Hub Multi-Chain Wallet Integration Prototype
**버전**: 1.0.0
**작성일**: 2025-12-08
**상태**: In Development

---

## 1. 프로젝트 개요

### 1.1 목적
멀티체인 지갑 통합 프로토타입 개발. EVM 호환 체인(Ethereum, Polygon, Arbitrum, Optimism, Base, BNB)과 Solana를 지원하는 통합 지갑 연결 레이어 구축.

### 1.2 범위
- 다중 지갑 프로토콜 지원 (WalletConnect, MetaMask, Phantom, Trust Wallet)
- 멀티체인 네트워크 전환
- 트랜잭션 서명 및 전송
- Deep Link 기반 모바일 지갑 연동

---

## 2. 기능 요구사항

### 2.1 지갑 연결 (Wallet Connection)

| ID | 요구사항 | 우선순위 | 상태 |
|----|----------|----------|------|
| WC-01 | WalletConnect v2 프로토콜 지원 | P0 | ✅ 완료 |
| WC-02 | MetaMask Deep Link 연동 | P0 | ✅ 완료 |
| WC-03 | Phantom 지갑 연동 (Solana) | P0 | ✅ 완료 |
| WC-04 | Trust Wallet 연동 | P1 | ✅ 완료 |
| WC-05 | QR 코드 기반 연결 UI | P0 | ✅ 완료 |
| WC-06 | 다중 지갑 동시 연결 | P2 | ❌ 제외 (범위 축소) |
| WC-07 | 세션 지속성 (앱 재시작 후 복원) | P1 | ⏳ 예정 |

### 2.2 체인 관리 (Chain Management)

| ID | 요구사항 | 우선순위 | 상태 |
|----|----------|----------|------|
| CM-01 | EVM 체인 전환 (switchChain) | P0 | ✅ 완료 |
| CM-02 | 7개 EVM 메인넷 지원 | P0 | ✅ 완료 |
| CM-03 | 테스트넷 지원 (Sepolia, Amoy 등) | P1 | ✅ 완료 |
| CM-04 | Solana 클러스터 지원 | P0 | ✅ 완료 |
| CM-05 | 커스텀 체인 추가 (addChain) | P2 | ⏳ 예정 |
| CM-06 | CAIP-2 체인 식별자 지원 | P1 | ✅ 완료 |

### 2.3 트랜잭션 (Transactions)

| ID | 요구사항 | 우선순위 | 상태 |
|----|----------|----------|------|
| TX-01 | EVM 트랜잭션 전송 | P0 | ✅ 완료 |
| TX-02 | Personal Sign (eth_sign) | P0 | ✅ 완료 |
| TX-03 | EIP-712 Typed Data 서명 | P1 | ✅ 완료 |
| TX-04 | Solana 트랜잭션 서명 | P0 | ✅ 완료 |
| TX-05 | 다중 트랜잭션 배치 서명 (Solana) | P2 | ✅ 완료 |
| TX-06 | 트랜잭션 상태 추적 | P2 | ⏳ 예정 |

### 2.4 계정 관리 (Account Management)

| ID | 요구사항 | 우선순위 | 상태 |
|----|----------|----------|------|
| AM-01 | 연결된 계정 목록 조회 | P0 | ✅ 완료 |
| AM-02 | 활성 계정 선택 UI | P1 | 🔄 진행중 |
| AM-03 | 계정별 잔액 조회 | P2 | ⏳ 예정 |
| AM-04 | 계정 주소 복사/공유 | P1 | ⏳ 예정 |

---

## 3. 비기능 요구사항

### 3.1 아키텍처

| ID | 요구사항 | 상태 |
|----|----------|------|
| AR-01 | Clean Architecture 적용 | ✅ |
| AR-02 | Adapter 패턴 기반 지갑 통합 | ✅ |
| AR-03 | Riverpod 3.0 상태관리 | ✅ |
| AR-04 | Layer별 Barrel Export | ✅ |

### 3.2 코드 품질

| ID | 요구사항 | 목표 | 현재 |
|----|----------|------|------|
| QA-01 | 유닛 테스트 커버리지 | ≥80% | ~5% |
| QA-02 | 통합 테스트 커버리지 | ≥70% | 0% |
| QA-03 | 정적 분석 경고 | 0개 | 21개 |
| QA-04 | 문서화 커버리지 | ≥90% | ~30% |

### 3.3 보안

| ID | 요구사항 | 우선순위 | 상태 |
|----|----------|----------|------|
| SE-01 | 민감 데이터 SecureStorage 저장 | P0 | ✅ |
| SE-02 | Private Key 로컬 저장 금지 | P0 | ✅ |
| SE-03 | Deep Link URI 검증 | P0 | ✅ |
| SE-04 | RPC URL 하드코딩 방지 | P1 | ⏳ |

### 3.4 성능

| ID | 요구사항 | 목표 |
|----|----------|------|
| PF-01 | 지갑 연결 응답 시간 | < 3초 |
| PF-02 | 체인 전환 응답 시간 | < 2초 |
| PF-03 | 앱 시작 시간 | < 2초 |
| PF-04 | 메모리 사용량 | < 100MB |

---

## 4. 지원 플랫폼

### 4.1 타겟 플랫폼

| 플랫폼 | 최소 버전 | 상태 |
|--------|-----------|------|
| iOS | 14.0+ | ✅ |
| Android | API 24+ (7.0) | ✅ |
| Web | Chrome 90+ | ⏳ 예정 |

### 4.2 지원 지갑

| 지갑 | 프로토콜 | EVM | Solana | 상태 |
|------|----------|-----|--------|------|
| WalletConnect | WC v2 | ✅ | ❌ | ✅ |
| MetaMask | Deep Link | ✅ | ❌ | ✅ |
| Phantom | Deep Link | ❌ | ✅ | ✅ |
| Trust Wallet | Deep Link | ✅ | ❌ | ✅ |
| Rainbow | WC v2 | ✅ | ❌ | ⏳ |
| Coinbase Wallet | WC v2 | ✅ | ❌ | ⏳ |

### 4.3 지원 체인

**EVM 체인**:
- Ethereum (Mainnet, Sepolia)
- Polygon (Mainnet, Amoy)
- BNB Chain (Mainnet, Testnet)
- Arbitrum One (Mainnet, Sepolia)
- Optimism (Mainnet, Sepolia)
- Base (Mainnet, Sepolia)
- Klaytn (Mainnet, Testnet) - 예정

**Non-EVM 체인**:
- Solana (Mainnet-beta, Devnet, Testnet)
- Sui - 예정

---

## 5. 기술 스택

### 5.1 프레임워크 & 언어
- **Flutter** 3.x (Dart 3.10+)
- **Riverpod** 3.0.3 (상태관리)
- **Freezed** 3.2.0 (불변 데이터 클래스)

### 5.2 지갑 & Web3
- **reown_appkit** 1.7.0 (WalletConnect v2)
- **web3dart** 2.7.3 (EVM 트랜잭션)
- **solana** 0.32.0 (Solana 트랜잭션)

### 5.3 저장소
- **flutter_secure_storage** 9.2.3 (민감 데이터)
- **shared_preferences** 2.3.4 (일반 설정)

### 5.4 유틸리티
- **url_launcher** 6.3.1 (Deep Link)
- **app_links** 7.0.0 (Universal Links)
- **qr_flutter** 4.1.0 (QR 코드 생성)

---

## 6. 개발 마일스톤

### Phase 1: Core Foundation (완료)
- [x] Clean Architecture 구조 설정
- [x] Wallet Adapter 인터페이스 정의
- [x] WalletConnect v2 통합
- [x] 기본 UI 구현

### Phase 2: Multi-Wallet Support (진행중)
- [x] MetaMask Adapter 구현
- [x] Phantom Adapter 구현
- [x] Trust Wallet Adapter 구현
- [x] ~~다중 지갑 동시 연결 완성~~ (범위에서 제외)
- [ ] 계정 선택 UI 완성

### Phase 3: Quality & Polish (예정)
- [ ] 테스트 커버리지 80% 달성
- [ ] CI/CD 파이프라인 구축
- [ ] 정적 분석 경고 0개
- [ ] 에러 처리 개선

### Phase 4: Production Ready (예정)
- [ ] 세션 지속성 구현
- [ ] 트랜잭션 상태 추적
- [ ] Web 플랫폼 지원
- [ ] 성능 최적화

---

## 7. 리스크 & 제약사항

### 7.1 기술적 리스크
| 리스크 | 영향도 | 대응 방안 |
|--------|--------|-----------|
| WalletConnect 서버 다운타임 | High | Fallback 메커니즘, 재시도 로직 |
| 지갑 앱 업데이트로 인한 호환성 | Medium | 버전 감지 및 적응형 처리 |
| Deep Link 스킴 충돌 | Low | 고유 스킴 사용, 검증 강화 |

### 7.2 제약사항
- WalletConnect Project ID 필요 (무료 플랜 제한 있음)
- iOS/Android 각 플랫폼별 설정 필요
- 실제 지갑 앱 필요 (시뮬레이터 제한)

---

## 8. 변경 이력

| 날짜 | 버전 | 변경 내용 | 작성자 |
|------|------|-----------|--------|
| 2025-12-08 | 1.0 | 초기 요구사항 문서 작성 | Claude |

---

## 참고 문서
- [CLAUDE.md](../CLAUDE.md) - 프로젝트 개발 가이드
- [MCP Setup Guide](./mcp-setup-guide.md) - MCP 서버 설정 가이드
- [Flutter 개발 워크플로우](./Claude%20Code를%20활용한%20Flutter%20개발%20워크플로우.md)
