# MCP Server Setup Guide

Claude Code와 Flutter 개발 환경을 위한 MCP 서버 설정 가이드입니다.

## 1. Flutter MCP (활성화됨)

50,000+ Flutter/Dart 패키지의 실시간 문서를 제공합니다.

### 설정 위치
`.claude/settings.json`에 이미 설정됨

### 기능
- pub.dev 패키지 실시간 문서 조회
- API 레퍼런스 및 사용 예제 제공
- 할루시네이션 방지를 위한 공식 문서 기반 응답

### 사용 예시
```
"WalletConnect reown_appkit 패키지 사용법 알려줘"
"flutter_riverpod 3.0 마이그레이션 가이드"
```

---

## 2. DCM (Dart Code Metrics) MCP

코드 품질 분석, 미사용 코드 감지, 메트릭 계산을 제공합니다.

### 설치 방법

DCM은 유료 라이선스가 필요합니다. 무료 체험판 또는 라이선스 구매 후:

```bash
# Dart pub global로 설치
dart pub global activate dcm

# 또는 brew로 설치 (macOS)
brew install dcm-cli/dcm/dcm
```

### MCP 설정 추가

라이선스 활성화 후 `.claude/settings.json`에 추가:

```json
{
  "mcpServers": {
    "flutter-mcp": {
      "command": "npx",
      "args": ["flutter-mcp"]
    },
    "dcm": {
      "command": "dcm",
      "args": ["mcp"],
      "description": "Dart Code Metrics - code analysis and unused code detection"
    }
  }
}
```

### DCM 기능
- 미사용 코드/파일 감지
- 코드 복잡도 메트릭
- 자동 코드 수정 제안
- 커스텀 린트 규칙

---

## 3. 무료 대안: analysis_options.yaml 강화

DCM 없이도 코드 품질을 높일 수 있습니다:

```yaml
# analysis_options.yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  errors:
    unused_element: warning
    unused_field: warning
    unused_local_variable: warning
    dead_code: warning
  exclude:
    - "**/*.g.dart"
    - "**/*.freezed.dart"

linter:
  rules:
    - always_declare_return_types
    - avoid_empty_else
    - avoid_print
    - avoid_unnecessary_containers
    - prefer_const_constructors
    - prefer_const_declarations
    - prefer_final_fields
    - prefer_final_locals
    - sort_constructors_first
    - use_key_in_widget_constructors
```

---

## 4. MCP Flutter Toolkit (선택사항)

실행 중인 Flutter 앱과 연동하여 스크린샷, 에러 모니터링 등을 제공합니다.

### 설치
```bash
flutter pub add mcp_toolkit
```

### 앱에 통합
```dart
import 'package:mcp_toolkit/mcp_toolkit.dart';

void main() {
  McpToolkit.initialize();
  runApp(const MyApp());
}
```

---

## 참고
- [Flutter MCP GitHub](https://github.com/kitsuyui/flutter-mcp)
- [DCM 공식 문서](https://dcm.dev/)
- [MCP 프로토콜 사양](https://modelcontextprotocol.io/)
