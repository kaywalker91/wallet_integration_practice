import React from 'react';

const MetaMaskMultiWalletFlow = () => {
  const ArrowDown = () => (
    <div className="flex justify-center my-2">
      <svg width="24" height="32" viewBox="0 0 24 32" fill="none">
        <path d="M12 0V28M12 28L4 20M12 28L20 20" stroke="#6366f1" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round"/>
      </svg>
    </div>
  );

  const Step = ({ number, title, items, color, icon }) => (
    <div className={`relative rounded-2xl p-5 shadow-lg border-2 ${color} bg-white`}>
      <div className="absolute -top-4 -left-2 w-10 h-10 rounded-full bg-indigo-600 text-white flex items-center justify-center font-bold text-lg shadow-md">
        {number}
      </div>
      <div className="ml-6">
        <div className="flex items-center gap-2 mb-3">
          <span className="text-2xl">{icon}</span>
          <h3 className="text-lg font-bold text-gray-800">{title}</h3>
        </div>
        <ul className="space-y-2">
          {items.map((item, idx) => (
            <li key={idx} className="flex items-start gap-2 text-sm text-gray-600">
              <span className="text-indigo-500 mt-0.5">•</span>
              <span>{item}</span>
            </li>
          ))}
        </ul>
      </div>
    </div>
  );

  const CodeBlock = ({ code }) => (
    <div className="bg-gray-900 rounded-lg p-3 mt-2 overflow-x-auto">
      <code className="text-xs text-green-400 font-mono whitespace-pre">{code}</code>
    </div>
  );

  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-50 to-indigo-50 p-6">
      <div className="max-w-4xl mx-auto">
        {/* Header */}
        <div className="text-center mb-8">
          <div className="inline-flex items-center gap-3 mb-3">
            <div className="w-12 h-12 bg-orange-500 rounded-xl flex items-center justify-center">
              <span className="text-2xl">🦊</span>
            </div>
            <span className="text-3xl font-bold text-gray-400">+</span>
            <div className="w-12 h-12 bg-indigo-600 rounded-xl flex items-center justify-center">
              <span className="text-white font-bold">iL</span>
            </div>
          </div>
          <h1 className="text-2xl font-bold text-gray-800 mb-2">
            MetaMask 다중 지갑 연동 플로우
          </h1>
          <p className="text-gray-500 text-sm">iLity Hub × WalletConnect v2</p>
        </div>

        {/* Flow Steps */}
        <div className="space-y-2">
          {/* Step 1 */}
          <Step
            number="1"
            title="최초 연결 (WalletConnect v2)"
            icon="🔗"
            color="border-blue-300"
            items={[
              "사용자가 '지갑 연결' 버튼 클릭",
              "WalletConnect QR 코드 또는 Deep Link 생성",
              "MetaMask 앱에서 'Edit accounts' 클릭 안내",
              "사용자가 연결할 계정들을 체크박스로 선택"
            ]}
          />

          <ArrowDown />

          {/* Step 2 */}
          <Step
            number="2"
            title="연결된 계정 목록 조회"
            icon="📋"
            color="border-green-300"
            items={[
              "WalletConnect 세션에서 accounts 배열 획득",
              "session.namespaces['eip155'].accounts",
              "예: [\"eip155:1:0x123...\", \"eip155:1:0x456...\"]",
              "각 계정의 체인 정보와 주소 파싱"
            ]}
          />

          <ArrowDown />

          {/* Step 3 */}
          <Step
            number="3"
            title="iLity Hub 서버에 등록"
            icon="☁️"
            color="border-purple-300"
            items={[
              "POST /api/v1/profile/me/wallets 호출",
              "각 계정별로 개별 등록 요청",
              "지갑 주소, 체인 ID, 지갑 타입 저장",
              "포트폴리오 통합 조회 가능"
            ]}
          />

          <ArrowDown />

          {/* Step 4 */}
          <Step
            number="4"
            title="추가 지갑 연결 (선택)"
            icon="➕"
            color="border-amber-300"
            items={[
              "프로필 > 지갑 관리 화면",
              "'지갑 추가' 버튼으로 새 연결",
              "다른 SRP의 지갑도 추가 가능",
              "accountsChanged 이벤트로 변경 감지"
            ]}
          />
        </div>

        {/* Technical Details */}
        <div className="mt-8 grid md:grid-cols-2 gap-4">
          {/* Code Example */}
          <div className="bg-white rounded-2xl p-5 shadow-lg border border-gray-200">
            <h3 className="font-bold text-gray-800 mb-3 flex items-center gap-2">
              <span className="text-xl">💻</span> 핵심 코드
            </h3>
            <CodeBlock code={`// WalletConnect 연결 후 계정 조회
final session = await web3App.connect(...);
final accounts = session
  .namespaces['eip155']
  ?.accounts ?? [];

// 각 계정 등록
for (final account in accounts) {
  await api.post('/profile/me/wallets', 
    {'address': account});
}`} />
          </div>

          {/* API Reference */}
          <div className="bg-white rounded-2xl p-5 shadow-lg border border-gray-200">
            <h3 className="font-bold text-gray-800 mb-3 flex items-center gap-2">
              <span className="text-xl">🔌</span> 관련 API
            </h3>
            <div className="space-y-2 text-sm">
              <div className="flex items-center gap-2 p-2 bg-green-50 rounded-lg">
                <span className="px-2 py-0.5 bg-green-500 text-white text-xs rounded font-mono">GET</span>
                <code className="text-gray-700">/profile/me/wallets</code>
              </div>
              <div className="flex items-center gap-2 p-2 bg-blue-50 rounded-lg">
                <span className="px-2 py-0.5 bg-blue-500 text-white text-xs rounded font-mono">POST</span>
                <code className="text-gray-700">/profile/me/wallets</code>
              </div>
              <div className="flex items-center gap-2 p-2 bg-red-50 rounded-lg">
                <span className="px-2 py-0.5 bg-red-500 text-white text-xs rounded font-mono">DEL</span>
                <code className="text-gray-700">/profile/me/wallets/{'{id}'}</code>
              </div>
            </div>
          </div>
        </div>

        {/* Important Notes */}
        <div className="mt-6 bg-amber-50 rounded-2xl p-5 border border-amber-200">
          <h3 className="font-bold text-amber-800 mb-3 flex items-center gap-2">
            <span className="text-xl">⚠️</span> 주의사항
          </h3>
          <div className="grid md:grid-cols-2 gap-3 text-sm text-amber-900">
            <div className="flex items-start gap-2">
              <span>📱</span>
              <span>MetaMask는 기본적으로 활성 계정 1개만 반환</span>
            </div>
            <div className="flex items-start gap-2">
              <span>👆</span>
              <span>사용자가 'Edit accounts'로 다중 선택 필요</span>
            </div>
            <div className="flex items-start gap-2">
              <span>🔄</span>
              <span>accountsChanged 이벤트 리스닝 필수</span>
            </div>
            <div className="flex items-start gap-2">
              <span>✍️</span>
              <span>트랜잭션 서명 시 계정 명시 필요</span>
            </div>
          </div>
        </div>

        {/* Footer */}
        <div className="mt-6 text-center text-xs text-gray-400">
          iLity Hub • Wallet Integration Flow • WalletConnect v2
        </div>
      </div>
    </div>
  );
};

export default MetaMaskMultiWalletFlow;
