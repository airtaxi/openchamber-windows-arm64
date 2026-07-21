# OpenChamber Windows ARM64

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)


🌐 [English](README.md) | 한국어

OpenChamber Windows ARM64는 데스크톱 AI 코딩 에이전트인 [OpenChamber](https://github.com/openchamber/openchamber)의 Windows ARM64 NSIS 인스톨러를 자동으로 생성하는 비공식 빌드 파이프라인입니다. GitHub Actions에서 실행되며, 업스트림 저장소의 새 릴리즈를 6시간마다 폴링하고, 네이티브 Windows ARM 러너에서 ARM64 인스톨러를 빌드한 뒤 GitHub Release를 게시하고 Scoop bucket 매니페스트를 갱신하여 자동 업데이트를 지원합니다.

이 프로젝트는 OpenChamber가 공식 Windows ARM64 빌드를 제공할 때까지 유지될 예정입니다. 공식 ARM64 릴리즈가 배포되면 워크플로우 실행을 중단하고 이 저장소를 archive 처리할 예정입니다.

## Disclaimer

이 프로젝트는 OpenChamber 팀과 제휴 관계가 없으며, 보증하거나 후원하거나 공식 지원하는 프로젝트가 아닙니다. Windows on ARM 호환성을 위한 독립 커뮤니티 도구입니다.

OpenChamber는 각 소유자의 상표입니다. 그 외 모든 상표는 각 소유자의 자산입니다.

## Release에서 빠르게 설치

Scoop 사용:

```powershell
scoop bucket add openchamber-arm64 https://github.com/airtaxi/openchamber-windows-arm64
scoop install openchamber-arm64
```

일반적인 업데이트:

```powershell
scoop update
scoop update openchamber-arm64
```

또는 [GitHub Releases](https://github.com/airtaxi/openchamber-windows-arm64/releases) 페이지에서 인스톨러를 직접 다운로드하여 실행할 수 있습니다.

## 작동 방식

1. **정기 확인** — 6시간마다 워크플로우가 업스트림 OpenChamber 저장소의 최신 태그를 가져와 이 저장소의 최신 릴리즈와 비교합니다.
2. **빌드** — 새 태그가 발견되거나 수동 빌드가 트리거되면, 해당 태그의 소스를 클론하고 Bun으로 의존성을 설치한 뒤 ARM64 호환 패치를 적용하고, 네이티브 Windows ARM 러너에서 electron-builder를 통해 NSIS 인스톨러를 빌드합니다.
3. **릴리즈** — 빌드된 인스톨러를 아카이브하고 해시값이 포함된 Scoop 매니페스트를 생성한 뒤 GitHub Release를 만듭니다.
4. **Scoop 업데이트** — Scoop bucket 매니페스트를 저장소에 커밋하여 `scoop update`가 새 버전을 자동으로 인식합니다.

## 적용되는 패치

빌드는 `bun install` 이후 클론된 소스에 다음 패치를 적용합니다:

- **prepare-opencode-cli.mjs** — 작동하지 않는 ARM64 바이너리 대신 x64-baseline OpenCode CLI 바이너리를 강제 사용합니다 (Windows ARM에서 x64 에뮬레이션으로 실행).
- **node-pty binding.gyp** — CI 툴체인에 ARM64 Spectre 라이브러리가 없으므로 Spectre mitigation을 비활성화합니다 (`Spectre` → `false`).
- **opencode/routes.js** — `/api/opencode/upgrade` 및 `/api/opencode/upgrade-status` 엔드포인트를 비활성화하여 OpenCode가 깨진 ARM64 바이너리로 자가 업그레이드하는 것을 방지합니다.
- **useUIStore.ts** — `showOpenCodeUpdateNotifications` 기본값을 `false`로 설정하여 업데이트 토스트가 표시되지 않도록 합니다.
- **OpenCodeCliSettings.tsx** — 설정 페이지에서 업데이트 알림 체크박스를 숨깁니다 (기존 `<label>` 마크업과 v1.16.2에서 도입된 `SettingsCheckboxRow` 마크업 모두 지원).
- **settings/search.ts** — 설정 검색 인덱스에서 업데이트 알림 항목을 제거합니다.

패치 앵커를 찾지 못하면(예: 업스트림 리팩터링) 빌드를 즉시 중단하여, 패치가 누락된 인스톨러가 조용히 배포되지 않도록 합니다.



## 요구사항 (로컬 빌드 시)

- Windows on ARM 장치 (또는 Windows ARM CI 러너).
- PowerShell 7 (`pwsh`).
- [Bun](https://bun.sh).
- "Desktop development with C++" 워크로드가 설치된 Visual Studio 2022 (ARM64 toolset 포함).
- `PATH`의 NSIS (electron-builder NSIS 타겟용).
- `PATH`의 Node.js 및 Git.

## 출력물

빌드가 성공하면 다음 파일이 생성됩니다:

- `dist/OpenChamber-<version>-win-arm64.exe` — NSIS 인스톨러.
- `dist.7z` — 릴리즈 업로드용 아카이브.
- `bucket/openchamber-arm64.json` — 해시가 포함된 Scoop 매니페스트.

## 라이선스

OpenChamber Windows ARM64는 [MIT 라이선스](LICENSE)로 배포됩니다.

## 제작자

[이호원 (airtaxi)](https://github.com/airtaxi)이 만들었습니다.