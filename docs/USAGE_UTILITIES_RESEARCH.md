# AI 구독 사용량 조회 유틸 조사

조사일: 2026-10-08. GitHub README, 인증·조회·파싱 코드 및 라이선스를 확인했다. 조사 대상 프로그램을 설치하거나 실행하지 않았으며, Bubble Tax Bar 구현은 변경하지 않았다. 아래 추천은 코드 검토에 근거한 판단이다.

## Bubble Tax Bar에 맞는 후보

| 프로젝트 | 수집 방식 | 참고할 부분 | 한계 / 라이선스 |
| --- | --- | --- | --- |
| [steipete/CodexBar](https://github.com/steipete/CodexBar) | 서비스별 OAuth, CLI, 웹 세션 등으로 서버 쿼타 조회 | 현재 Bubble Tax Bar 수집 기반 유지. 여러 서비스의 잔여량·리셋 시각 정규화 | 공개 API와 내부 API가 섞임. 소스 우선순위는 서비스별로 다름 / MIT |
| [tddworks/ClaudeBar](https://github.com/tddworks/ClaudeBar) | Swift 앱, 선언형 provider JSON, OAuth·Billing API 등 | Apple 네이티브 구조와 provider 확장 방식. Copilot 공식 Billing API 연동 | 일부 한도·사용량은 수동 설정 가능. 그대로 도입하면 무입력 제품 요구와 충돌 / Apache-2.0 |
| [mathdevie/devie-ai-quota-tracker](https://github.com/mathdevie/devie-ai-quota-tracker) | 자체 OAuth 로그인, Claude·Codex·Copilot 서버 조회 | 명시적 계정 연결, 여러 계정, 플랜 자동 파싱, Enterprise·무제한 처리 | Tauri/Rust. 기존 CLI 로그인 자동 재사용 방식은 아님. 작은 프로젝트 / MIT |
| [nerlichman/claudebar](https://github.com/nerlichman/claudebar) | Claude OAuth + Claude Code statusline의 rate_limits | OAuth 장애 시에도 실제 쿼타를 로컬에서 읽는 fallback | statusline 데이터는 터미널 세션이 실행돼야 갱신. 훅 설치가 필요 / MIT |
| [ccusage/ccusage](https://github.com/ccusage/ccusage) | 로컬 에이전트 로그의 토큰·기간별 비용 분석 | 활동 증거와 API 가격 기준 비용 추정 | 토큰 수만으로 구독 잔여 쿼타를 계산할 수 없음. 비용도 실제 구독료가 아님 / MIT¹ |
| [kollinger/llm-usage-dashboard](https://github.com/kollinger/llm-usage-dashboard) | 서버 쿼타와 로컬 로그를 구분하고 변화 이력 저장 | 리셋 이력, 계정별 기록, 수동 리셋과 자연 리셋 구분 | JavaScript 대시보드. 작은 프로젝트이므로 알고리즘 참고 대상으로 적합 / MIT |
| [nguyenphutrong/quotio](https://github.com/nguyenphutrong/quotio) | 여러 계정·서비스의 인증 및 쿼타 조회 | 다계정 관리와 provider parser | 프록시·라우팅·자동 전환까지 포함해 Bubble Tax Bar보다 범위가 큼 / MIT |
| [ousid/claudebar](https://github.com/ousid/claudebar) | Claude OAuth PKCE, Keychain, usage endpoint | user:profile만 요청하는 작은 OAuth 구현 | 고정 client ID를 사용하므로 자체 등록된 공개 OAuth 앱의 예제로 단정하면 안 됨 / MIT |

¹ ccusage의 루트 LICENSE는 다른 파일을 가리킨다. 실제 [apps/ccusage/LICENSE](https://github.com/ccusage/ccusage/blob/88ed26d611597b3910c800f4a83e76360e9cd245/apps/ccusage/LICENSE)는 MIT다.

추가로 [Dicklesworthstone/coding_agent_usage_tracker](https://github.com/Dicklesworthstone/coding_agent_usage_tracker)도 확인했다. CLI 정규화 구조는 참고할 수 있지만 [LICENSE](https://github.com/Dicklesworthstone/coding_agent_usage_tracker/blob/9678b661d2adc2605bec8d65ca7ca206c5ef0185/LICENSE)에 별도 제한 조항이 있어 일반 MIT 코드 재사용 후보에서는 제외했다.

## 실제로 무엇을 호출하나

서버에서 받는 값이라고 모두 문서화된 공개 API인 것은 아니다. 세 가지 경로를 별도로 취급해야 한다.

1. **문서화된 공개 API**: GitHub Billing API 등. 권한·결제 주체가 맞아야 조회된다.
2. **서비스 클라이언트용 경로**: Claude OAuth usage, ChatGPT backend usage, Copilot internal API 등. 여러 유틸이 사용하는 경로지만, 제3자 공개 API 지원을 보장한다는 의미는 아니다.
3. **로컬 데이터**: CLI가 받은 rate limit, statusline의 실제 quota, 로컬 토큰 로그. 실제 쿼타와 단순 활동 로그를 구분해야 한다.

| 서비스 / 경로 | 코드에서 확인한 호출 | 인증 / 의미 |
| --- | --- | --- |
| Claude OAuth | GET https://api.anthropic.com/api/oauth/usage | OAuth 토큰. 사용률·기간별 리셋 조회 |
| Claude 웹 | claude.ai/api/organizations/{orgID}/usage | 웹 세션 쿠키. 조직 식별 필요 |
| Codex / ChatGPT | GET https://chatgpt.com/backend-api/wham/usage | 계정 OAuth 토큰. 전체 ChatGPT 기능의 종합 사용률로 확장해 해석하면 안 됨 |
| Codex CLI | codex app-server의 account/read, account/rateLimits/read | CLI 인증을 이용한 계정 및 쿼타 조회 |
| Copilot 내부 | GET https://api.github.com/copilot_internal/user | GitHub 토큰. quota_snapshots의 entitlement·remaining 등 |
| Copilot Billing | 개인 / 조직 / Enterprise Billing API | 공식 문서와 결제 범위에 맞는 권한 필요 |

근거: [CodexBar Claude 문서](https://github.com/steipete/CodexBar/blob/a88f0819d868327680b8ccabae59b72a9cbc06f3/docs/claude.md), [Codex 문서](https://github.com/steipete/CodexBar/blob/a88f0819d868327680b8ccabae59b72a9cbc06f3/docs/codex.md), [Devie Copilot 구현](https://github.com/mathdevie/devie-ai-quota-tracker/blob/9f2ea2542f0415b186dd58d300721654d6b52eee/src-desktop/src/oauth/copilot.rs).

## 인증과 Enterprise 처리에서 가져올 점

Devie는 Claude·Codex·Copilot을 앱에서 직접 로그인시키고 플랜 및 계정을 파싱한다. Copilot의 unlimited와 entitlement 누락을 구분하며, Codex의 ent26·enterprise_cbp_automation·enterprise_cbp_usage_based 같은 별칭도 Enterprise로 처리한다. 단순히 문자열에 enterprise가 있는지 검사하는 Bubble Tax Bar의 현재 분류는 이 별칭을 놓칠 수 있다. [Codex 구현](https://github.com/mathdevie/devie-ai-quota-tracker/blob/9f2ea2542f0415b186dd58d300721654d6b52eee/src-desktop/src/oauth/codex.rs)

OAuth 예제의 요청 scope도 그대로 복사하지 말아야 한다. ousid 구현은 user:profile만 요청하지만, 다른 구현에는 추론·세션·API 키 생성 관련 scope도 있다. 필요한 조회 기능에 맞춰 범위를 검토해야 한다. 또한 기존 CLI 토큰을 재사용할 때는 갱신과 저장의 소유권을 CLI와 충돌시키지 않는 설계가 필요하다. [ousid OAuth 구현](https://github.com/ousid/claudebar/blob/d8add82ead3d5caaa2962305c48332f89ccd12f0/Sources/ClaudeBar/OAuth.swift)

GitHub 공식 문서는 개인 Billing API가 **개인이 직접 결제한 Copilot** 사용량만 반환한다고 명시한다. 조직·Enterprise가 결제하는 좌석은 조직·Enterprise 경로를 사용해야 한다. 조직 보고서는 관리자 및 Administration read 권한이 필요하다. 결제 사용량 보고서만으로 남은 총 할당량까지 자동 확보된다고 가정하면 안 된다. [공식 Billing 문서](https://docs.github.com/en/rest/billing/usage?apiVersion=2026-03-10)

따라서 권한 없음, 조회 실패, 개인 결제 범위 밖의 결과를 0% used / 100% left로 변환하면 안 된다. 조직 공용 쿼타와 개인 좌석의 미사용도 다른 의미다. Enterprise 문구는 확인된 조직 플랜과 데이터 범위를 바탕으로 선택해야 한다.

## Bubble Tax Bar의 Left / 버려진 쿼타에 직접 유용한 구현

**Claude 로컬 fallback**: nerlichman/claudebar는 statusline에서 실제 rate_limits를 파일로 받아 OAuth 실패·429 시 활용한다. 로컬 토큰 수로 쿼타를 추측하는 것보다 제품 요구에 가깝다. 훅 설치는 기존 설정을 보존하는 별도 연결 기능으로 다루고, 수집 시각을 표시해야 한다. [OAuth fetcher](https://github.com/nerlichman/claudebar/blob/70338f013e4500603982eb9dc2826bc3777fcbbe/Sources/ClaudeBar/Usage/OAuthUsageFetcher.swift)

**리셋 시 미사용 이력**: llm-usage-dashboard는 quota 변화만 저장하며 계정 식별, 리셋 시각의 오차, 수동 reset credit 사용을 구분한다. 자연 만료로 버려진 잔여량을 계산하는 데 특히 유용하다. [reset history 구현](https://github.com/kollinger/llm-usage-dashboard/blob/b7480e16d4b110be33cd6360a75c5bc86742febd/lib/codex-reset-history.js)

Bubble Tax Bar 적용 판단: 현재 Left는 서버의 remaining 또는 utilization으로 표시하고, 종료된 기간의 미사용은 마지막 유효 관측값·관측 시각과 함께 저장한다. 리셋 직전 표본이 없으면 정확한 만료 잔여량은 알 수 없으므로 추정 또는 unknown으로 표시한다. 수동 리셋, 계정·플랜 변경, 무제한 및 초과 사용은 별도로 처리한다. 월간 결제 기간과 5시간·주간 quota 기간도 동일하게 취급하지 않는다.

## 추천 순서

1. **CodexBar 기반 유지**: 이미 통합된 조회 엔진을 활용하고 서비스별 데이터 출처를 명확히 한다.
2. **Devie 인증·플랜 파싱 참고**: 명시적 계정 연결과 Enterprise 별칭 처리를 보완한다.
3. **Claude statusline fallback 추가 검토**: 실제 쿼타가 있는 로컬 데이터를 우선한다.
4. **reset history 강화**: 계정별 종료 기간의 미사용을 쌓아 앱의 해지 유도 근거로 사용한다.
5. **ccusage는 보조 자료**: 쿼타를 못 받는 서비스의 활동·토큰 증거로만 활용한다.

앱 전체를 교체하거나 Quotio의 프록시 기능을 도입할 필요는 없다. 조사 대상의 인증 흐름을 실행 검증하지 않았으므로, 실제 통합 시 provider별 응답과 계정 범위를 확인해야 한다.
